#!/usr/bin/perl

# Combines two players in the database schema.
# Now useless as duplicate names are consolidated
# on the fly in the migration phase.

use strict;
use warnings;
use Getopt::Long;
use DBI;
use Data::Dumper;

use lib "./modules";
use Constants;

require './scripts/utils.pl';

my $merge_names_filename = Constants::INPUT_DIR . "/" . Constants::INPUT_MERGE_FILE;

GetOptions (
             'filename:s'        => \$merge_names_filename,
           );


my $dbh = connect_to_database();


open(MERGE_NAMES, "<", $merge_names_filename) or die "Cannot open $merge_names_filename: $!";

while(<MERGE_NAMES>)
{
  chomp $_;

  my @names = split /,/, $_;

  if (!@names){next;}

  my $true_name = shift @names;

  foreach my $alt_name (@names)
  {
    merge($dbh, $true_name, $alt_name); 
  }
}

sub merge
{
  my $dbh       = shift;
  my $true_name = shift;
  my $alt_name  = shift;

  $true_name =~ s/^\s+|\s+$//g;
  $alt_name  =~ s/^\s+|\s+$//g;

  my $ptn    = Constants::PLAYERS_TABLE_NAME;
  my $pantn  = Constants::PLAYER_ALT_NAMES_TABLE_NAME;
  my $trtn   = Constants::TOURNAMENT_RESULTS_TABLE_NAME;
  my $prtn   = Constants::PLAYER_RESULTS_TABLE_NAME;

  my ($true_id, $true_total_games, $true_last_played, $true_is_provisional) =
  @{get_fields
    (
      $dbh,
      $ptn,
      "id, total_games, last_played, provisional",
      "name=\"$true_name\""
    )
   };

  my ($alt_id, $alt_total_games, $alt_last_played) =
  @{get_fields
    (
      $dbh,
      $ptn,
      "id, total_games, last_played",
      "name=\"$alt_name\""
    )
   };

  my $new_total_games    = $true_total_games + $alt_total_games;
  my $new_is_provisional = $true_is_provisional;
  my $new_last_played    = $true_last_played;

  if ($true_is_provisional && $new_total_games >= Constants::PROVISIONAL_GAMES_MAX)
  {
    $new_is_provisional = 0;
  }

  if ( ( $true_last_played =~ s/\D//gr  ) < ( $alt_last_played =~ s/\D//gr ) )
  {
    $new_last_played = $alt_last_played;
  }

  my @updates = ("UPDATE $ptn SET total_games = $new_total_games, provisional = $new_is_provisional, last_played = \"$new_last_played\" WHERE id = $true_id",
                 "UPDATE $pantn SET player_id = $true_id WHERE player_id = $alt_id",
                 "UPDATE $trtn  SET player_id = $true_id WHERE player_id = $alt_id",
                 "UPDATE $prtn  SET player_id = $true_id WHERE player_id = $alt_id",
               );

  for (my $i = 0; $i < scalar @updates; $i++)
  {
    $dbh->do($updates[$i], {"RaiseError" => 1});
  }
  my $delete = "DELETE FROM players WHERE id=$alt_id";

  $dbh->do($delete, {"RaiseError" => 1});
}

sub get_fields
{
  my $dbh     = shift;
  my $table   = shift;
  my $columns = shift;
  my $where   = shift;

  my $query = "SELECT $columns FROM $table WHERE $where";

  return $dbh->selectrow_arrayref($query, {"RaiseError" => 1});
}



