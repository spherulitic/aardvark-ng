#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Long;
use Pod::Usage qw(pod2usage);
use lib './modules';
use Constants;


my $update_start_year = Constants::UPDATE_START_YEAR;
my $source_dir        = Constants::UPDATE_SOURCE_DIR;
my $working_dir       = Constants::DEFAULT_WORKING_DIR;

my @localtime_data = localtime();
my $current_year = $localtime_data[5] + 1900;

for (my $year = $update_start_year; $year <= $current_year; $year++)
{
  my $cmd = "cp -r $source_dir/$year $working_dir/";
  system $cmd;
}



