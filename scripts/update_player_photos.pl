#!/usr/bin/perl

# This script reads player photo data from multiple sources and updates
# the photo column for matching players in the database. Priority (highest
# to lowest): wespa_biodata.csv, centrestar_photos.txt, photos.txt.
#
# Usage (run in order of priority):
#   perl ./scripts/update_player_photos.pl photos.txt
#   perl ./scripts/update_player_photos.pl centrestar_photos.txt
#   perl ./scripts/update_player_photos.pl wespa_biodata.csv
#
# photos.txt / centrestar_photos.txt format (tab-separated, no header):
#   Firstname  Lastname  RelativePath
#
# wespa_biodata.csv format:
#   ID,Firstname,Middlename,Lastname,Email,Country,Photo,Headshot
#
# Output is written to photo_updates.log (clobbered each run).

use strict;
use warnings;
use DBI;
use Text::CSV_XS;

use lib './modules';
use Constants;

unless (caller)
{
  main();
}

sub open_log
{
  my $log_file = '/app/logs/photo_updates.log';
  open my $lfh, '>', $log_file or die "Cannot open $log_file for writing: $!";
  return $lfh;
}

sub main
{
  my $input_file = shift @ARGV;

  if (!$input_file)
  {
    die "Usage: perl $0 <input_file>\n";
  }

  if (!-e $input_file)
  {
    die "ERROR: File not found: $input_file\n";
  }

  my $dbh = connect_to_database();
  my $lfh = open_log();

  # Determine file type by extension and content
  if ($input_file =~ /\.csv$/i)
  {
    process_csv($dbh, $input_file, $lfh);
  }
  else
  {
    process_text_file($dbh, $input_file, $lfh);
  }

  close $lfh;
}

# Process a wespa_biodata.csv file
sub process_csv
{
  my ($dbh, $csv_file, $lfh) = @_;

  my $csv = Text::CSV_XS->new({ binary => 1, auto_diag => 1 });

  open my $fh, "<:encoding(utf8)", $csv_file or die "Cannot open $csv_file: $!";

  # Read header
  my $headers = $csv->getline($fh);

  # Find column indices
  my %col_idx;
  foreach my $i (0 .. $#$headers)
  {
    $col_idx{ $headers->[$i] } = $i;
  }

  foreach my $col (qw(Firstname Lastname Email Photo))
  {
    if (!exists $col_idx{$col})
    {
      die "ERROR: Required column '$col' not found in CSV header\n";
    }
  }

  my $updated = 0;
  my $not_found = 0;
  my $skipped = 0;
  my $multiple = 0;

  while (my $row = $csv->getline($fh))
  {
    my $firstname  = $row->[$col_idx{Firstname}] // '';
    my $middlename = $row->[$col_idx{Middlename}] // '';
    my $lastname   = $row->[$col_idx{Lastname}] // '';
    my $email      = $row->[$col_idx{Email}] // '';
    my $photo_url  = $row->[$col_idx{Photo}] // '';

    # Skip rows without a photo URL
    if (!$photo_url)
    {
      $skipped++;
      next;
    }

    # Build the display name as it appears in the players table
    # The players table stores names in "Pretty" format (e.g. "Conrad Bassett-Bouchard")
    # Try several name constructions
    my @candidate_names;
    my $pretty_name;

    if ($middlename && $middlename ne 'N/a')
    {
      $pretty_name = "$firstname $middlename $lastname";
      push @candidate_names, $pretty_name;
    }

    $pretty_name = "$firstname $lastname";
    push @candidate_names, $pretty_name;

    # Some names have a period after the middle initial, try that too
    if ($middlename && $middlename ne 'N/a' && $middlename !~ /\.$/)
    {
      push @candidate_names, "$firstname $middlename. $lastname";
    }

    # Deduplicate candidate names
    my %seen;
    @candidate_names = grep { !$seen{$_}++ } @candidate_names;

    my $player_id;

    # Try each candidate name
    foreach my $candidate (@candidate_names)
    {
      my $query = "SELECT id FROM players WHERE BINARY name = ?";
      my $sth = $dbh->prepare($query);
      $sth->execute($candidate);
      my @rows = map { $_->[0] } @{$sth->fetchall_arrayref()};

      if (scalar @rows == 1)
      {
        $player_id = $rows[0];
        last;
      }
    }

    # If name didn't match exactly, try matching by LIKE
    if (!$player_id)
    {
      my $query = "SELECT id FROM players WHERE BINARY name LIKE ?";
      my $sth = $dbh->prepare($query);
      $sth->execute("%$firstname%$lastname%");
      my @rows = map { $_->[0] } @{$sth->fetchall_arrayref()};

      if (scalar @rows == 1)
      {
        $player_id = $rows[0];
      }
      elsif (scalar @rows > 1)
      {
        printf $lfh "WARNING: Multiple players match '%s %s' (IDs: %s). Skipping.\n",
          $firstname, $lastname, join(", ", @rows);
        $multiple++;
        next;
      }
    }

    if (!$player_id)
    {
      printf $lfh "WARNING: No player found for '%s %s' (email: %s). Skipping.\n",
        $firstname, $lastname, $email;
      $not_found++;
      next;
    }

    # Update the photo URL
    my $update = "UPDATE players SET photo = ? WHERE id = ?";
    my $sth = $dbh->prepare($update);
    $sth->execute($photo_url, $player_id);

    printf $lfh "Updated player ID %d: '%s %s' -> %s\n",
      $player_id, $firstname, $lastname, $photo_url;
    $updated++;
  }

  close $fh;

  printf $lfh "\nDone. %d updated, %d not found, %d skipped (no photo), %d multiple matches.\n",
    $updated, $not_found, $skipped, $multiple;
}

# Process a tab-separated text file (photos.txt or centrestar_photos.txt)
sub process_text_file
{
  my ($dbh, $text_file, $lfh) = @_;

  # Determine the URL prefix based on the filename
  my $url_prefix;
  if ($text_file =~ /centrestar/i)
  {
    $url_prefix = '/pix/centrestar/';
  }
  else
  {
    $url_prefix = '/pix/';
  }

  open my $fh, "<:encoding(utf8)", $text_file or die "Cannot open $text_file: $!";

  my $updated = 0;
  my $not_found = 0;
  my $multiple = 0;

  while (my $line = <$fh>)
  {
    chomp $line;
    next if $line =~ /^\s*$/;

    # Tab-separated: firstname, lastname, relative_path
    my @fields = split /\t/, $line;
    if (scalar @fields < 3)
    {
      printf $lfh "WARNING: Skipping malformed line: %s\n", $line;
      next;
    }

    my $firstname     = $fields[0];
    my $lastname      = $fields[1];
    my $relative_path = $fields[2];

    if (!$relative_path)
    {
      next;
    }

    my $photo_url = $url_prefix . $relative_path;

    my $player_id;

    # First, try exact match on players.name
    my $exact_name = "$firstname $lastname";
    {
      my $query = "SELECT id FROM players WHERE BINARY name = ?";
      my $sth = $dbh->prepare($query);
      $sth->execute($exact_name);
      my @rows = map { $_->[0] } @{$sth->fetchall_arrayref()};

      if (scalar @rows == 1)
      {
        $player_id = $rows[0];
      }
    }

    # If no exact match, look in player_alt_names for this player's name
    # Try to find any player whose alt_name matches
    if (!$player_id)
    {
      my $query = "SELECT p.id FROM players p
                    INNER JOIN player_alt_names a ON a.player_id = p.id
                    WHERE BINARY a.alt_name = ?
                    ORDER BY p.id";
      my $sth = $dbh->prepare($query);
      $sth->execute($exact_name);
      my @rows = map { $_->[0] } @{$sth->fetchall_arrayref()};

      if (scalar @rows == 1)
      {
        $player_id = $rows[0];
      }
      elsif (scalar @rows > 1)
      {
        printf $lfh "WARNING: Multiple players match alt_name '%s' (IDs: %s). Skipping.\n",
          $exact_name, join(", ", @rows);
        $multiple++;
        next;
      }
    }

    # If not already found, try sanitized alt_name lookup
    if (!$player_id)
    {
      my $sanitized = $exact_name;
      $sanitized = uc $sanitized;
      $sanitized =~ s/[^A-Z]//g;
      my $query = "SELECT p.id FROM players p
                    INNER JOIN player_alt_names a ON a.player_id = p.id
                    WHERE BINARY a.alt_name = ?
                    ORDER BY p.id";
      my $sth = $dbh->prepare($query);
      $sth->execute($sanitized);
      my @rows = map { $_->[0] } @{$sth->fetchall_arrayref()};

      if (scalar @rows == 1)
      {
        $player_id = $rows[0];
      }
      elsif (scalar @rows > 1)
      {
        printf $lfh "WARNING: Multiple players match alt_name '%s' (IDs: %s). Skipping.\n",
          $sanitized, join(", ", @rows);
        $multiple++;
        next;
      }
    }

    if (!$player_id)
    {
      printf $lfh "WARNING: No player found for '%s %s'. Skipping.\n",
        $firstname, $lastname;
      $not_found++;
      next;
    }

    # Update the photo URL
    my $update = "UPDATE players SET photo = ? WHERE id = ?";
    my $sth = $dbh->prepare($update);
    $sth->execute($photo_url, $player_id);

    printf $lfh "Updated player ID %d: '%s %s' -> %s\n",
      $player_id, $firstname, $lastname, $photo_url;
    $updated++;
  }

  close $fh;

  printf $lfh "\nDone. %d updated, %d not found, %d multiple matches.\n",
    $updated, $not_found, $multiple;
}

sub connect_to_database
{
  my $database_name = get_environment_name(Constants::DATABASE_NAME);
  my $host_name     = Constants::DATABASE_HOST_NAME;
  my $user_name     = Constants::DATABASE_USER_NAME;
  my $password      = Constants::DATABASE_PASSWORD;

  my $dbh = DBI->connect("DBI:mysql:database=$database_name;host=$host_name",
                         $user_name, $password,
                         {'RaiseError' => 1});
  return $dbh;
}

sub get_environment_name
{
  # Duplicate of the function from utils.pl to keep this script standalone
  my $name = shift;

  my $app_env = $ENV{'AARDVARK_APP_ENV'};

  if ($app_env && $app_env eq 'dev')
  {
    return $name . '_dev';
  }
  return $name;
}
