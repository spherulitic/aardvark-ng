#!/usr/bin/perl

# This script copies all of the tournament data from /srv/dev/aardvark
# (unless the --input argument is specified) into a new backup directory
# (which is a required argument specified with the --backup flag)
# in aardvark-ng/backups. Tournament data refers to all directories
# that match the DEFAULT_YEAR_REGEX found in modules/Constants.pm

use strict;
use warnings;
use Getopt::Long;
use DBI;
use Data::Dumper;

use lib "./modules";
use Constants;

my $year_regex = Constants::DEFAULT_YEAR_REGEX;

unless (caller)
{
  my $backup_dir = "";
  my $working_directory = Constants::DEFAULT_WORKING_DIR;

  GetOptions (
               'input:s'  => \$working_directory,
               'backup=s' => \$backup_dir
             );
  backup($working_directory, $backup_dir);
}

sub backup
{
  my $base_directory_name = shift;
  my $backup_dir          = shift;

  mkdir $backup_dir;

  $base_directory_name .= "/";

  my @tournament_data_filenames = ();

  opendir my $base_directory, $base_directory_name or die "Cannot open $base_directory_name: $!";
  my @year_directory_names = grep(/$year_regex/, readdir($base_directory));

  foreach my $year_directory_name (@year_directory_names)
  {
    my $year_directory_full_path_name = $base_directory_name . $year_directory_name;
    system "cp -r $year_directory_full_path_name $backup_dir";
  }
  return \@tournament_data_filenames;
}

1;


