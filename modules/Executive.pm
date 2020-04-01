#!/usr/bin/perl

package Executive;

use strict;
use warnings;

use version; our $VERSION = qv('1');

use Data::Dumper;
use Getopt::Long qw(:config pass_through);
use List::Util;
use English qw( -no_match_vars );
use Carp;

use lib './objects';
use lib './modules';

use Constants;
use Report;
use Utils;

if ( !caller )
{
  my $command_arguments = {};

  GetOptions(
    { pass_through => 1 },
    coverage    => \$command_arguments->{coverage},
    maintenance => \$command_arguments->{maintenance},
    cron        => \$command_arguments->{cron},
  );

  if ( $command_arguments->{maintenance} )
  {
    my $argument_string = join q{ }, @ARGV;
    Executive::maintenance(
      { argument_string => $argument_string,
        coverage        => $command_arguments->{coverage}
      }
    );
  }
  if ( $command_arguments->{cron} )
  {
    Executive::cron();
  }
}

sub maintenance
{
  my $arg_ref = shift;

  my $argument_string = $arg_ref->{argument_string};
  my $coverage        = $arg_ref->{coverage};

  my $test_command = "./test/Test.pm -$EXECUTIVE_KEY $argument_string";

  if ($coverage)
  {
    $test_command
      = 'cover -delete >/dev/null 2>&1 && '
      . 'perl -MDevel::Cover=-silent,1 '
      . $test_command
      . ' && cover -report html >/dev/null 2>&1';
  }

  system $test_command . $NEWLINE;

  if ($coverage)
  {
    my $coverage_report = Report->new('COVERAGE REPORT');
    Utils::get_coverage_report($coverage_report);
    Utils::format_print( $coverage_report->to_string() );
  }

  return 1;
}

1;
