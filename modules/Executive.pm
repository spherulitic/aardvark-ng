#!/usr/bin/perl

package Executive;

use strict;
use warnings;

use version; our $VERSION = qv('1');

use Data::Dumper;
use Getopt::Long qw(:config pass_through);
use Pod::Usage qw(pod2usage);
use List::Util;
use English qw( -no_match_vars );
use Carp;

use lib './objects';
use lib './modules';

use Constants;
use Report;
use Update;
use Utils;

if ( !caller )
{
  my $command_arguments = {};

  GetOptions(
    coverage => \$command_arguments->{coverage},
    help     => \$command_arguments->{help},
    man      => \$command_arguments->{man},
  ) or pod2usage( -verbose => 0 );

  if ( $command_arguments->{help} )
  {
    pod2usage( -verbose => 1 );
  }
  if ( $command_arguments->{man} )
  {
    pod2usage( -verbose => 2 );
  }

  my $subcommand = $ARGV[0];

  if (
    !$subcommand
    || ( lc $subcommand ne $SUBCOMMAND_CRON
      && lc $subcommand ne $SUBCOMMAND_MAINTENANCE )
    )
  {
    pod2usage( 'Specify exactly one of the following subcommands: '
        . "$SUBCOMMAND_MAINTENANCE, $SUBCOMMAND_CRON" );
  }

  if ( lc $subcommand eq $SUBCOMMAND_MAINTENANCE )
  {
    my $argument_string = join q{ }, @ARGV;
    Executive::maintenance(
      { argument_string => $argument_string,
        coverage        => $command_arguments->{coverage}
      }
    );
  }
  if ( lc $subcommand eq $SUBCOMMAND_CRON )
  {
    Executive::cron();
  }
}

sub cron
{
  my $logname
    = "$LOG_DIR/" . Utils::get_iso_date( time, q{_} ) . '_cronjob.log';

  my $cron_command = "./modules/Update.pm -$EXECUTIVE_KEY > $logname 2>&1";

  system $cron_command;

  return 1;
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

__END__

=head1 NAME

Aardvark - Processing and testing of WESPA tournament data

=head1 VERSION

This documentation refers to Aardvark version 1.

=head1 USAGE

./aardvark  main
            [--all]
            [--alphabetize]
            [--coverage]
            [--criticize]
            [--croak]
            [--database]
            [--export]
            [--full]
            [--html]
            [--prepare]
            [--setexpected]
            [--standards]
            [--syntax]
            [--test=<test_cases>]
            [--tidy]

./aardvark  cron

=head1 REQUIRED ARGUMENTS

Exactly one of the 'main' or 'cron' subcommands must be given.

=head1 OPTIONS

=over 16

=item B<main>

The maintenance subcommand.

=item B<cron>

The cronjob subcommand.

=item B<--all>

Optional argument for the maintenance subcommand.
Enables the --prepare, --test, --database, and --html
options.

=item B<--alphabetize>

Optional argument for the maintenance subcommand.
Alphabetizes all Aardvark perl files in-place.

=item B<--coverage>

Optional argument for the maintenance subcommand.
Enables coverage analysis.

=item B<--criticize>

Optional argument for the maintenance subcommand.
Criticizes all Aardvark perl files.

=item B<--croak>

Optional argument for the maintenance subcommand.
Terminates program on a testing failure.

=item B<--database>

Optional argument for the maintenance subcommand.
Runs the database test harness.

=item B<--export>

Optional argument for the maintenance subcommand.
Remakes the export statement for Constants.pm.

=item B<--full>

Optional argument for the maintenance subcommand.
Loads all TOU data in addition to test TOU data.

=item B<--help>

Display this message.

=item B<--html>

Optional argument for the maintenance subcommand.
Runs the html test harness.

=item B<--prepare>

Optional argument for the maintenance subcommand.
Enables the --alphabetize, --export, --tidy, --syntax,
--criticize, and --standards options.

=item B<--setexpected>

This option is very dangerous! Use with care.
Optional argument for the maintenance subcommand.
Sets expected results to actual results for all tests.

=item B<--standards>

Optional argument for the maintenance subcommand.
Detects standards exceptions for all Aardvark perl files.

=item B<--syntax>

Optional argument for the maintenance subcommand.
Checks syntax for all Aardvark perl files.

=item B<--test=<test_cases>>

Optional argument for the maintenance subcommand.
Specifies which tests to run. If no value is specified,
runs all tests.

=item B<--tidy>

Optional argument for the maintenance subcommand.
Tidies all Aardvark perl files.

=back

=head1 DESCRIPTION

The aardvark executable performs all the functions of the
Aardvark program. This includes maintenance and cronjobs.
See the README.md for more details.

=head1 EXIT STATUS

There are no expected errors given by the aardvark executable itself.
The expected exit status is 0.

=head1 DIAGNOSTICS

The aardvark executable itself should produce no error messages if properly
used. The Test.pm and Update.pm modules will croak if they are run directly.

=head1 CONFIGURATION

The 'main' subcommand should only be used in the development environment.

=head1 DEPENDENCIES

Aardvark requires the following perl modules:

  Carp
  Clone
  Cwd
  Data::Dumper
  DBI
  English
  Getopt::Long
  List::Util
  Perl::Critic
  Perl::Critic::Violation
  Pod::Usage
  Readonly

On Redhat or CentOS, use the following command:

  sudo yum -y install <module>

On Ubuntu or Debian, use the following command:

  sudo cpan <module>

or use http://deb.perl.it/ubuntu/cpan-deb/ to
find the equivalent apt-get command.

=head1 INCOMPATIBILITIES

It is not recommended to run Aardvark on any Perl version earlier than v5.16.3.

=head1 BUGS AND LIMITATIONS

There are no known bugs in Aardvark.
Please report problems to Joshua Castellano (joshuacastellano7@gmail.com).
Patches are welcome.

=head1 AUTHOR

Joshua Castellano (joshuacastellano7@gmail.com)

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2020 WESPA. All rights reserved.
This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.
This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
