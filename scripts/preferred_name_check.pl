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

my $duplicates_filename = Constants::INPUT_DIR . "/" .
                          Constants::INPUT_MERGE_FILE;

my %master_list_names_hash = ();
my %dup_names_hash         = ();

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
  $master_list_names_hash{$ratings_list_name} = 1;
}

open(DUP, "<", $duplicates_filename)
  or die "Cannot open $duplicates_filename: $!";

while(<DUP>)
{
  chomp $_;

  $_ =~ s/^\s+|\s+$//g;

  if ($_ =~ /^#/ || !$_){next;}

  my @names = split /,/, $_;

  @names = map { $_ =~ s/^\s+|\s+$//gr  } @names;

  if (!@names){next;}
    
  my $true_name = shift @names;

  foreach my $alt_name (@names)
  {
    $dup_names_hash{$alt_name} = $true_name;
  }
}

# Check master ratings list for duplicates

open(my $dupnames_fh, ">", Constants::LOG_DIR . "/" . Constants::DUPLICATE_NAMES_FILE);

print "Duplicate names:\n";

foreach my $n (keys %master_list_names_hash)
{
  my $true_name = $dup_names_hash{$n}; 
  if ($true_name && $master_list_names_hash{$true_name})
  {
    my $line = "$true_name, $n\n";
    print $dupnames_fh $line;
    print $line;
  }
}

close $dupnames_fh;

open(my $prefnames_fh, ">", Constants::LOG_DIR . "/" . Constants::INCORRECT_NAME_MAPPINGS_FILE);

print "\n\nIncorrect preferred names:\n";

foreach my $n (keys %master_list_names_hash)
{
  if ($dup_names_hash{$n})
  {
    print $prefnames_fh "$n\n";
    print "$n\n";
  }
}

close $prefnames_fh;


