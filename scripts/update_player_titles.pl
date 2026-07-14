#!/usr/bin/perl

# This script reads latest.txt (fixed-width) and populates the title and
# norms columns for matching players in the database.  Matching is done by
# anchoring the truncated 20-character name from the file against the
# start of the full pretty name (players.name), falling back to a LIKE
# query, and finally to the player_alt_names table.
#
# title values: 'M', 'IM', 'GM', or NULL
# norms values: '*', '**', or NULL  (a value of '--' becomes NULL)

use strict;
use warnings;
use DBI;

use lib './modules';
use Constants;

require './scripts/utils.pl';

# Column definitions for latest.txt (1-indexed character positions)
use constant COL_NICK_START => 0;     #  0-3   nickname (4 chars)
use constant COL_NICK_END   => 3;
use constant COL_CTRY_START => 5;     #  5-7   country trigraph (3 chars)
use constant COL_CTRY_END   => 7;
use constant COL_NAME_START => 9;     #  9-28  name, truncated to 20 chars
use constant COL_NAME_END   => 28;
use constant COL_GAMES_START => 30;   # 30-33  total games played (4 chars)
use constant COL_GAMES_END   => 33;
use constant COL_RATING_START => 35;  # 35-38  rating (4 chars)
use constant COL_RATING_END   => 38;
use constant COL_DATE_START   => 40;  # 40-47  last played date (8 chars)
use constant COL_DATE_END     => 47;
use constant COL_RD_START     => 49;  # 49-51  rating deviation (3 chars)
use constant COL_RD_END       => 51;
use constant COL_TITLE_START  => 53;  # 53-54  title (2 chars)
use constant COL_TITLE_END    => 54;
use constant COL_NORMS_START  => 56;  # 56-57  norms (2 chars)
use constant COL_NORMS_END    => 57;

unless (caller)
{
  update_player_titles();
}

sub update_player_titles
{
  my $database_name = get_environment_name(Constants::DATABASE_NAME);
  my $host_name     = Constants::DATABASE_HOST_NAME;
  my $user_name     = Constants::DATABASE_USER_NAME;
  my $password      = Constants::DATABASE_PASSWORD;
  my $players_tn    = Constants::PLAYERS_TABLE_NAME;
  my $alt_names_tn  = Constants::PLAYER_ALT_NAMES_TABLE_NAME;

  my $titles_file = Constants::INPUT_DIR . "/latest.txt";

  if (!-e $titles_file)
  {
    die "ERROR: Titles file not found: $titles_file\n";
  }

  my $dbh = DBI->connect("DBI:mysql:database=$database_name;host=$host_name",
                         $user_name, $password,
                         {'RaiseError' => 1});

  open my $fh, "<:encoding(utf8)", $titles_file or die "Cannot open $titles_file: $!";

  # Read and skip the header row
  my $header = <$fh>;

  my $updated = 0;
  my $not_found = 0;
  my $duplicate = 0;
  my $skipped = 0;
  my $line_num = 1;  # header is line 1

  # Pre-fetch all player names into a hash: pretty_name => player_id
  my $sth = $dbh->prepare("SELECT id, name FROM $players_tn");
  $sth->execute();
  my %name_to_id;
  while (my @row = $sth->fetchrow_array())
  {
    $name_to_id{$row[1]} = $row[0];
  }

  # Build a mapping: alt_name (sanitized) => player_id
  my $alt_sth = $dbh->prepare("SELECT alt_name, player_id FROM $alt_names_tn");
  $alt_sth->execute();
  my %alt_name_to_id;
  while (my @row = $alt_sth->fetchrow_array())
  {
    $alt_name_to_id{$row[0]} = $row[1];
  }

  my $update_sth = $dbh->prepare(
    "UPDATE $players_tn SET title = ?, norms = ? WHERE id = ?"
  );

  while (my $line = <$fh>)
  {
    $line_num++;
    chomp $line;
    $line =~ s/\r$//;  # Remove Windows line endings

    # Must be at least long enough to hold the norms column
    next if length($line) < COL_NORMS_END + 1;

    # Extract fixed-width fields
    my $file_nick  = substr($line, COL_NICK_START,  COL_NICK_END  - COL_NICK_START  + 1);
    my $file_ctry  = substr($line, COL_CTRY_START,  COL_CTRY_END  - COL_CTRY_START  + 1);
    my $file_name  = substr($line, COL_NAME_START,  COL_NAME_END  - COL_NAME_START  + 1);
    my $file_games = substr($line, COL_GAMES_START, COL_GAMES_END - COL_GAMES_START + 1);
    my $file_rating= substr($line, COL_RATING_START,COL_RATING_END- COL_RATING_START+ 1);
    my $file_date  = substr($line, COL_DATE_START,  COL_DATE_END  - COL_DATE_START  + 1);
    my $file_rd    = substr($line, COL_RD_START,    COL_RD_END    - COL_RD_START    + 1);
    my $file_title = substr($line, COL_TITLE_START, COL_TITLE_END - COL_TITLE_START + 1);
    my $file_norms = substr($line, COL_NORMS_START, COL_NORMS_END - COL_NORMS_START + 1);

    # Trim whitespace from each field
    $file_nick   =~ s/^\s+|\s+$//g;
    $file_ctry   =~ s/^\s+|\s+$//g;
    $file_name   =~ s/^\s+|\s+$//g;
    $file_games  =~ s/^\s+|\s+$//g;
    $file_rating =~ s/^\s+|\s+$//g;
    $file_date   =~ s/^\s+|\s+$//g;
    $file_rd     =~ s/^\s+|\s+$//g;
    $file_title  =~ s/^\s+|\s+$//g;
    $file_norms  =~ s/^\s+|\s+$//g;

    # Skip rows without a name
    if (!$file_name)
    {
      $skipped++;
      next;
    }

    # Validate title
    if ($file_title ne 'M' && $file_title ne 'IM' && $file_title ne 'GM' && $file_title ne '--' && $file_title)
    {
      printf "WARNING:  Invalid title '%s' for '%s' at line %d (skipping)\n",
             $file_title, $file_name, $line_num;
      $skipped++;
      next;
    }

    # Convert title: '--' or blank becomes undef (NULL)
    if ($file_title eq '--' || !$file_title)
    {
      $file_title = undef;
    }

    # Convert norms: '--' becomes undef (NULL), '*' and '**' stay as-is
    my $db_norms;
    if ($file_norms eq '--' || !$file_norms)
    {
      $db_norms = undef;
    }
    elsif ($file_norms eq '*' || $file_norms eq '**')
    {
      $db_norms = $file_norms;
    }
    else
    {
      printf "WARNING:  Invalid norms value '%s' for '%s' at line %d (skipping)\n",
             $file_norms, $file_name, $line_num;
      $skipped++;
      next;
    }

    # --- Player lookup ---
    # The name in latest.txt is truncated to 20 characters, so we need to
    # match against the start of the full pretty name in the database.
    my $player_id;

    # Strategy 1: exact match on the 20-char prefix of a pretty name
    foreach my $db_name (keys %name_to_id)
    {
      my $prefix = substr($db_name, 0, 20);
      if ($prefix eq $file_name)
      {
        $player_id = $name_to_id{$db_name};
        last;
      }
    }

    # Strategy 2: if no prefix match found, try a LIKE query
    if (!$player_id)
    {
      my $like_sth = $dbh->prepare(
        "SELECT id, name FROM $players_tn WHERE name LIKE ?"
      );
      # Escape underscores and percent signs in the name (though unlikely),
      # then append '%' to match any longer names
      my $safe_name = $file_name;
      $safe_name =~ s/([%_])/\\$1/g;
      $like_sth->execute("$safe_name%");
      my @like_results;
      while (my @row = $like_sth->fetchrow_array())
      {
        push @like_results, \@row;
      }

      if (scalar @like_results == 1)
      {
        $player_id = $like_results[0][0];
      }
      elsif (scalar @like_results > 1)
      {
        printf "ERROR:    Multiple players match prefix '%s' at line %d (%d matches)\n",
               $file_name, $line_num, scalar @like_results;
        $duplicate++;
        next;
      }
    }

    # Strategy 3: try alt_name lookup with sanitized name
    if (!$player_id)
    {
      my $sanitized = $file_name;
      $sanitized = uc $sanitized;
      $sanitized =~ s/[^A-Z]//g;
      $player_id = $alt_name_to_id{$sanitized};
    }

    if (!$player_id)
    {
      printf "ERROR:    Player not found for '%s' at line %d\n",
             $file_name, $line_num;
      $not_found++;
      next;
    }

    # Skip the update if both title and norms are NULL in the file
    # and already NULL in the database — no change needed
    # First, need to prepare the check statement (done after the update_sth)

    if (!$file_title && !$db_norms)
    {
      # Both are NULL from the file; check if DB already has NULL,NULL
      my $check_sth = $dbh->prepare(
        "SELECT title, norms FROM $players_tn WHERE id = ?"
      );
      $check_sth->execute($player_id);
      my ($db_title, $db_norms_val) = $check_sth->fetchrow_array();
      if (!$db_title && !$db_norms_val)
      {
        # Already NULL,NULL in DB — nothing to do
        next;
      }
    }

    # Execute the update
    $update_sth->execute($file_title, $db_norms, $player_id);
    $updated++;
  }

  close $fh;

  printf "Player titles updated: %d\n",      $updated;
  printf "Players not found:    %d\n",       $not_found;
  printf "Duplicate matches:    %d\n",       $duplicate;
  printf "Skipped (bad data):   %d\n",       $skipped;

  if ($not_found || $duplicate)
  {
    print "WARNING: One or more title entries could not be matched to database players.\n";
  }
}

1;

__END__

=head1 SYNOPSIS

 perl ./scripts/update_player_titles.pl

Reads inputs/latest.txt (fixed-width format) and updates the title and
norms columns in the players table for matching players.

=cut
