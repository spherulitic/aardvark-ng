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
  my $database_name = get_environment_name(Constants::DATABASE_NAME);
  my $host_name     = Constants::DATABASE_HOST_NAME;
  my $user_name     = Constants::DATABASE_USER_NAME;
  my $password      = Constants::DATABASE_PASSWORD;
  
  my $table_ref = Constants::TABLE_CREATION_ORDER;
  my $exceptions = Constants::TABLE_DROP_EXCEPTIONS;

  my $dbh = DBI->connect("DBI:mysql:database=$database_name;host=$host_name",
                         $user_name, $password,
                         {'RaiseError' => 1});
  
  foreach my $t (reverse @{$table_ref})
  {
    if (!$exceptions->{$t})
    {
      $dbh->do("DROP TABLE IF EXISTS $t");
    }
  }
  
  my $players_tn = Constants::PLAYERS_TABLE_NAME;

  my $reset_games_played =
  "
  UPDATE $players_tn AS p
  SET p.total_games = 0
  "; 
  
  $dbh->do($reset_games_played, {"RaiseError" => 1}); 

  my $reset_last_played =
  "
  UPDATE $players_tn AS p
  SET p.last_played = '0000-00-00'
  "; 
  
  $dbh->do($reset_last_played, {"RaiseError" => 1}); 
}

1;




