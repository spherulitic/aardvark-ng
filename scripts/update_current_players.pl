#!/usr/bin/perl

# This script updates the current player boolean field for each player in the
# players table. The current player status is one of the only dynamic
# fields in the player table, so a separate script was written to update this
# field so that it can be called periodically on a cronjob.

use strict;
use warnings;
use DBI;
use Data::Dumper;

use lib "./modules";
use Constants;

require './scripts/utils.pl';

unless (caller)
{
  update_current_players();
}

sub update_current_players
{
  
  my $players_tn        = Constants::PLAYERS_TABLE_NAME;
  my $current_games_min = Constants::CURRENT_GAMES_MIN;
  
  my $dbh = connect_to_database();
  
  my $datestring = localtime();
  my $epoc = time();
  $epoc = $epoc - (24 * 60 * 60 * 365 * 2);   # two years before current date.
  $epoc = $epoc - (24 * 60 * 60 * 60); # CL 19 Nov 2021 - temporarily add two extra months to the window  
  my @t = localtime($epoc);
  $t[5] += 1900;
  $t[4]++;
  
  my $date_two_years_ago = sprintf "%04d-%02d-%02d", @t[5,4,3];
  
  my $games_in_last_two_years =
  "
  (
    SELECT SUM(tr.wins + tr.losses)
    FROM tournaments AS t, divisions AS d, tournament_results AS tr
    WHERE p.id = tr.player_id AND
          tr.division_id = d.id AND
          d.tournament_id = t.id AND t.end_date > '$date_two_years_ago'
  )
  "; 
  
  
  my $update_current =
  "
  UPDATE $players_tn AS p
  SET p.current =
  (
    CASE
      WHEN $games_in_last_two_years > 0 AND p.total_games > $current_games_min
        THEN 1
      ELSE 0
    END
  )
  "; 
  
  $dbh->do($update_current, {"RaiseError" => 1}); 
  

}

1;


