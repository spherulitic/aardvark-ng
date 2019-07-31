#!/usr/bin/perl

# This scripts searches for duplicate tournament files.
# To compare by content, set the content flag. If the
# content flag is not set, it will compare files
# by name only.

use strict;
use warnings;
use Getopt::Long;
use DBI;
use Data::Dumper;

use lib "./modules";
use Constants;

require "./scripts/utils.pl";

unless (caller)
{
  my $working_directory      = Constants::DEFAULT_WORKING_DIR;
  my $year_regex             = Constants::DEFAULT_YEAR_REGEX;
  my $country_trigraph_regex = Constants::DEFAULT_COUNTRY_TRIGRAPH_REGEX;
  my $file_regex             = Constants::DEFAULT_FILE_REGEX;

  my $content_check          = '';
  GetOptions (
               'directory:s' => \$working_directory,
               'year:s'      => \$year_regex,
               'country:s'   => \$country_trigraph_regex,
               'file:s'      => \$file_regex,
               'content'     => \$content_check
             );

  my $filenames_array_ref = get_tournament_data_filenames($working_directory,
                            $year_regex, $country_trigraph_regex, $file_regex);

  check_for_duplicate_files($filenames_array_ref, $content_check);
}


sub check_for_duplicate_files
{
  my $files_ref     = shift;
  my $content_check = shift;

  my @files = @{$files_ref};

  print "Checking " . scalar @files . " files\n\n";

  my @dups = ();

  my $num_checks = 0;

  for (my $i = 0; $i < scalar @files; $i++)
  {
    for (my $k = $i + 1; $k < scalar @files; $k++)
    {    
      if ($num_checks % 1000 == 0)
      {
        print "Number of comparisons: $num_checks\n";
      }
      $num_checks++;
      # if ($num_checks == 10000){exit(0);}   
      my $file1 = $files[$i];
      my $file2 = $files[$k];
      if (!$content_check)
      {
        my $file1_shortname = $file1 =~ s/.*\///gr;
        my $file2_shortname = $file2 =~ s/.*\///gr;
        if ($file1_shortname eq $file2_shortname)
        {    
          push @dups, [$file1, $file2];
          next;
        }   
      }
      else
      {
        my $cmd = "diff -U 0 \"$file1\" \"$file2\" | grep -v ^@ | wc -l |";
        # my $cmd = "diff \"$file1\" \"$file2\" |";
        open(CMD, $cmd);

        my $num_diffs;
        while(<CMD>)
        {
          $num_diffs = int (($_ - 2) / 2);
        }
        # print "num diffs: $num_diffs\n";
        if ($num_diffs <= 3)
        {
          push @dups, [$file1, $file2];
        }
      }
    }    
  }
  if (@dups)
  {
    print "Found ". scalar @dups . " duplicates\n\n";
    print "Duplicate .tou files:\n\n" .
           Dumper(\@dups) . "\n\nMade $num_checks comparisons\n";
  }
}



1;


