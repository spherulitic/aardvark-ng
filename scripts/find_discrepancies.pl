#!/usr/bin/perl

# This script finds players in the player table who do not appear in the
# master ratings list and prints out the results as well as writes the
# result to a log file

use strict;
use warnings;
use Getopt::Long;
use DBI;
use Data::Dumper;

use lib "./modules";
use Constants;

my $master_ratings_list_filename = Constants::DEFAULT_WORKING_DIR . "/" . 
                                   Constants::MASTER_RATINGS_LIST;

my $table_name      = Constants::PLAYERS_TABLE_NAME;

my $output_filename = Constants::LOG_DIR . "/" . 
                      Constants::NOT_IN_MASTER_RATINGS_LIST;

GetOptions (
             'filename:s'        => \$master_ratings_list_filename,
             'table_name:s'      => \$table_name,
             'output_filename:s' => \$output_filename,
           );

my $database_name = Constants::DATABASE_NAME;
my $host_name     = Constants::DATABASE_HOST_NAME;
my $user_name     = Constants::DATABASE_USER_NAME;
my $password      = Constants::DATABASE_PASSWORD;



my $dbh = DBI->connect("DBI:mysql:database=$database_name;host=$host_name",
                       $user_name, $password,
                       {'RaiseError' => 1});

# The $table_name variable should always be the name of the players table

my $player_query     = "SELECT name FROM $table_name";

my $database_players_arrayref = $dbh->selectall_arrayref
                                ($player_query, {"RaiseError" => 1}); 

my %database_players_hash = map { $_->[0] => 1} @{$database_players_arrayref};

open(MASTER_RATINGS_LIST, "<", $master_ratings_list_filename)
  or die "Cannot open $master_ratings_list_filename: $!";

my $master_ratings_list_header = <MASTER_RATINGS_LIST>;

while(<MASTER_RATINGS_LIST>)
{
  chomp $_;
  my @items = split /\s+/, $_;

  my $nickname           = shift @items;
  my $trigraph           = shift @items;
  my $last_played_date   = pop @items;
  my $rating             = pop @items;
  my $total_games_played = pop @items;

  my $ratings_list_name  = join " ", @items;
  $ratings_list_name     =~ s/^\s+|\s+$//g;

  delete $database_players_hash{$ratings_list_name};
}

open(my $output_file, ">", $output_filename)
  or die "Cannot open $output_filename: $!";

foreach my $key (keys %database_players_hash)
{
  print $output_file $key . "\n";
  print $key . "\n";
}

close $output_file;


