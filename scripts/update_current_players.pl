#!/usr/bin/perl

use strict;
use warnings;
use DBI;
use Data::Dumper;

use lib "./modules";
use Constants;

my $players_tn        = Constants::PLAYERS_TABLE_NAME;
my $current_games_min = Constants::CURRENT_GAMES_MIN;

my $database_name = Constants::DATABASE_NAME;
my $host_name     = Constants::DATABASE_HOST_NAME;
my $user_name     = Constants::DATABASE_USER_NAME;
my $password      = Constants::DATABASE_PASSWORD;

my $dbh = DBI->connect("DBI:mysql:database=$database_name;host=$host_name",
                       $user_name, $password,
                       {'RaiseError' => 1});

my $datestring = localtime();
my $epoc = time();
$epoc = $epoc - (24 * 60 * 60 * 365 * 2);   # two years before current date.

my @t = localtime($epoc);
$t[5] += 1900;
$t[4]++;

my $date_two_years_ago = sprintf "%04d-%02d-%02d", @t[5,4,3];

my $games_in_last_two_years =
"
(
  SELECT SUM(tr.wins + tr.losses)
  FROM tournaments AS t, divisions AS d, tournament_results AS tr
  WHERE p.id = tr.player_id AND tr.division_id = d.id AND d.tournament_id = t.id AND t.end_date > '$date_two_years_ago'
)
"; 


my $update_current =
"
UPDATE $players_tn AS p
SET p.current =
(
  CASE
    WHEN $games_in_last_two_years > $current_games_min
      THEN 1
    ELSE 0
  END
)
"; 


$dbh->do($update_current, {"RaiseError" => 1}); 

