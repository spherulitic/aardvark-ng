#!/usr/bin/perl

use strict;
use warnings;
use Data::Dumper;

use lib "./modules";
use Constants;

my $master_ratings_list_filename = Constants::DEFAULT_WORKING_DIR . "/" . Constants::MASTER_RATINGS_LIST;
my $duplicates_filename = Constants::INPUT_DIR . "/" . Constants::INPUT_MERGE_FILE;

my %master_list_names_hash = ();
my %dup_names_hash         = ();

open(MASTER_RATINGS_LIST, "<", $master_ratings_list_filename) or die "Cannot open $master_ratings_list_filename: $!";

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

open(DUP, "<", $duplicates_filename) or die "Cannot open $duplicates_filename: $!";

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

my @master_dup = ();

foreach my $n (keys %master_list_names_hash)
{
  my $true_name = $dup_names_hash{$n}; 
  if ($true_name && $master_list_names_hash{$true_name})
  {
    push @master_dup, [$true_name, $n];
  }
}

print "Duplicate names in $master_ratings_list_filename:\n\n" . Dumper(\@master_dup);

my @incorrect_mapping = ();

foreach my $n (keys %master_list_names_hash)
{
  if ($dup_names_hash{$n})
  {
    push @incorrect_mapping, $n;
  }
}

print "\n\nIncorrect true name mappings:\n\n" . Dumper(\@incorrect_mapping);



