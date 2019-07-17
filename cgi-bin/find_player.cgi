#!/usr/bin/perl

# This script updates the WESPA html pages

use strict;
use warnings;
use DBI;
use Data::Dumper;
use CGI;

use lib '/home/jcastellano/aardvark-ng/modules';
use Constants;

my $database_name = Constants::DATABASE_NAME;
my $host_name     = Constants::DATABASE_HOST_NAME;
my $user_name     = Constants::DATABASE_USER_NAME;
my $password      = Constants::DATABASE_PASSWORD;

my $query = new CGI;

my $player_name = $query->param('name');

my $dbh = connect_to_database();

my $player_id = query_table($dbh, Constants::PLAYERS_TABLE_NAME, "BINARY name", $player_name)->[0]->{'id'};

if ($player_id)
{
  print $query->redirect("https://dev.wespa.org/html/players/$player_id.html");
}
else
{
  print "Content-Type: text/javascript\n\nNo player with name $player_name found.\n";
}

sub query_table
{
  my $dbh         = shift;
  my $table       = shift;
  my $table_field = shift;
  my $query_field = shift;

  my $query = "SELECT * FROM $table WHERE $table_field='$query_field'";

  my $query_result = $dbh->selectall_arrayref($query, {Slice => {}, "RaiseError" => 1});

  return $query_result;
}

sub connect_to_database
{
  my $database_name = Constants::DATABASE_NAME;
  my $host_name     = Constants::DATABASE_HOST_NAME;
  my $user_name     = Constants::DATABASE_USER_NAME;
  my $password      = Constants::DATABASE_PASSWORD;

  my $dbh = DBI->connect("DBI:mysql:database=$database_name;host=$host_name",
                         $user_name, $password,
                         {'RaiseError' => 1}); 
  return $dbh;
}

1;











