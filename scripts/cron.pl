#!/usr/bin/perl

use strict;
use warnings;
use English qw ( -no_math_vars );

my $target_directory = $PROGRAM_NAME;
$target_directory =~ s/\/[^\/]*\/[^\/]*$//gxms;
chdir($target_directory);
my $command = './aardvark cron';
system $command;
