#!/usr/bin/perl

package Test;

use strict;
use warnings;
use Data::Dumper;
use Getopt::Long;

use lib './objects';
use lib './modules';

use Constants;
use Failure;
use HTML;
use TOU;
use Utils;
use JSON::XS;

my $syntax;

GetOptions
(
  syntax => \$syntax,
);

run(
     $syntax
   );

sub run
{
  my $syntax = shift;

  Test::print_title("CHECKING SYNTAX");
  Test::check_syntax();
  if ($syntax) {return;}
  print "\n\n";
  Test::print_title("CHECKING FOR REDUNDANT SUBS");
  Test::check_for_repeat_subs();
  print "\n\n";
  Test::print_title("RUNNING TESTS");
  Test::Harness();
}

sub Harness
{
  testrun();
}

sub setup_testrun
{
  my $alt_names_hash        = Utils::populate_alt_names_hash();
  my $deceased_players_hash = Utils::populate_deceased_players_hash($alt_names_hash);
  my $dbh                   = Utils::connect_to_database();

  Utils::drop_all_wespa_tables($dbh, $alt_names_hash);
  Utils::initialize_database($dbh, Constants::TABLES, Constants::TABLE_CREATION_ORDER);

  return ($dbh, $alt_names_hash, $deceased_players_hash);
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

sub compare_lines
{
  my $expected_line = shift;
  my $actual_line   = shift;
  my $line_number   = shift;
  my $failure_obj   = shift;

  if (! defined $actual_line)
  {
    $actual_line = Constants::UNDEFINED_STRING;
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

  for (my $k = 0; $k < $min_line; $k++)
  {
    $expected_char = substr($expected_line, $k, 1);
    $actual_char   = substr($actual_line, $k, 1);
    if ($expected_char ne $actual_char)
    {
      $diffs .= '^';
      $failed = 1;
    }
    else
    {
      $diffs .= ' ';
    }
  }
  $diffs .= '^' x ($max_line - $min_line);

  if ($failed)
  {
    $failure_obj->set_failure(
                               "Results or keys do not match on line $line_number",
                               $expected_line,
                               $actual_line,
                               $diffs
                             );
  }

  return $failure_obj;
}

sub compare_keys
{
  my $expected_keys_ref = shift;
  my $actual_keys_ref   = shift;
  my $failure_obj       = shift;

  my $expected_keys   = join ",", sort @{$expected_keys_ref};
  my $actual_keys     = join ",", sort @{$actual_keys_ref};

  return Test::compare_lines(
                              $expected_keys,
                              $actual_keys,
                              0,
                              $failure_obj
                            );
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

    for (my $i = 0; $i < scalar @actual_array; $i++)
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

sub compare_json
{
  my $expected_json = shift;
  my $actual_json   = shift;
  my $failure_obj   = shift;

  my $expected_obj = JSON::XS::decode_json($expected_json); 
  my $actual_obj   = JSON::XS::decode_json($actual_json);

  return compare_objects($expected_obj, $actual_obj, $failure_obj);
}

sub compare_strings
{
  my $expected_string = shift;
  my $actual_string   = shift;
  my $failure_obj     = shift;

  my @expected_string_lines = split/\n/, $expected_string;
  my @actual_string_lines   = split/\n/, $actual_string;

  my $line_count = 0;
  my $expected_line;
  my $actual_line;
  my $diffs = '';
  my $failed = 0;
  my $failure_string = '';

  for (my $i = 0; $i < scalar @expected_string_lines; $i++)
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

sub testcase
{
  my $dbh                   = shift;
  my $alt_names_hash        = shift;
  my $deceased_players_hash = shift;
  my $player_data           = shift;
  my $case                  = shift;

  my $padded_case = sprintf "%3s", $case;

  print "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n";
  print "~~~~~~~~~~~~ TEST CASE $padded_case ~~~~~~~~~~~~\n";
  print "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n\n";

  my $test_dir   = Constants::TEST_DIRECTORY;
  my $tou_dir    = $test_dir . '/' . Constants::TEST_TOU_DIRECTORY . '/';
  my $stdout_dir = $test_dir . '/' . Constants::TEST_STDOUT_DIRECTORY . '/';
  my $json_dir   = $test_dir . '/' . Constants::TEST_JSON_DIRECTORY . '/';

  my $toufile          = "$tou_dir$case.tou";

  my $expected_stdout_file = "$stdout_dir$case.stdout";
  my $expected_json_file   = "$json_dir$case.json";

  if (! -e $expected_stdout_file)
  {
    die "File does not exist: $expected_stdout_file\n";
  }
  if (! -e $expected_json_file)
  {
    die "File does not exist: $expected_json_file\n";
  }

  # Load expected results
  my $expected_stdout  = Utils::write_file_to_string(
                                                $expected_stdout_file
                                              );

  my $expected_json    = Utils::write_file_to_string(
                                                $expected_json_file
                                              );
  # Load the actual stdout
  my $actual_stdout;
  open (my $fhstdout, '>>', \$actual_stdout);

  select $fhstdout;

  my $tou = TOU->new(
                      $dbh,
                      $toufile,
                      $alt_names_hash,
                      $deceased_players_hash,
                      $player_data
                    );

  select STDOUT;

  if (!defined $actual_stdout)
  {
    $actual_stdout = Constants::UNDEFINED_STRING;
  }

  Utils::write_string_to_file($actual_stdout, "$stdout_dir$case.actual.stdout");

  # Load the actual json
  my $unblessed_tou = $tou->get_unblessed_ref();
  #print Dumper($unblessed_tou);
  my $actual_json = JSON::XS::encode_json($unblessed_tou);

  Utils::write_string_to_file($actual_json, "$json_dir$case.actual.json");

  my $stdout_failure_obj = Failure->new(Constants::STDOUT_FAILURE_TYPE);
  my $json_failure_obj   = Failure->new(Constants::JSON_FAILURE_TYPE);

  return (
           Test::compare_strings($expected_stdout, $actual_stdout, $stdout_failure_obj),
           Test::compare_json($expected_json,   $actual_json, $json_failure_obj),
           Test::format_expected_stdout($expected_stdout)
         );
}

sub format_expected_stdout
{
  my $stdout = shift;
  my @stdout_lines = split /\n/, $stdout;
  my $title = 'EXPECTED STDOUT: ';
  my $title_length = length $title;

  my $formatted_stdout = $title;
  for (my $i = 0; $i < scalar @stdout_lines; $i++)
  {
    if ($i == 0)
    {
      $formatted_stdout .= $stdout_lines[$i] . "\n";
    }
    else
    {
      $formatted_stdout .= (' ' x $title_length) . $stdout_lines[$i] . "\n";
    }
  }
  return $formatted_stdout . "\n";
}

sub testrun
{
  my ($dbh, $alt_names_hash, $deceased_players_hash) = Test::setup_testrun();

  my $test_dir = Constants::TEST_DIRECTORY;
  my $tou_dir  = $test_dir . '/' . Constants::TEST_TOU_DIRECTORY . '/aardvark/2020/USA';

  opendir (my $dh, $tou_dir) or die "Cannot open directory $tou_dir: $!\n";

  # Only get files ending with 'tou'
  my @toufiles =  (grep {/tou$/} readdir ($dh));

  # Remove .tou extension and sort in numerical ascending order
  @toufiles = sort {$a <=> $b} map { s/\.tou//gr;  } @toufiles;

  # Add missing tournament for testing
  unshift @toufiles, 1;

  my $stdout_failure;
  my $json_failure;
  my $expected_stdout;

  my $player_data = {};

  for (my $i = 0; $i < scalar @toufiles; $i++)
  {

    ($stdout_failure, $json_failure, $expected_stdout) = 
      Test::testcase(
                      $dbh,
                      $alt_names_hash,
                      $deceased_players_hash,
                      $player_data,
                      $toufiles[$i]
                    );

    my $response_content = '';

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
    if ($stdout_failure->is_failure() || $json_failure->is_failure())
    {
      last;
    }
  }
}

sub print_title
{
  my $title = shift;
  $title =~ s/^\s+|\s+$//g;
  my $border = '***************************************';
  my $border_length = length $border;
  my $margin = $border_length - (length $title);
  my $left_margin = '*' x (int ($margin / 2 ) - 1);
  my $right_margin = '*' x (int ($margin / 2 ) - 1);
  if ($margin % 2 == 1)
  {
    $right_margin .= '*';
  }
  print <<TITLE
$border
$left_margin $title $right_margin
$border
TITLE
;

}

sub check_for_repeat_subs
{
  my $directories = Constants::PERL_DIRECTORIES;
  
  my @files = ();
  
  foreach my $dir (@{$directories})
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

  my $ignore = {
                 'to_string'  => 1,
                 'initialize' => 1,
                 'process'    => 1
               };

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
          if ($sub1 eq $sub2 && !$ignore->{$sub1})
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
  my $directories = Constants::PERL_DIRECTORIES;
  my $dirs = '';
  for (my $i = 0; $i < scalar @{$directories}; $i++)
  {
    $dirs .= $directories->[$i] . ' ';
  }

  my $cmd = "find $dirs -name \"*.p[lm]\" | ";

  open (CMDOUT, $cmd) or die "$!\n";
  while (<CMDOUT>)
  {
    system "perl -cw $_";
  }
}

1;

