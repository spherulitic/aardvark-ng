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

sub deploy
{
  
  # Delete old data in the dev dir
  system "rm -rf $working_dir/$html_dir";
   
  # Copy new data to dev dir
  system "cp -r $html_dir $working_dir";
  
  # Copy static html
  system "cp $html_static_dir/* /srv/dev/";
  
  # Copy data html
  system "cp $html_data_dir/* /srv/dev/";
  
  # Copy the cgi scripts
  system "cp -r $cgibin_dir $working_dir";

  # Copy the flags
  system "cp -r $flags_dir/ $working_dir";
  
}


1;

