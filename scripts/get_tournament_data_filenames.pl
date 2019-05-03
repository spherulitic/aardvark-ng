#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Long;
use DBI;
use Data::Dumper;

use lib "./modules";
use Constants;

unless (caller)
{
  my $working_directory      = Constants::DEFAULT_WORKING_DIR;
  my $year_regex             = Constants::DEFAULT_YEAR_REGEX;
  my $country_trigraph_regex = Constants::DEFAULT_COUNTRY_TRIGRAPH_REGEX;
  my $file_regex             = Constants::DEFAULT_FILE_REGEX;

  GetOptions (
               'directory:s' => \$working_directory,
               'year:s'      => \$year_regex,
               'country:s'   => \$country_trigraph_regex,
               'file:s'      => \$file_regex,
             );  

  my $filenames_array_ref = get_tournament_data_filenames($working_directory, $year_regex, $country_trigraph_regex, $file_regex);

  print Dumper($filenames_array_ref);
}

sub get_tournament_data_filenames
{
  my $base_directory_name    = shift;
  my $year_regex             = shift;
  my $country_trigraph_regex = shift;
  my $file_regex             = shift;

  $base_directory_name .= "/";

  my @tournament_data_filenames = ();

  opendir my $base_directory, $base_directory_name or die "Cannot open $base_directory_name: $!";
  my @year_directory_names = grep(/$year_regex/, readdir($base_directory));

  foreach my $year_directory_name (@year_directory_names)
  {
    my $year_directory_full_path_name = $base_directory_name . $year_directory_name;
    opendir my $year_directory, $year_directory_full_path_name or die "Cannot open $year_directory_full_path_name: $!";
    my @country_trigraphs = grep(/$country_trigraph_regex/, readdir($year_directory));

    foreach my $country_trigraph (@country_trigraphs)
    {
      my $trigraph_directory_full_path_name = $year_directory_full_path_name . "/" .  $country_trigraph;
      opendir my $trigraph_directory, $trigraph_directory_full_path_name or die "Cannot open $trigraph_directory_full_path_name: $!";
      my @filenames = grep(/$file_regex/i, readdir($trigraph_directory));

      my @full_filenames = map { $trigraph_directory_full_path_name . "/"  . $_} @filenames;

      push @tournament_data_filenames, @full_filenames;
    }
  }
  return \@tournament_data_filenames;
}

1;





