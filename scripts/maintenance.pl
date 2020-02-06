#!/usr/bin/perl

use warnings;
use strict;
use Data::Dumper;

use lib './test';
use lib './modules';
use Constants;
use Test;

run_all();

sub run_all
{
  print_title("CHECKING SYNTAX");
  check_syntax();
  print_title("CHECKING FOR REDUNDANT SUBS");
  check_for_repeat_subs();
  print_title("RUNNING TESTS");
  prepare_test_area();
  Test::Harness();
}

sub print_title
{
  my $title = shift;
  $title =~ s/^\s+|\s+$//g;
  print <<TITLE
*************************
***** $title ************
*************************
TITLE
;

}

sub prepare_test_area
{
  my @directories = (
                      Constants::OBJECTS_DIRECTORY,
                      Constants::MODULES_DIRECTORY
                    );
  my $test_dir = Constants::TEST_DIRECTORY;

  foreach my $dir (@directories)
  {
    my $cmd = "ln -sf $dir/* test/\n";
    print $cmd;
    system $cmd;
  }
}

sub check_for_repeat_subs
{
  my @directories = qw(scripts objects modules);
  
  my @files = ();
  
  foreach my $dir (@directories)
  {
    opendir (my $fh_dir, $dir);
    push @files, map {$dir . '/' . $_} (grep {/\.p[ml]/} readdir $fh_dir);
  }
  
  my $file_subs = {};
  
  foreach my $f (@files)
  {
    $file_subs->{$f} = [];
    open(my $fh, '<', $f);
    while(<$fh>)
    {
      if (/^sub (.*)/)
      {
        push @{$file_subs->{$f}}, $1;
      }
    }
  }
  
  foreach my $f1 (@files)
  {
    my $f1_subs = $file_subs->{$f1};
    foreach my $f2 (@files)
    {
      my $f2_subs = $file_subs->{$f2};
      for (my $i = 0; $i < scalar @{$f1_subs}; $i++)
      {
        for (my $k = $i + 1; $k < scalar @{$f2_subs}; $k++)
        {
          my $sub1 = $f1_subs->[$i];
          my $sub2 = $f2_subs->[$k];
          if ($sub1 eq $sub2)
          {
            print "Redundant routine: $sub1\n";
            print "File 1:            $f1\n";
            print "File 2:            $f2\n";
          }
        }
      }    
    }
  }
  
}

sub check_syntax
{
  my $cmd = "find scripts objects modules cgi-bin -name \"*.p[lm]\" | ";

  open (CMDOUT, $cmd) or die "$!\n";
  while (<CMDOUT>)
  {
    system "perl -cw $_";
  }
}

1;

