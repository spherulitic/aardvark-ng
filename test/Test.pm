#!/usr/bin/perl

package Test;

use strict;
use warnings;

use version; our $VERSION = qv('1');

use Data::Dumper;
use Getopt::Long;
use List::Util;
use Perl::Critic;
use English qw( -no_match_vars );
use Carp;
use Perl::Critic::Violation;

use lib './objects';
use lib './modules';

use Constants;
use Failure;
use HTML;
use TOU;
use Update;
use Utils;
use JSON::XS;

my $all;
my $full;
my $alphabetize;
my $prepare;
my $criticize;
my $croak;
my $export;
my $html;
my $setexpected;
my $syntax;
my $standards;
my $test = $TEST_ARGUMENT_NOT_SET;
my $tidy;

GetOptions(
  all         => \$all,
  alphabetize => \$alphabetize,
  prepare     => \$prepare,
  criticize   => \$criticize,
  croak       => \$croak,
  export      => \$export,
  full        => \$full,
  html        => \$html,
  setexpected => \$setexpected,
  standards   => \$standards,
  syntax      => \$syntax,
  'test:s'    => \$test,
  tidy        => \$tidy
);

if ($alphabetize)
{
  Test::alphabetize_routine_order();
}
if ($export)
{
  Test::export_constants();
}
if ($tidy)
{
  Test::tidy();
}
if ($syntax)
{
  Test::check_syntax();
}
if ($criticize)
{
  Test::criticize();
}
if ($standards)
{
  Test::list_standards_exceptions();
}
if ( $prepare || $all )
{
  Test::prepare();
}
if ( $test ne $TEST_ARGUMENT_NOT_SET || $all )
{
  Test::harness( { test_cases => $test, exit_on_failure => $croak } );
}

sub alphabetize_routine_order
{
  Utils::format_print(
    Test::make_title(
      'ALPHABETIZING ROUTINE ORDER', q{%}, $TEST_TITLE_WIDTH
    )
  );

  my @files = Utils::get_perl_files;

  foreach my $f (@files)
  {
    my $routine_hash = {};
    my $current_routine;
    my $in_current_routine = 0;
    my $file_string        = $EMPTY_STRING;
    my @file_lines         = Utils::write_file_to_array($f);
    while (@file_lines)
    {
      my $current_line = shift @file_lines;
      if (    ## no critic (ProhibitCascadingIfElse)
        $current_line =~ /^sub (.*)/xms
        )
      {
        $current_routine = $1;
        $current_routine =~ s/\s//gxms;
        $routine_hash->{$current_routine} = $EMPTY_STRING;
      }
      elsif ( !$current_routine )
      {
        $file_string .= $current_line;
      }
      elsif ( $current_line =~ /^[{]\s*/xms )
      {
        $in_current_routine = 1;
      }
      elsif ( $current_line =~ /^[}]\s*/xms )
      {
        $in_current_routine = 0;
      }
      elsif ($in_current_routine)
      {
        $routine_hash->{$current_routine} .= $current_line;
      }
    }
    if ($current_routine)
    {
      my @alphabetized_routine_keys = sort keys %{$routine_hash};

      my $alphabetized_file = $EMPTY_STRING;

      $alphabetized_file .= $file_string;
      for my $i ( 0 .. scalar @alphabetized_routine_keys - 1 )
      {
        my $key             = $alphabetized_routine_keys[$i];
        my $routine_content = $routine_hash->{$key};
        $alphabetized_file .= "sub $key$NEWLINE";
        $alphabetized_file .= "{$NEWLINE";
        $alphabetized_file .= $routine_content;
        $alphabetized_file .= "}$NEWLINE$NEWLINE";
      }
      $alphabetized_file .= '1;';

      Utils::write_string_to_file( $alphabetized_file, $f );
      printf "Alphabetized %s$NEWLINE", $f;
    }
  }
  Utils::format_print($NEWLINE);
  return 1;
}

sub check_syntax
{
  Utils::format_print(
    Test::make_title( 'CHECKING SYNTAX', q{%}, $TEST_TITLE_WIDTH ) );

  my @files = Utils::get_perl_files;

  while (@files)
  {
    my $file = shift @files;
    system "perl -cw $file";
  }
  Utils::format_print( $NEWLINE . $NEWLINE );
  return 1;
}

sub compare_json
{
  my $expected_json = shift;
  my $actual_json   = shift;
  my $failure_obj   = shift;

  my $expected_obj = JSON::XS::decode_json($expected_json);
  my $actual_obj   = JSON::XS::decode_json($actual_json);

  return compare_objects( $expected_obj, $actual_obj, $failure_obj );
}

sub compare_keys
{
  my $expected_keys_ref = shift;
  my $actual_keys_ref   = shift;
  my $failure_obj       = shift;

  my $expected_keys = join q{,}, sort @{$expected_keys_ref};
  my $actual_keys   = join q{,}, sort @{$actual_keys_ref};

  return Test::compare_lines( $expected_keys, $actual_keys, 0, $failure_obj );
}

sub compare_lines
{
  my $expected_line = shift;
  my $actual_line   = shift;
  my $line_number   = shift;
  my $failure_obj   = shift;

  if ( !defined $actual_line )
  {
    $actual_line = $EMPTY_STRING;
  }

  if ( !defined $expected_line )
  {
    $expected_line = $EMPTY_STRING;
  }

  my $min_line = length $expected_line;
  my $max_line = length $actual_line;

  my $failed = 0;

  if ( $min_line != $max_line )
  {
    $failed = 1;
  }

  if ( $max_line < $min_line )
  {
    my $swap = $min_line;
    $min_line = $max_line;
    $max_line = $swap;
  }

  my $expected_char;
  my $actual_char;
  my $diffs;

  for my $k ( 0 .. $min_line - 1 )
  {
    $expected_char = substr $expected_line, $k, 1;
    $actual_char   = substr $actual_line,   $k, 1;
    if ( $expected_char ne $actual_char )
    {
      $diffs .= q{^};
      $failed = 1;
    }
    else
    {
      $diffs .= q{ };
    }
  }

  $diffs .= q{^} x ( $max_line - $min_line );

  if ($failed)
  {
    $failure_obj->set_failure(
      "Results or keys do not match on line $line_number",
      ">$expected_line<", ">$actual_line<", " $diffs" );
  }
  return $failure_obj;
}

sub compare_objects
{
  my $expected_obj = shift;
  my $actual_obj   = shift;
  my $failure_obj  = shift;

  if ( ref $actual_obj eq $PERL_ARRAY_REF_NAME )
  {
    my @expected_array = @{$expected_obj};
    my @actual_array   = @{$actual_obj};

    for my $i ( 0 .. scalar @actual_array - 1 )
    {
      compare_objects( $expected_array[$i], $actual_array[$i], $failure_obj );
      if ( $failure_obj->is_failure() )
      {
        $failure_obj->add_to_traceback("[ $i ]");
        last;
      }
    }
  }
  elsif ( ref $actual_obj eq 'HASH' )
  {
    my @expected_keys = keys %{$expected_obj};
    my @actual_keys   = keys %{$actual_obj};

    compare_keys( \@expected_keys, \@actual_keys, $failure_obj );

    if ( !$failure_obj->is_failure() )
    {
      foreach my $key ( keys %{$expected_obj} )
      {
        my $expected_value = $expected_obj->{$key};
        my $actual_value   = $actual_obj->{$key};

        compare_objects( $expected_value, $actual_value, $failure_obj );

        if ( $failure_obj->is_failure() )
        {
          $failure_obj->add_to_traceback("{ $key }");
          last;
        }
      }
    }
  }
  else
  {
    compare_strings( $expected_obj, $actual_obj, $failure_obj );
  }

  return $failure_obj;
}

sub compare_strings
{
  my $expected_string = shift;
  my $actual_string   = shift;
  my $failure_obj     = shift;

  if ( !defined $expected_string )
  {
    $expected_string = $EMPTY_STRING;
  }

  if ( !defined $actual_string )
  {
    $actual_string = $EMPTY_STRING;
  }

  my @expected_string_lines = split /[\n]/xms, $expected_string;
  my @actual_string_lines   = split /[\n]/xms, $actual_string;

  my $max_line = List::Util::max( scalar @expected_string_lines,
    scalar @actual_string_lines );

  my $line_count = 0;
  my $expected_line;
  my $actual_line;
  my $diffs          = $EMPTY_STRING;
  my $failed         = 0;
  my $failure_string = $EMPTY_STRING;

  for my $i ( 0 .. $max_line - 1 )
  {
    $line_count++;
    $expected_line = $expected_string_lines[$i];
    $actual_line   = $actual_string_lines[$i];

    Test::compare_lines( $expected_line, $actual_line, $line_count,
      $failure_obj );
    if ( $failure_obj->is_failure() )
    {
      last;
    }
  }
  return $failure_obj;
}

sub convert_to_response
{
  my $boolean = shift;
  my $response_text;
  if ($boolean)
  {
    $response_text = 'FAILED';
  }
  else
  {
    $response_text = 'OK    ';
  }
  return $response_text;
}

sub criticize
{
  Utils::format_print(
    Test::make_title( 'CRITIQUING', q{%}, $TEST_TITLE_WIDTH ) );

  my @files = Utils::get_perl_files();

  my $critic = Perl::Critic->new(
    -severity => $PERL_CRITIC_SEVERITY,
    -exclude  => ['RequireTidyCode']
  );

  Perl::Critic::Violation::set_format(
    "%m at line %l, column %c. %e. (%p)$NEWLINE");

  foreach my $f (@files)
  {
    my @violations = $critic->critique($f);

    my @file_contents          = Utils::write_file_to_array($f);
    my @line_length_violations = ();

    for my $i ( 0 .. scalar @file_contents - 1 )
    {
      if ( length $file_contents[$i] > $MAX_LINE_LENGTH )
      {
        push @line_length_violations,
            "Line length exceeds $MAX_LINE_LENGTH characters at line "
          . ( $i + 1 )
          . ".$NEWLINE";
      }
    }

    push @violations, @line_length_violations;

    my $number_of_violations = scalar @violations;
    Utils::format_print("Critiquing $f$NEWLINE");
    if ($number_of_violations)
    {
      Utils::format_print($NEWLINE);
      Utils::format_print( \@violations );
      Utils::format_print($NEWLINE);
    }
  }
  Utils::format_print($NEWLINE);
  return 1;
}

sub delete_players
{
  my $dbh = shift;

  foreach my $player ( @{$TEST_PLAYERS_TO_DELETE} )
  {
    my $statement = "DELETE FROM $PLAYERS_TABLE_NAME WHERE name='$player'";
    $dbh->do($statement);
  }
  return 1;
}

sub export_constants
{
  my $constants_filename = './modules/Constants.pm';

  my @lines              = Utils::write_file_to_array($constants_filename);
  my $exporting_regex    = 'our..EXPORT';
  my @exportables        = ();
  my $new_constants_file = $EMPTY_STRING;

  while (@lines)
  {
    my $line = shift @lines;
    if ( $line =~ /$exporting_regex/xms )
    {
      $new_constants_file .= $line;
      last;
    }
    if ( $line =~ /Readonly\sour\s(\$\S+)/xms )
    {
      push @exportables, $1;
    }
    $new_constants_file .= $line;
  }
  $new_constants_file
    .= "qw($NEWLINE"
    . ( join "$NEWLINE", @exportables )
    . "$NEWLINE);$NEWLINE$NEWLINE 1;";
  Utils::write_string_to_file( $new_constants_file, $constants_filename );
  return 1;
}

sub format_actual_report
{
  my $report       = shift;
  my @report_lines = split /[\n]/xms, $report;
  my $title        = $TEST_REPORT_TITLE . ': ';
  my $title_length = length $title;

  my $first_report_line = shift @report_lines;

  $first_report_line
    = $first_report_line ? $first_report_line : $EMPTY_STRING;

  my $formatted_report
    = ( sprintf "%-$TEST_CONTENT_PADDING" . 's', $title )
    . $first_report_line
    . $NEWLINE;

  for my $i ( 0 .. scalar @report_lines - 1 )
  {
    $formatted_report
      .= ( q{ } x $TEST_CONTENT_PADDING ) . $report_lines[$i] . $NEWLINE;
  }

  return $formatted_report . $NEWLINE;
}

sub get_status
{
  my $failure_object = shift;
  return (
    sprintf "%-$TEST_CONTENT_PADDING" . 's',
    ( $failure_object->get_type() . ' STATUS:' )
    )
    . Test::convert_to_response( $failure_object->is_failure() )
    . $NEWLINE;

}

sub harness
{
  my $arg_ref = shift;

  my $test_cases      = $arg_ref->{test_cases};
  my $exit_on_failure = $arg_ref->{exit_on_failure};

  my %test_cases_hashref = map { $_ => 1 } ( split /,/xms, $test_cases );
  my @active_test_cases  = (1) x ( $LAST_TC + 1 );

  if ( $test_cases && $test_cases ne $TEST_ARGUMENT_NOT_SET )
  {
    @active_test_cases = ();
    for my $i ( 1 .. $LAST_TC + 1 )
    {
      push @active_test_cases, $test_cases_hashref{$i} ? 1 : 0;
    }
  }

  Utils::format_print(
    Test::make_title( 'STARTING TEST HARNESS', q{%}, $TEST_TITLE_WIDTH ) );

  # Processing Errors
  Test::testrun(
    { title             => 'PROCESSING ERRORS',
      first_tc          => $FIRST_PROCESSING_ERRORS_TC,
      last_tc           => $LAST_PROCESSING_ERRORS_TC,
      active_test_cases => \@active_test_cases,
      exit_on_failure   => $exit_on_failure,
    }
  );

  # Processing Warnings
  Test::testrun(
    { title             => 'PROCESSING WARNINGS',
      first_tc          => $FIRST_PROCESSING_WARNINGS_TC,
      last_tc           => $LAST_PROCESSING_WARNINGS_TC,
      active_test_cases => \@active_test_cases,
      exit_on_failure   => $exit_on_failure,
    }
  );

  # TOU Processing Coverage
  Test::testrun(
    { title             => 'TOU PROCESSING COVERAGE',
      first_tc          => $FIRST_COVERAGE_TC,
      last_tc           => $LAST_COVERAGE_TC,
      active_test_cases => \@active_test_cases,
      exit_on_failure   => $exit_on_failure,
    }
  );

  if ($html)
  {
    Utils::fetch_local_tournament_data();
    
    my $filenames_array_ref;

    if ($full)
    {
      my $tou_data_directory = Utils::get_environment_name($TOURNAMENT_DATA_DIR);

      # Get the list of every .tou file that needs to be processed
      $filenames_array_ref = Utils::get_tournament_data_filenames(
        $tou_data_directory,             $DEFAULT_YEAR_REGEX,
        $DEFAULT_COUNTRY_TRIGRAPH_REGEX, $DEFAULT_FILE_REGEX
      );

      Update::load_tournament_data($filenames_array_ref);
    }
    else
    {
      # We gotta compare database results here
      # With just these test cases, the comparison
      # is manageable
      # Test::compare_database_results 
    }
    Update::update_html();
    Update::push_local_content();
  }

  # Utilities
  Test::testrun_utils( { active_test_cases => \@active_test_cases } );

  return 1;
}

sub list_standards_exceptions
{
  Utils::format_print(
    Test::make_title(
      'LISTING STANDARDS EXCEPTIONS',
      q{%}, $TEST_TITLE_WIDTH
    )
  );

  my @files = Utils::get_perl_files;

  while (@files)
  {
    my $file          = shift @files;
    my @file_contents = Utils::write_file_to_array($file);
    my @exceptions    = ();

    for my $i ( 0 .. scalar @file_contents - 1 )
    {
      my $line = $file_contents[$i];
      if ( $line =~ /[#][#][ ] no [ ] critic/xms )
      {
        push @exceptions, "$i: $line";
      }
    }

    my $number_of_exceptions = scalar @exceptions;

    Utils::format_print(
      "Listing standards exceptions for $file  ($number_of_exceptions)$NEWLINE"
    );

    if (@exceptions)
    {
      Utils::format_print(
        $NEWLINE . ( join $EMPTY_STRING, @exceptions ) . $NEWLINE );
    }
  }

  Utils::format_print( $NEWLINE . $NEWLINE );
  return 1;
}

sub make_title
{
  my $content = shift;
  my $char    = shift;
  my $width   = shift;

  my $border        = $char x $width;
  my $border_length = length $border;

  my $margin       = $border_length - ( length $content );
  my $left_margin  = $char x ( int( $margin / 2 ) - 1 );
  my $right_margin = $char x ( int( $margin / 2 ) - 1 );

  if ( $margin % 2 == 1 )
  {
    $right_margin .= $char;
  }

  my $title = "$border$NEWLINE";
  $title .= "$left_margin $content $right_margin$NEWLINE";
  $title .= "$border$NEWLINE$NEWLINE";

  return $title;
}

sub prepare
{
  Test::alphabetize_routine_order();
  Test::export_constants();
  Test::tidy();
  Test::check_syntax();
  Test::criticize();
  Test::list_standards_exceptions();
  return 1;
}

sub setup_testrun
{
  my $alt_names_hash = Utils::populate_alt_names_hash();
  my $deceased_players_hash
    = Utils::populate_deceased_players_hash($alt_names_hash);
  my $dbh = Utils::connect_to_database();

  Utils::drop_all_wespa_tables( $dbh, $alt_names_hash );
  Utils::initialize_database( $dbh, $TABLES, $TABLE_CREATION_ORDER );
  Test::delete_players($dbh);

  return ( $dbh, $alt_names_hash, $deceased_players_hash );
}

sub testcase
{
  my $arg_ref = shift;

  my $dbh                   = $arg_ref->{dbh};
  my $alt_names_hash        = $arg_ref->{alt_names_hash};
  my $deceased_players_hash = $arg_ref->{deceased_players_hash};
  my $player_data           = $arg_ref->{player_data};
  my $case                  = $arg_ref->{test_case_number};
  my $utilities             = $arg_ref->{utilities};

  my $padded_case = sprintf '%3s', $case;

  Utils::format_print(
    Test::make_title( "TEST CASE $padded_case", q{~}, $TEST_TITLE_WIDTH ) );

  my $tou_dir = $TEST_DIRECTORY . q{/} . $TEST_TOU_DIRECTORY . $TEST_TOU_PATH;
  my $json_dir = $TEST_DIRECTORY . q{/} . $TEST_JSON_DIRECTORY . q{/};

  my $file_number = $case;

  my $retested_file_number = $TEST_TC_RETESTS->{$file_number};

  if ($retested_file_number)
  {
    $file_number = $retested_file_number;
  }

  my $toufile = "$tou_dir$file_number.tou";

  my $actual_json_file   = "$json_dir$case.actual.json";
  my $expected_json_file = "$json_dir$case.json";

  if ( !$setexpected && !-e $expected_json_file )
  {
    croak "File does not exist: $expected_json_file$NEWLINE";
  }

  my $tou = TOU->new(
    { dbh                   => $dbh,
      filename              => $toufile,
      alt_names_hash        => $alt_names_hash,
      deceased_players_hash => $deceased_players_hash,
      player_data           => $player_data,
      correct               => $TEST_TC_CORRECTIONS->{$case},
    }
  );

  $tou->load($player_data);

  # Load the actual json
  my $unblessed_tou = $tou->get_unblessed_ref();

  my $actual_json = JSON::XS->new->pretty(1)->encode($unblessed_tou);

  Utils::write_string_to_file( $actual_json, $actual_json_file );

  if ($setexpected)
  {
    Utils::write_string_to_file( $actual_json, $expected_json_file );
  }

  # Load expected results
  my $expected_json = Utils::write_file_to_string($expected_json_file);

  my $json_failure_obj = Failure->new($JSON_FAILURE_TYPE);

  return (
    Test::compare_json( $expected_json, $actual_json, $json_failure_obj ),
    Test::format_actual_report( $tou->get_report() ) );
}

sub testrun
{
  my $arg_ref = shift;

  my $run_title         = $arg_ref->{title};
  my $first_tc          = $arg_ref->{first_tc};
  my $last_tc           = $arg_ref->{last_tc};
  my $active_test_cases = $arg_ref->{active_test_cases};
  my $exit_on_failure   = $arg_ref->{exit_on_failure};

  my $tests_present = 0;

  for my $i ( $first_tc .. $last_tc )
  {
    if ( $active_test_cases->[ $i - 1 ] )
    {
      $tests_present = 1;
      last;
    }
  }

  if ( !$tests_present )
  {
    return 1;
  }

  my ( $dbh, $alt_names_hash, $deceased_players_hash )
    = Test::setup_testrun();

  my $json_failure;
  my $expected_report;

  my $player_data = {};

  Utils::format_print(
    Test::make_title( "TEST RUN: $run_title", q{*}, $TEST_TITLE_WIDTH ) );

  for my $i ( $first_tc .. $last_tc )
  {
    if ( !$active_test_cases->[ $i - 1 ] )
    {
      next;
    }

    ( $json_failure, $expected_report ) = Test::testcase(
      { dbh                   => $dbh,
        alt_names_hash        => $alt_names_hash,
        deceased_players_hash => $deceased_players_hash,
        player_data           => $player_data,
        test_case_number      => $i,
      }
    );

    my $response_content = $EMPTY_STRING;

    if ( $json_failure->is_failure() )
    {
      $response_content .= $json_failure->to_string();
    }

    $response_content .= $expected_report;
    $response_content .= Test::get_status($json_failure);
    Utils::format_print($response_content);
    Utils::format_print("$NEWLINE$NEWLINE");

    if ( $exit_on_failure && $json_failure->is_failure() )
    {
      croak 'Croak is set: exiting on failure';
    }
  }

  return 1;
}

sub testrun_utils
{
  my $arg_ref = shift;

  my $active_test_cases = $arg_ref->{active_test_cases};

  if ( !$active_test_cases->[$LAST_TC] )
  {
    return 1;
  }

  Utils::format_print(
    Test::make_title( 'TEST RUN: UTILITIES', q{*}, $TEST_TITLE_WIDTH ) );

  Utils::format_print(
    Test::make_title(
      'TEST CASE ' . ( $LAST_TC + 1 ),
      q{~}, $TEST_TITLE_WIDTH
    )
  );

  my $actual_utils = $EMPTY_STRING;

  my $valid_flag   = 'USA.png';
  my $invalid_flag = 'USB.png';

  system "mv $COUNTRY_FLAGS_DIR/$valid_flag $COUNTRY_FLAGS_DIR/$invalid_flag";

  $actual_utils .= Utils::check_country_flag_icons( ['USA'] );

  system "mv $COUNTRY_FLAGS_DIR/$invalid_flag $COUNTRY_FLAGS_DIR/$valid_flag";

  # Load expected results
  my $utils_dir = $TEST_DIRECTORY . q{/} . $TEST_UTILS_DIRECTORY . q{/};
  my $expected_utils_file = "$utils_dir/utils.expected";
  my $actual_utils_file   = "$utils_dir/utils.actual";

  Utils::write_string_to_file( $actual_utils, $actual_utils_file );

  if ($setexpected)
  {
    Utils::write_string_to_file( $actual_utils, $expected_utils_file );
  }

  my $expected_utils = Utils::write_file_to_string($expected_utils_file);

  my $utils_failure_obj = Failure->new($UTILS_FAILURE_TYPE);

  Test::compare_objects( $expected_utils, $actual_utils, $utils_failure_obj );

  my $response_content = $EMPTY_STRING;

  if ( $utils_failure_obj->is_failure() )
  {
    $response_content .= $utils_failure_obj->to_string();
  }

  $response_content .= Test::format_actual_report($actual_utils);
  $response_content .= Test::get_status($utils_failure_obj);
  Utils::format_print($response_content);
  Utils::format_print("$NEWLINE$NEWLINE");

  return 1;
}

sub tidy
{
  Utils::format_print(
    Test::make_title( 'TIDYING', q{%}, $TEST_TITLE_WIDTH ) );

  my @files = Utils::get_perl_files;

  foreach my $f (@files)
  {
    Utils::format_print("Tidying $f$NEWLINE");
    system "perltidy -pbp -nst -ci=2 -i=2 -bl -b -bext='/' $f";
  }
  Utils::format_print($NEWLINE);
  return 1;
}

1;
