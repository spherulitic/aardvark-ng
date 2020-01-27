#!/usr/bin/perl

# This script copies html and maybe other stuff
# to the appropriate directories

use strict;
use warnings;
use Getopt::Long;
use lib './modules';
use Constants;
use Cwd;

require './scripts/utils.pl';

my $working_dir         = get_environment_name(Constants::DEFAULT_WORKING_DIR);
my $html_dir            = Constants::HTML_DIR;
my $cgibin_dir          = Constants::CGIBIN_DIR;
my $html_static_dir     = Constants::HTML_STATIC_DIR;
my $html_data_dir       = Constants::HTML_DATA_DIR;
my $player_html_dir     = Constants::PLAYER_HTML_DIR;
my $tournament_html_dir = Constants::TOURNAMENT_HTML_DIR;
my $rankings_html_dir   = Constants::RANKINGS_HTML_DIR;
my $flags_dir           = Constants::COUNTRY_FLAGS_DIR;

unless(caller)
{
   deploy('/srv/dev/', $working_dir);
   deploy('/srv/iwi.wespa.org/', '/srv/iwi.wespa.org/aardvark');
}

sub deploy
{
  my $base_dir    = shift;
  my $working_dir = shift;
  my $cwd         = getcwd();
  print "Deploying all HTML files\n"; 
  print "Copying html to $working_dir\n"; 
  # Copy new data to dev dir
  system "cp -r $html_dir $working_dir";

  print "Copying static html to $base_dir\n";
  # Copy static html
  # Softlinking is much more convenient
  # in this case
  system "cp -rf $html_static_dir/* $base_dir";

  print "Copying css to $working_dir\n";
  system "cp -rf css/* $working_dir";

  print "Copying html data to to $base_dir\n";
  # Copy data html
  system "cp -r $html_data_dir/. $base_dir";

  print "Copying cgi scripts to $base_dir\n";
  # Copy the cgi scripts
  system "cp -r $cgibin_dir $working_dir";

  print "Copying the flags to the $working_dir\n";
  # Copy the flags
  system "cp -r $flags_dir/ $working_dir";
  
}


1;

