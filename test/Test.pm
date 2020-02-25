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

use lib './objects';
use lib './modules';

use Constants;
use Failure;
use HTML;
use TOU;
use Utils;
use JSON::XS;

my $alphabetize;
my $criticize;
my $export;
my $setexpected;
my $syntax;

GetOptions
(
  alphabetize => \$alphabetize,
  criticize   => \$criticize,
  export      => \$export,
  setexpected => \$setexpected,
  syntax      => \$syntax
);


if ($alphabetize)
{
  Test::alphabetize_routine_order();
}
if ($criticize)
{
  Test::criticize();
}
if ($export)
{
  Test::export_constants();
}
if ($syntax)
{
  Test::check_syntax();
}
if (!$alphabetize && !$criticize && !$export && !$syntax)
{
  Test::check_syntax();
  Test::alphabetize_routine_order();
  Test::harness();
}


sub export_constants
{
  my $constants_filename = './modules/Constants.pm';

  my @lines = Utils::write_file_to_array($constants_filename);
  my $exporting_comment = 'BEGIN EXPORT';
  my $exporting_regex   = $exporting_comment;
     $exporting_regex   =~ s/\s/\\s/gxms;
  my @exportables = ();
  my $new_constants_file = $EMPTY_STRING;
  
  while (@lines)
  {
    my $line = shift @lines;
    if ($line =~ /$exporting_regex/xms)
    {
      $new_constants_file .= q{# } . $exporting_comment . "\n";
      last;
    }
    if ($line =~ /Readonly\sour\s(\$\S+)/xms)
    {
      push @exportables, $1;
    }
    $new_constants_file .= $line;
  }
  $new_constants_file .= "our \@EXPORT = qw(\n" . (join "\n", @exportables) . "\n);\n\n1;";
  Utils::write_string_to_file($new_constants_file, $constants_filename);
  return 1;
}

sub alphabetize_routine_order
{
  print Test::make_title('ALPHABETIZING ROUTINE ORDER', q{%}, $TEST_TITLE_WIDTH);

  my $directories = $PERL_DIRECTORIES;

  my @files = ();

  foreach my $dir (@{$directories})
  {
    my $fh_dir;
    opendir $fh_dir, $dir;
    push @files, map {$dir . q{/} . $_} (grep {/\.p[ml]/xms} readdir $fh_dir);
  }

  foreach my $f (@files)
  {
    my $routine_hash    = {};
    my $current_routine;
    my $in_current_routine = 0;
    my $file_string = $EMPTY_STRING;
    my @file_lines = Utils::write_file_to_array($f);
    while(@file_lines)
    {
      my $current_line = shift @file_lines;
      if ($current_line =~ /^sub (.*)/xms)
      {
        $current_routine = $1;
        $current_routine =~ s/\s//gxms;
        $routine_hash->{$current_routine} = $EMPTY_STRING;
      }
      elsif (!$current_routine)
      {
        $file_string .= $_;
      }
      elsif ($current_line =~ /^\{\s*/xms)
      {
        $in_current_routine = 1;
      }
      elsif ($current_line =~ /^\}\s*/xms)
      {
        $in_current_routine = 0;
      }
      elsif ($in_current_routine)
      {
        $routine_hash->{$current_routine} .= $_;
      }
    }
    if ($current_routine)
    {
      my @alphabetized_routine_keys = sort keys %{$routine_hash};

      my $alphabetized_file = $EMPTY_STRING;


      $alphabetized_file .= $file_string;
      for my $i (0 .. scalar @alphabetized_routine_keys - 1)
      {
        my $key = $alphabetized_routine_keys[$i];
        my $routine_content = $routine_hash->{$key};
        $alphabetized_file .= "sub $key\n";
        $alphabetized_file .= "{\n";
        $alphabetized_file .= $routine_content;
        $alphabetized_file .= "}\n\n";
      }
      $alphabetized_file .= '1;';

      my $original_file = Utils::write_file_to_string($f);

      if ($original_file ne $alphabetized_file)
      {
        Utils::write_string_to_file($alphabetized_file, $f);
        printf "Alphabetized %30s\n", $f;
      }
    }
  }
  return 1;
}

sub check_syntax
{
  print Test::make_title('CHECKING SYNTAX', q{%}, $TEST_TITLE_WIDTH);
  my $directories = $PERL_DIRECTORIES;
  my $dirs = $EMPTY_STRING;
  for my $i (0 .. scalar @{$directories} - 1)
  {
    $dirs .= $directories->[$i] . q{ };
  }

  my $cmd = "find $dirs -name \"*.p[lm]\" | ";

  my @cmd_lines = Utils::write_file_to_array($cmd);
  while (@cmd_lines)
  {
    my $file = shift @cmd_lines;
    system "perl -cw $file";
  }
  print "\n";
  return 1;
}

sub compare_json
{
  my $expected_json = shift;
  my $actual_json   = shift;
  my $failure_obj   = shift;

  my $expected_obj = JSON::XS::decode_json($expected_json); 
  my $actual_obj   = JSON::XS::decode_json($actual_json);

  return compare_objects($expected_obj, $actual_obj, $failure_obj);
}

sub compare_keys
{
  my $expected_keys_ref = shift;
  my $actual_keys_ref   = shift;
  my $failure_obj       = shift;

  my $expected_keys   = join q{,}, sort @{$expected_keys_ref};
  my $actual_keys     = join q{,}, sort @{$actual_keys_ref};

  return Test::compare_lines(
                              $expected_keys,
                              $actual_keys,
                              0,
                              $failure_obj
                            );
}

sub compare_lines
{
  my $expected_line = shift;
  my $actual_line   = shift;
  my $line_number   = shift;
  my $failure_obj   = shift;

  if (! defined $actual_line)
  {
    $actual_line = $EMPTY_STRING;
  }

  if (! defined $expected_line)
  {
    $expected_line = $EMPTY_STRING;
  }
  
  my $min_line = length $expected_line;
  my $max_line = length $actual_line;

  my $failed = 0;
  
  if ($min_line != $max_line)
  {
    $failed = 1;
  }

  if ($max_line < $min_line)
  {
    my $swap = $min_line;
    $min_line = $max_line;
    $max_line = $swap;
  }

  my $expected_char;
  my $actual_char;
  my $diffs;

  for my $k (0 .. $min_line - 1)
  {
    $expected_char = substr($expected_line, $k, 1);
    $actual_char   = substr($actual_line, $k, 1);
    if ($expected_char ne $actual_char)
    {
      $diffs .= q{^};
      $failed = 1;
    }
    else
    {
      $diffs .= q{ };
    }
  }

  $diffs .= q{^} x ($max_line - $min_line);

  if ($failed)
  {
    $failure_obj->set_failure(
                               "Results or keys do not match on line $line_number",
                               ">$expected_line<",
                               ">$actual_line<",
                               " $diffs"
                             );
  }
  return $failure_obj;
}

sub compare_objects
{
  my $expected_obj = shift;
  my $actual_obj   = shift;
  my $failure_obj  = shift;

  if (ref($actual_obj) eq 'ARRAY')
  {
    my @expected_array = @{$expected_obj};
    my @actual_array   = @{$actual_obj};

    for my $i (0 .. scalar @actual_array - 1)
    {
      compare_objects(
                       $expected_array[$i],
                       $actual_array[$i],
                       $failure_obj
                     );
      if ($failure_obj->is_failure())
      {
        $failure_obj->add_to_traceback("[ $i ]");
        last;
      }
    } 
  }
  elsif (ref($actual_obj) eq 'HASH')
  {
    my @expected_keys = keys %{$expected_obj};
    my @actual_keys   = keys %{$actual_obj};

    compare_keys(\@expected_keys, \@actual_keys, $failure_obj);

    if (!$failure_obj->is_failure())
    {
      foreach my $key (keys %{$expected_obj})
      {
        my $expected_value = $expected_obj->{$key};
        my $actual_value   = $actual_obj->{$key};
    
        compare_objects(
                         $expected_value,
                         $actual_value,
                         $failure_obj
                       );

        if ($failure_obj->is_failure())
        {
          $failure_obj->add_to_traceback("{ $key }");
          last;
        }
      }
    }
  }
  else
  {
    compare_strings($expected_obj, $actual_obj, $failure_obj);
  }

  return $failure_obj;
}

sub compare_strings
{
  my $expected_string = shift;
  my $actual_string   = shift;
  my $failure_obj     = shift;

  if (! defined $expected_string)
  {
    $expected_string = $EMPTY_STRING;
  }

  if (! defined $actual_string)
  {
    $actual_string = $EMPTY_STRING;
  }

  my @expected_string_lines = split/\n/xms, $expected_string;
  my @actual_string_lines   = split/\n/xms, $actual_string;

  my $max_line = List::Util::max(scalar @expected_string_lines, scalar @actual_string_lines);

  my $line_count = 0;
  my $expected_line;
  my $actual_line;
  my $diffs = $EMPTY_STRING;
  my $failed = 0;
  my $failure_string = $EMPTY_STRING;

  for my $i (0 .. $max_line - 1)
  {
    $line_count++;
    $expected_line = $expected_string_lines[$i];
    $actual_line   = $actual_string_lines[$i];

    Test::compare_lines(
                         $expected_line,
                         $actual_line,
                         $line_count,
                         $failure_obj
                       );
    if ($failure_obj->is_failure())
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
  print Test::make_title('CRITIQUING', q{%}, $TEST_TITLE_WIDTH);

  my $directories = $PERL_DIRECTORIES;
  
  my @files = ();
  
  foreach my $dir (@{$directories})
  {
    opendir (my $fh_dir, $dir);
    push @files, map {$dir . q{/} . $_} (grep {/\.p[ml]/xms} readdir $fh_dir);
  }
    
  my $critic = Perl::Critic->new( -severity => 1);
  
  foreach my $f (@files)
  {
    print "$f\n\n";
    print $critic->critique($f);
    print "\n\n";
  }

  return 1;
}

sub format_expected_stdout
{
  my $stdout = shift;
  my @stdout_lines = split /\n/xms, $stdout;
  my $title = 'EXPECTED STDOUT: ';
  my $title_length = length $title;

  my $formatted_stdout = $title;
  for my $i (0 .. scalar @stdout_lines - 1)
  {
    if ($i == 0)
    {
      $formatted_stdout .= $stdout_lines[$i] . "\n";
    }
    else
    {
      $formatted_stdout .= (q{ } x $title_length) . $stdout_lines[$i] . "\n";
    }
  }
  return $formatted_stdout . "\n";
}

sub make_title
{
  my $content = shift;
  my $char    = shift;
  my $width   = shift;

  my $border        = $char x $width;
  my $border_length = length $border;

  my $margin       = $border_length - (length $content);
  my $left_margin  = $char x (int ($margin / 2 ) - 1);
  my $right_margin = $char x (int ($margin / 2 ) - 1);

  if ($margin % 2 == 1)
  {
    $right_margin .= $char;
  }

  my $title =  "$border\n";
     $title .= "$left_margin $content $right_margin\n";
     $title .= "$border\n\n";

  return $title;
}

sub setup_testrun
{
  my $alt_names_hash        = Utils::populate_alt_names_hash();
  my $deceased_players_hash = Utils::populate_deceased_players_hash($alt_names_hash);
  my $dbh                   = Utils::connect_to_database();

  Utils::drop_all_wespa_tables($dbh, $alt_names_hash);
  Utils::initialize_database($dbh, $TABLES, $TABLE_CREATION_ORDER);

  return ($dbh, $alt_names_hash, $deceased_players_hash);
}

sub testcase
{
  my $dbh                   = shift;
  my $alt_names_hash        = shift;
  my $deceased_players_hash = shift;
  my $player_data           = shift;
  my $case                  = shift;

  my $padded_case = sprintf "%3s", $case;

  print Test::make_title("TEST CASE $padded_case", q{~}, $TEST_TITLE_WIDTH);

  my $test_dir   = $TEST_DIRECTORY;
  my $tou_dir    = $test_dir . q{/} . $TEST_TOU_DIRECTORY . $TEST_TOU_PATH;
  my $stdout_dir = $test_dir . q{/} . $TEST_STDOUT_DIRECTORY . q{/};
  my $json_dir   = $test_dir . q{/} . $TEST_JSON_DIRECTORY . q{/};

  my $toufile          = "$tou_dir$case.tou";

  my $actual_stdout_file   = "$stdout_dir$case.actual.stdout";
  my $actual_json_file     = "$json_dir$case.actual.json" ;
  my $expected_stdout_file = "$stdout_dir$case.stdout";
  my $expected_json_file   = "$json_dir$case.json";

  if (!$setexpected && ! -e $expected_stdout_file)
  {
    die "File does not exist: $expected_stdout_file\n";
  }
  if (!$setexpected && ! -e $expected_json_file)
  {
    die "File does not exist: $expected_json_file\n";
  }

  # Load the actual stdout
  my $actual_stdout;
  open (my $fhstdout, '>>', \$actual_stdout) or die "Cannot even: $OS_ERROR\n";

  select $fhstdout;

  Utils::check_country_flag_icons(['USA']);

  my $tou = TOU->new({
                      dbh                   => $dbh,
                      filename              => $toufile,
                      alt_names_hash        => $alt_names_hash,
                      deceased_players_hash => $deceased_players_hash,
                      player_data           => $player_data
                     });

  $tou->load($player_data);

  select STDOUT;
  
  close $fhstdout or croak "Cannot close file handle: $OS_ERROR\n";

  if (!$actual_stdout)
  {
    $actual_stdout = $EMPTY_STRING;
  }

  Utils::write_string_to_file($actual_stdout, $actual_stdout_file);

  # Load the actual json
  my $unblessed_tou = $tou->get_unblessed_ref();

  my $actual_json = JSON::XS->new->pretty(1)->encode($unblessed_tou);

  Utils::write_string_to_file($actual_json, $actual_json_file);

  if ($setexpected)
  {
    Utils::write_string_to_file($actual_stdout, $expected_stdout_file);
    Utils::write_string_to_file($actual_json,   $expected_json_file);
  }

  # Load expected results
  my $expected_stdout  = Utils::write_file_to_string(
                                                $expected_stdout_file
                                              );

  my $expected_json    = Utils::write_file_to_string(
                                                $expected_json_file
                                              );


  my $stdout_failure_obj = Failure->new($STDOUT_FAILURE_TYPE);
  my $json_failure_obj   = Failure->new($JSON_FAILURE_TYPE);

  return (
           Test::compare_strings($expected_stdout, $actual_stdout, $stdout_failure_obj),
           Test::compare_json($expected_json,   $actual_json, $json_failure_obj),
           Test::format_expected_stdout($expected_stdout)
         );
}

sub testrun
{
  my $run_title = shift;
  my $first_tc  = shift;
  my $last_tc   = shift;

  my ($dbh, $alt_names_hash, $deceased_players_hash) = Test::setup_testrun();

  my $test_dir = $TEST_DIRECTORY;

  my $stdout_failure;
  my $json_failure;
  my $expected_stdout;

  my $player_data = {};

  print Test::make_title("TEST RUN: $run_title", q{*}, $TEST_TITLE_WIDTH);

  for my $i ($first_tc .. $last_tc)
  {

    ($stdout_failure, $json_failure, $expected_stdout) = 
      Test::testcase(
                      $dbh,
                      $alt_names_hash,
                      $deceased_players_hash,
                      $player_data,
                      $i
                    );

    my $response_content = $EMPTY_STRING;

    if ($stdout_failure->is_failure())
    {
      $response_content .= $stdout_failure->to_string();
    }
    if ($json_failure->is_failure())
    {
      $response_content .= $json_failure->to_string();
    }

    $response_content .= $expected_stdout;
    $response_content .= (sprintf "%-17s", ($stdout_failure->get_type() . ' STATUS:')) . Test::convert_to_response($stdout_failure->is_failure()) . "\n";
    $response_content .= (sprintf "%-17s", ($json_failure->get_type() . ' STATUS:')) . Test::convert_to_response($json_failure->is_failure()) . "\n";
    print $response_content;
    print "\n\n";
  }

  return 1;
}

1;