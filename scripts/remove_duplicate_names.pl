#!/usr/bin/perl

# This scripts checks the master ratings list for duplicate names
# and checks that the duplicate names input file uses the correct preferred
# name.

use strict;
use warnings;
use Data::Dumper;

use lib "./modules";
use Constants;

my $master_ratings_list_filename = Constants::DEFAULT_WORKING_DIR . "/" .
                                   Constants::MASTER_RATINGS_LIST;

my $duplicates_filename = Constants::LOG_DIR . "/" .
                          Constants::DUPLICATE_NAMES_FILE;

my $new_ratings_list_filename = Constants::LOG_DIR . "/" . Constants::MASTER_RATINGS_LIST;

my %master_list_names_hash = ();
my %dup_names_hash         = ();

open(MASTER_RATINGS_LIST, "<", $master_ratings_list_filename)
  or die "Cannot open $master_ratings_list_filename: $!";

my $master_ratings_list_header = <MASTER_RATINGS_LIST>;

my $line_number = 2;

while(<MASTER_RATINGS_LIST>)
{
  my $original_line = $_;
  chomp $_;
  my @items = split /\s+/, $_;

  my $nickname           = shift @items;
  my $trigraph           = shift @items;
  my $last_played_date   = pop @items;
  my $rating             = pop @items;
  my $total_games_played = pop @items;

  my $ratings_list_name  = join " ", @items;
  $master_list_names_hash{$ratings_list_name} = [$line_number++, $last_played_date, $original_line];
}

open(DUP, "<", $duplicates_filename)
  or die "Cannot open $duplicates_filename: $!";


my @removed_report_array = ();
my $num_removed    = 0;

while(<DUP>)
{
  chomp $_;

  $_ =~ s/^\s+|\s+$//g;

  if ($_ =~ /^#/ || !$_){next;}

  my @names = split /,/, $_;

  @names = map { $_ =~ s/^\s+|\s+$//gr  } @names;

  if (!@names){next;}
    
  my @name_date_pair_array = ();

  foreach my $name (@names)
  {
    push @name_date_pair_array, [$name, $master_list_names_hash{$name}->[1]];
  }
  
  @name_date_pair_array = sort {$b->[1] <=> $a->[1]} @name_date_pair_array;

  shift @name_date_pair_array;

  foreach my $pair (@name_date_pair_array)
  {
    my $name_array_ref = $master_list_names_hash{$pair->[0]};
    push @removed_report_array, [$name_array_ref->[0], $name_array_ref->[2]]; 
    delete $master_list_names_hash{$pair->[0]};
    $num_removed++;
  }
}

my @sorted_report = sort {$a->[0] <=> $b->[0]} @removed_report_array;

my $removed_report = "$num_removed lines were removed:\n\n";

for (my $i = 0; $i < scalar @sorted_report; $i++)
{
  my $line_number = sprintf "%-5s", $sorted_report[$i]->[0]. ":";
  $removed_report .= "Line $line_number $sorted_report[$i]->[1]";
}

print $removed_report;
open(my $removed_names_fh, ">", Constants::LOG_DIR . "/" . Constants::REMOVED_NAMES_FILE);
print $removed_names_fh $removed_report;
close $removed_names_fh;

my @sorted_lines = sort {$a->[0] <=> $b->[0]} values %master_list_names_hash;

open(my $new_ratings_fh, ">", $new_ratings_list_filename);

print $new_ratings_fh $master_ratings_list_header;

for (my $i = 0; $i < scalar @sorted_lines; $i++)
{
  print $new_ratings_fh $sorted_lines[$i]->[2];
}

close $new_ratings_fh;


