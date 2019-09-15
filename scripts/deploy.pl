#!/usr/bin/perl

# This script copies html and maybe other stuff
# to the appropriate directories

use strict;
use warnings;
use Getopt::Long;
use Pod::Usage qw(pod2usage);
use lib './modules';
use Constants;


my $working_dir         = Constants::DEFAULT_WORKING_DIR;
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
  deploy();
}

sub deploy
{
  print "Deploying all HTML files\n"; 
  # Delete old data in the dev dir
  system "rm -rf $working_dir/$html_dir";
  print "Copying html to working\n"; 
  # Copy new data to dev dir
  system "cp -r $html_dir $working_dir";
  print "Copying static html to base\n";
  # Copy static html
  system "cp -r $html_static_dir/. /srv/dev/";
  print "Copying html data to to base\n";
  # Copy data html
  system "cp -r $html_data_dir/. /srv/dev/";
  print "Copying cgi scripts to working dir\n";
  # Copy the cgi scripts
  system "cp -r $cgibin_dir $working_dir";
  print "Copying the flags to the working dir\n";
  # Copy the flags
  system "cp -r $flags_dir/ $working_dir";
  
}


1;

