#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Long;
use Pod::Usage qw(pod2usage);
use DBI;
use Data::Dumper;
use Term::ANSIColor;
use List::Util qw(max);

use lib './modules';
use Constants;

unless (caller)
{

  my $input_filename = '';
  my $output_filename = '';

  GetOptions (
               'input=s'  => \$input_filename,
               'output=s' => \$output_filename,
             ); 

  my $reports_string = parse_reports(fill_and_check_tournament($input_filename, $output_filename), $input_filename, $output_filename);
  print $reports_string;
}

sub parse_reports
{
  my $reports_ref = shift;
  my $input_filename = shift;
  my $output_filename = shift;

  my $stmt = "";

  my @reports_array = @{$reports_ref};

  for (my $i = 0; $i < scalar @reports_array; $i++)
  {
    my $div_report = $reports_array[$i];
    my $fill_info  = $div_report->[0];
    my $no_success = $div_report->[1];
    my $div_name   = $div_report->[2];

    if (($fill_info || $no_success) && !$stmt)
    {
      $stmt .= "WARNING:       missing or invalid games found in .tou\nFile:          $input_filename\n";
    }
    if ($fill_info || $no_success)
    {
      $stmt .= "Division:      $div_name\n";
    }
    if ($fill_info)
    {
      $stmt .= "Byes added:    $fill_info\n\n";
    }
    elsif ($no_success)
    {
      $stmt .= "Errors:\n$no_success\n\n";
    }
  }

  return $stmt;
}

sub fill_and_check_tournament
{
    my $input_filename = shift;
    my $output_filename = shift;

    if (!$input_filename || !$output_filename){die "Must specify input and output files";}

    my $line_number = 1;
    my $div_name;
    my @division_data_array = ();
    my %file_contents = ();
    my $new_lines_hashref = {};
    my $tourney_length = 0;

    my @division_reports = ();

    open(INPUT_FILE, "<", $input_filename) or die "Cannot open .tou file $input_filename: $!";
    while(<INPUT_FILE>)
    {
      $file_contents{$line_number} = $_;
      chomp $_;
      my $at_end = $_ =~ /END OF FILE/;
      if ($_ =~ /^\*(.*)/ || $at_end)
      {
        # Send it if a division ended
        if (@division_data_array)
        {
          # print Dumper(\@division_data_array);
          my $div_report = fill_and_check_division(\@division_data_array, $tourney_length, $new_lines_hashref);
          $div_report->[2] = $div_name;
          push @division_reports, $div_report;
        }
        # Restart it
        if (!$at_end)
        {
          $div_name = $1;
          $div_name =~ s/^\s+|\s+$//g;
          @division_data_array = ();
          $tourney_length = 0;
        }
      }
      elsif ($_ =~ /\w\s+(\d+\s+\+?\d+(\s+|$))+/)
      {
        if (!$div_name){die "No div name at line $line_number\n";}

        my @player_game_data = split/\s+/, $_;
    
        my @games = ();

        my $games_played = () = $_ =~ /(\d+\s+\+?\d+(?:\s+|$))/g;

        $tourney_length = max($games_played, $tourney_length);

        for(my $i = 0; $i < $games_played; $i++)
        {
          my $opp_number  = pop @player_game_data;
          my $score       = pop @player_game_data;

          $opp_number =~ s/\D//g;
          $score      =~ s/\D//g;

          unshift @games, [$score, $opp_number];
        }

        my $player_name = join " ", @player_game_data;
        $player_name =~ s/^\s+|\s+$//g;

        unshift @games, $player_name;

        if (!@division_data_array)
        {
          unshift @division_data_array, $line_number;
        }

        push @division_data_array, \@games;
      }
      $line_number++; 
    }

    my $new_file = 0;

    foreach my $report (@division_reports)
    {
      if ($report->[0] && !$report->[1])
      {
        open(my $fh, ">", $output_filename);
        for (my $i = 1; $i < $line_number; $i++)
        {
          my $maybe_new_line = $new_lines_hashref->{$i};
          if ($maybe_new_line)
          {
            print $fh $maybe_new_line;
          }
          else
          {
            print $fh $file_contents{$i};
          }
        }
        close $fh;
      }
    }

    return \@division_reports;
}

sub fill_and_check_division
{

  my $division_data_arrayref = shift;
  my $tourney_length        = shift;
  my $new_lines_hashref     = shift;

  my @division_data_array    = @{$division_data_arrayref};

  my $start_line = shift @division_data_array;

  my $num_players = scalar @division_data_array;

  my @player_names = ();

  my @division_matrix = ();

  my $num_missing_games = 0;

  for (my $i = 0; $i < $num_players; $i++)
  {
    my @player_data_array = @{$division_data_array[$i]};

    push @player_names, (shift @player_data_array);
    
    for (my $k = 0; $k < $tourney_length; $k++)
    {
      if (@player_data_array)
      {
        push @division_matrix, (shift @player_data_array);
      }
      else
      {
        push @division_matrix, undef;
        $num_missing_games++;
      }
    }
  }


  my $fill_report = "";

  if ($num_missing_games > 0)
  {
    $fill_report .= "$num_missing_games";
  }
   # print division_matrix_to_string(\@player_names, \@division_matrix, $tourney_length);
  # Crunch time

  while($num_missing_games > 0)
  {
    my $min_col = $tourney_length;
    my $min_row = -1;

    row: for (my $row = 0; $row < $num_players; $row++)
    {
      my $num_missing = num_missing_games_in_row(\@division_matrix, $tourney_length, $row);
      if ($num_missing > 0)
      {
        for (my $col = 0; $col < $tourney_length; $col++)
        {
          my $pp = potential_pairing(\@division_matrix, $num_players, $tourney_length, $col, $row);
          if (!$pp && $col < $min_col)
          {
            $min_col = $col;
            $min_row = $row;
          }
        }
      }
    }

    # Insert Bye if available bye is found
    if ($min_col < $tourney_length)
    {
      $fill_report .= insert_bye(\@division_matrix, $num_players, $tourney_length, $min_col, $min_row, [1350, $min_row+1]);
      $num_missing_games--;
      # print division_matrix_to_string(\@player_names, \@division_matrix, $tourney_length, $min_col, $min_row);
      # matrix_is_valid(\@division_matrix, $num_players, $tourney_length, 0, 1);
    }
    else
    {
      $fill_report .= "cannot fill the division, not enough info\n";
    }
  }

  # print division_matrix_to_string(\@player_names, \@division_matrix, $tourney_length);
  my $valid_report = matrix_is_valid(\@division_matrix, $num_players, $tourney_length, 1, 0);
  if (!$valid_report)
  {
    populate_new_lines_hashref(\@division_matrix, \@player_names, $tourney_length, $new_lines_hashref, $start_line);
  }
  return [$fill_report, $valid_report];
}

sub populate_new_lines_hashref
{
  my $matrix_ref = shift;
  my $player_names_ref   = shift;
  my $num_cols   = shift;
  my $hashref    = shift;
  my $start_line = shift;

  my @player_names_array = @{$player_names_ref};
  
  my $num_rows = scalar @player_names_array;
  
  for (my $i = 0; $i < $num_rows; $i++)
  {
    $hashref->{$start_line} = (sprintf "%-30s", (shift @player_names_array)) . " ";
    $hashref->{$start_line} .= matrix_row_to_file_string($matrix_ref, $num_cols, $i);
    $start_line++;
  }
}

sub matrix_row_to_file_string
{
  my $matrix_ref = shift;
  my $num_cols   = shift;
  my $row        = shift;

  my $s = "";

  for (my $i = 0; $i < $num_cols; $i++)
  {
    my $item = $matrix_ref->[$row * $num_cols + $i];
    my $score = $item->[0];
    my $opp   = $item->[1];
    $s .= (sprintf "%4s", $score ) . (sprintf "%4s", $opp) . " ";
  }
  return $s . "\n";
}

sub matrix_is_valid
{
  my $matrix_ref = shift;
  my $num_rows   = shift;
  my $num_cols   = shift;

  my $completion_check = shift;
  my $warn = shift;

  my %column_hash = ();

  my $report_string = "";

  for (my $i = 0; $i < $num_rows; $i++)
  {
    $column_hash{$i+1} = 0;
  }
  
  for (my $i = 0; $i < $num_cols; $i++)
  {
    for (my $k = 0; $k < $num_rows; $k++)
    {
      my $item = $matrix_ref->[$k * $num_cols + $i];
      if ($completion_check && !(defined $item))
      {
        $report_string .= sprintf "   undefined item at (%s, %s)\n", $k, $i;
      }
      if (defined $item && $column_hash{$item->[1]})
      {
        $report_string .= sprintf "   two players play player %s in round %s\n", $item->[1], $i+1;
      }
      if (defined $item)
      {
        $column_hash{$item->[1]} += 1;
      }
    }
    foreach my $key (keys %column_hash)
    {
      if ($completion_check && !$column_hash{$key})
      {
        $report_string .=  sprintf "   missing player number %s in round %s\n", $key, $i+1;
      }
    }
    foreach my $key (keys %column_hash)
    {
      $column_hash{$key} = 0;
    }
  }
  return $report_string;
}

sub insert_bye
{
  my $matrix_ref = shift;
  my $num_rows   = shift;
  my $num_cols   = shift;
  my $col        = shift;
  my $row        = shift;
  my $item       = shift;

  # printf "No possible pairings, inserting a bye\n\nPlayer: %s\nRound: %s\n", $row+1, $col+1;
  for (my $i = $col; $i < $num_cols; $i++)
  {
    my $replaced_value = $matrix_ref->[$row * $num_cols + $i];
    $matrix_ref->[$row * $num_cols + $i] = $item;

    $item = $replaced_value;

    if (!(defined $item))
    {
      last;
    }
    if ($i == $num_cols - 1 && defined $item)
    {
      return sprintf "Bye insert failed at (%s, %s), attempted to erase a valid value\n", $col, $row;
    }
  }
  return "";
}

sub potential_pairing
{
  my $matrix_ref = shift;
  my $num_rows   = shift;
  my $num_cols   = shift;
  my $column     = shift;
  my $row        = shift;

  for (my $i = 0; $i < $num_rows; $i++)
  {
    my $num_missing = num_missing_games_in_row($matrix_ref, $num_cols, $i);
    my $limit = max($column - $num_missing, 0);
    if ($i == $row)
    {
      $limit = $column
    }
    for (my $k = $column; $k >= $limit; $k--)
    {
      my $el = $matrix_ref->[$i * $num_cols + $k];
      if ($el && $el->[1] == $row + 1)
      {
        return $i + 1;
      }
    }
  }
  return 0;
}

sub num_missing_games_in_row
{
  my $matrix_ref = shift;
  my $tourney_length = shift;
  my $row = shift;

  my $sum = 0;
  for (my $i = 0; $i < $tourney_length; $i++)
  {
    if (!(defined $matrix_ref->[$row * $tourney_length + $i]))
    {
      $sum++;;
    }
  }
  return $sum;
}

sub division_matrix_to_string
{
  my $player_names_arrayref = shift;
  my $matrix_ref            = shift;
  my $tourney_length        = shift;

  my $col_to_bold = shift;
  my $row_to_bold = shift;

  my $s = "";

  my $num_names =  scalar @{$player_names_arrayref};

  $s .= sprintf "%-28s", "";
 
  for (my $i = 0; $i < $tourney_length; $i++)
  {
    $s .= sprintf "%4s", $i + 1;
  }
  $s .= "\n\n";
  for (my $i = 0; $i < $num_names; $i++)
  {
    my $trunc_name = substr($player_names_arrayref->[$i], 0, 20);
    $s .= sprintf "%-4s", $i + 1;
    $s .= sprintf "%-24s", $trunc_name; 
    for (my $k = 0; $k < $tourney_length; $k++)
    {
      my $item = $matrix_ref->[$i * $tourney_length + $k];
      if ($item)
      {
        $item = $item->[1];
      }
      else
      {
        $item = -1;
      }
      if (defined $row_to_bold && defined $col_to_bold && $i == $row_to_bold && $k == $col_to_bold)
      {
        $s .= colored( (sprintf "%4s", $item), 'bold green');
      }
      else
      {
        $s .= sprintf "%4s", $item;
      }
    }
    $s .= "\n" 
  }
  return "Number of Players: $num_names\nNumber of Games: $tourney_length\n\n$s\n";
}















