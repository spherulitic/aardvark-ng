#!/usr/bin/perl

# This script compares every tournament file between directories
# and writes the diffs to a log file.

use strict;
use warnings;
use Getopt::Long;
use Data::Dumper;

use lib "./modules";
use Constants;

require "./scripts/utils.pl";

my $working_directory      = Constants::DEFAULT_WORKING_DIR;
my $year_regex             = Constants::DEFAULT_YEAR_REGEX;
my $country_trigraph_regex = Constants::DEFAULT_COUNTRY_TRIGRAPH_REGEX;
my $file_regex             = "(.tou)|(.STS)|(.STA)|(.TOU)";

my $filenames_array_ref = get_tournament_data_filenames($working_directory,
                          $year_regex, $country_trigraph_regex, $file_regex);

my $backups_directory = Constants::DEFAULT_BACKUP_DIR;

my @filenames_array = @{$filenames_array_ref};

my $num_corrections = 0;

foreach my $filename (@filenames_array)
{
  my $backup_filename = $filename;

  $backup_filename =~ s/$working_directory/$backups_directory/g;

  if (-e $filename && !(-e $backup_filename))
  {
    print "Missing file\nNo backup for $filename\n";
  }

  if (-e $backup_filename && !(-e $filename))
  {
    print "Missing file\nNo file for $backup_filename\n";
  }

  # print "file: $filename, backup: $backup_filename\n";

  my $cmd = "diff \"$filename\" \"$backup_filename\" |";

  my $output = "";

  open(CMD, $cmd);

  while (<CMD>)
  {
    $output .= $_;
  }
  if ($output)
  {
    print "$cmd\n$output\n";
    $num_corrections++;
  }
}

print "\n\n\n\n$num_corrections files altered\n";


