#!/usr/bin/perl

package Test;

use strict;
use warnings;
use Data::Dumper;

use lib './objects';
use lib './modules';

use Constants;
use HTML;
use Utils;
use JSON::XS;

sub Harness
{
  testrun();
}

sub setup_testrun
{
  my $alt_names_hash = Utils::populate_alt_names_hash();
  my $deceased_players_hash = Utils::populate_deceased_players_hash($alt_names_hash);
  my $dbh = Utils::connect_to_database();
  Utils::drop_all_wespa_tables($dbh, $alt_names_hash);
  Utils::initialize_database($dbh, Constants::TABLES, Constants::TABLE_CREATION_ORDER);
  return ($dbh, $alt_names_hash, $deceased_players_hash);
}

sub convert_to_response_text
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

sub compare_keys
{
  my $expected_keys_ref = shift;
  my $actual_keys_ref   = shift;

  my @expected_keys   = map { [$_, 1]  } @{$expected_keys_ref};
  my @actual_keys     = map { [$_, 1]  } @{$actual_keys_ref};

  for (my $i = 0; $i < scalar @expected_keys; $i++)
  {
    for (my $k = 0; $k < scalar @actual_keys; $k++)
    {
      my $expected_item = $expected_keys[$i];
      my $actual_item   = $actual_keys[$k];
      if ($actual_item->[0] eq $expected_item->[0])
      {
        $expected_item->[1] = 0;
        $actual_item->[1]   = 0;
      }
    }
  }

  my @expected_leftover = grep { $_->[1] } @expected_keys;
  my @actual_leftover   = grep { $_->[1] } @actual_keys;
  my $failed = 0;
  if (@expected_leftover || @actual_leftover)
  {
    print "Mismatching keys:\n";
    print "Missing keys: " . (join ",", @expected_leftover) . "\n";
    print "Extra keys:   " . (join ",", @actual_leftover)   . "\n";
    $failed = 1;
  }
  return $failed;
}

sub compare_json
{
  my $expected_json = shift;
  my $actual_json = shift;

  my $expected_obj = JSON::XS::decode_json($expected_json); 
  my $actual_obj = JSON::XS::decode_json($actual_json);

  my @expected_keys = keys %{$expected_obj};
  my @actual_keys   = keys %{$actual_obj};

  my $failed        = compare_keys(\@expected_keys, \@actual_keys);

  if (!$failed)
  {
    foreach my $key (keys %{$expected_obj})
    {
      my $expected_value = $expected_obj->{$key};
      my $actual_value = $actual_obj->{$key};

      $failed = compare_strings($expected_value, $actual_value);

      if ($failed)
      {
        last;
      }
    }
  }
  return $failed;
}

sub compare_strings
{
  my $expected_string = shift;
  my $actual_string = shift;

  my @expected_string_lines = split/\n/, $expected_string;
  my @actual_string_lines = split/\n/, $actual_string;

  my $line_count = 1;
  my @expected_string_chars;
  my @actual_string_chars;
  my $expected_char;
  my $actual_char;
  my @diffs;
  my $min_line;
  my $max_line;
  my $swap;
  my $failed = 0;

  for (my $i = 0; $i < scalar @expected_string_lines; $i++)
  {
    @expected_string_chars = split //, $expected_string_lines[$i];
    @actual_string_chars = split //, $actual_string_lines[$i];
    $min_line = scalar @expected_string_chars;
    $max_line = scalar @actual_string_chars;

    if ($min_line != $max_line)
    {
      $failed = 1;
    }

    if ($max_line < $min_line)
    {
      $swap = $min_line;
      $min_line = $max_line;
      $max_line = $swap;
    }

    for (my $k = 0; $k < $min_line; $k++)
    {
      $expected_char = $expected_string_chars[$k];
      $actual_char = $actual_string_chars[$k];
      if ($expected_char ne $actual_char)
      {
        $diffs[$k] = '^';
        $failed = 1;
      }
      else
      {
        $diffs[$k] = ' ';
      }
    }
    for (my $j = 0; $j < $max_line - $min_line; $j++)
    {
      push @diffs, '~';
    }
  }
  return $failed;
}

sub testcase
{
  my $dbh                   = shift;
  my $alt_names_hash        = shift;
  my $deceased_players_hash = shift;
  my $case                  = shift;

  my $test_dir         = Constants::TEST_DIRECTORY;

  my $toufile          = $test_dir . '/' . Constants::TEST_TOU_DIRECTORY . '/' . $case . '.tou';

  # Load expected results
  my $expected_stdout  = $test_dir . '/' . Constants::TEST_STDOUT_DIRECTORY . '/' . $case . '.stdout';
  my $expected_json    = $test_dir . '/' . Constants::TEST_JSON_DIRECTORY . '/' . $case . '.json';

  # Load the actual stdout
  my $actual_stdout;
  open (my $fhstdout, '>>', \$actual_stdout);

  select $fhstdout;

  my $tou = TOU->new(
                      $dbh,
                      $toufile,
                      $alt_names_hash,
                      $deceased_players_hash
                    );

  select STDOUT;

  # Load the actual json
  my $actual_json = JSON::XS::encode_json($tou);
  
  return (
           Test::compare_strings($expected_stdout, $actual_stdout),
           Test::compare_json($expected_json,   $actual_json),
         );
}

sub testrun
{
  my ($dbh, $alt_names_hash, $deceased_players_hash) = Test::setup_testrun();

  my $test_dir = Constants::TEST_DIRECTORY;
  my $tou_dir  = $test_dir . '/' . Constants::TEST_TOU_DIRECTORY;

  opendir (my $dh, $tou_dir) or die "Cannot open directory $tou_dir: $!\n";
  my @toufiles = map { $test_dir . '/' . $_  } (grep {/tou/} readdir ($dh));
  my $stdout_response;
  my $json_response;

  for (my $i = 0; $i < scalar @toufiles; $i++)
  {
    print "Test Case $i\n";

    ($stdout_response, $json_response) = 
      testcase(
                $dbh,
                $alt_names_hash,
                $deceased_players_hash,
                $i
              );

    print "  STDOUT: $stdout_response\n";
    print "  JSON:   $json_response\n";
    print "\n";
  }
}

1;
