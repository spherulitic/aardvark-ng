#!/usr/bin/perl

use strict;
use warnings;
use DBI;
use Data::Dumper;

use lib "./modules";
use Constants;

require './scripts/utils.pl';

unless (caller)
{
  drop_all_wespa_tables();
}

sub drop_all_wespa_tables
{
  my $alt_names_hash = shift;

  my $table_ref = Constants::TABLE_CREATION_ORDER;
  my $exceptions = Constants::TABLE_DROP_EXCEPTIONS;

  my $dbh = connect_to_database();
  
  foreach my $t (reverse @{$table_ref})
  {
    if (!$exceptions->{$t})
    {
      $dbh->do("DROP TABLE IF EXISTS $t");
    }
  }

  # Tournament identity tables (events, tournaments) are preserved so that
  # tournament ids stay stable between full runs. Their child data is rebuilt
  # from scratch, so wipe it here. TRUNCATE requires FOREIGN_KEY_CHECKS off
  # because the child tables are still referenced by FK constraints in the
  # schema; child ids are regenerated on reload and nothing references them
  # externally.
  $dbh->do("SET FOREIGN_KEY_CHECKS = 0");
  $dbh->do("TRUNCATE TABLE " . Constants::PLAYER_RESULTS_TABLE_NAME);
  $dbh->do("TRUNCATE TABLE " . Constants::GAMES_TABLE_NAME);
  $dbh->do("TRUNCATE TABLE " . Constants::TOURNAMENT_RESULTS_TABLE_NAME);
  $dbh->do("TRUNCATE TABLE " . Constants::DIVISIONS_TABLE_NAME);
  $dbh->do("SET FOREIGN_KEY_CHECKS = 1");

  my $players_tn = Constants::PLAYERS_TABLE_NAME;

  foreach my $key (keys %{$alt_names_hash})
  {
    $key =~ s/'/''/g;
    my $delete_redundant_players =
    "
    DELETE FROM $players_tn
    WHERE name = '$key'
    "; 
    $dbh->do($delete_redundant_players, {"RaiseError" => 1}); 
  }

  my $reset_games_played =
  "
  UPDATE $players_tn AS p
  SET p.total_games = 0
  "; 
  
  $dbh->do($reset_games_played, {"RaiseError" => 1}); 

  my $reset_last_played =
  "
  UPDATE $players_tn AS p
  SET p.last_played = NULL
  "; 
  
  $dbh->do($reset_last_played, {"RaiseError" => 1}); 
}

1;




