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
  record_database();
}

sub record_database
{
  my $database_name = get_environment_name(Constants::DATABASE_NAME);
  my $host_name     = Constants::DATABASE_HOST_NAME;
  my $user_name     = Constants::DATABASE_USER_NAME;
  my $password      = Constants::DATABASE_PASSWORD;
  
  my $logs          = Constants::LOG_DIR;
  my $players_tn    = Constants::PLAYERS_TABLE_NAME;

  my $dbh = DBI->connect("DBI:mysql:database=$database_name;host=$host_name",
                         $user_name, $password,
                         {'RaiseError' => 1});
  
  my @t = localtime;
  $t[5] += 1900;
  $t[4]++;

  my $tstamp = sprintf "%04d_%02d_%02d", @t[5,4,3];

  my $dumpfile = 'mysqldump_' . $database_name . '_' . $tstamp;

  my $dump_cmd = "mysqldump -u $user_name --password='$password' $database_name $players_tn > $logs/$dumpfile";

  system $dump_cmd;
 
  my @players = @{$dbh->selectall_arrayref("SELECT name, id FROM $players_tn", {"RaiseError" => 1} )};

  my $player_ids = join "\n", (map {$_->[0] . ', ' . $_->[1]} @players) ;
  open(my $fh, '>', "$logs/player_ids_$database_name" . "$tstamp.txt");
  print $fh $player_ids;
  close $fh;
}

1;




