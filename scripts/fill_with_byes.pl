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

  fill_and_check($input_filename, $output_filename);
}

sub fill_and_check
{
    my $input_filename = shift;
    my $output_filename = shift;

    if (!$input_filename || !$output_filename){die "Must specify input and output files";}

    my $line_number = 1;
    my $div_name;
    my @tourney_data_array = ();
    my @file_contents = ();
    my $new_lines_hashref = {};
    my $tourney_length = 0;

    open(INPUT_FILE, "<", $input_filename) or die "Cannot open .tou file $input_filename: $!";
    while(<INPUT_FILE>)
    {
      push @file_contents, $_;
      chomp $_;
      my $at_end = $_ =~ /END OF FILE/;
      if ($_ =~ /^\*(.*)/ || $at_end)
      {
        # Send it if a division ended
        if (@tourney_data_array)
        {
          # print Dumper(\@tourney_data_array);
          fill(\@tourney_data_array, $tourney_length, $new_lines_hashref);
        }
        # Restart it
        if (!$at_end)
        {
          $div_name = $1;
          $div_name =~ s/^\s+|\s+$//g;
          @tourney_data_array = ();
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

          unshift @games, [$score, $opp_number];
        }

        my $player_name = join " ", @player_game_data;
        $player_name =~ s/^\s+|\s+$//g;

        unshift @games, $player_name;

        if (!@tourney_data_array)
        {
          unshift @tourney_data_array, $line_number;
        }

        push @tourney_data_array, \@games;
      }
      $line_number++; 
    }
}

sub fill
{

  my $tourney_data_arrayref = shift;
  my $tourney_length        = shift;
  my $new_lines_hashref     = shift;

  my @tourney_data_array    = @{$tourney_data_arrayref};

  my $start_line = shift @tourney_data_array;

  my $num_players = scalar @tourney_data_array;

  my @player_names = ();

  my @division_matrix = ();

  my $num_missing_games = 0;

  for (my $i = 0; $i < $num_players; $i++)
  {
    my @player_data_array = @{$tourney_data_array[$i]};

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

  print "Missing Games: $num_missing_games\n";

  print division_matrix_to_string(\@player_names, \@division_matrix, $tourney_length);
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

    # Insert Bye is available bye is found
    if ($min_col < $tourney_length)
    {
      insert_bye(\@division_matrix, $num_players, $tourney_length, $min_col, $min_row, [0, $min_row+1]);
      $num_missing_games--;
      print "Missing games: $num_missing_games\n";
      print division_matrix_to_string(\@player_names, \@division_matrix, $tourney_length, $min_col, $min_row);
      matrix_is_valid(\@division_matrix, $num_players, $tourney_length, 0, 1);
    }
    else
    {
      print "Cannot fill, not enough info\n";
      return;
    }
  }

  print division_matrix_to_string(\@player_names, \@division_matrix, $tourney_length);
  matrix_is_valid(\@division_matrix, $num_players, $tourney_length, 1, 0);
}

sub matrix_is_valid
{
  my $matrix_ref = shift;
  my $num_rows   = shift;
  my $num_cols   = shift;

  my $completion_check = shift;
  my $warn = shift;

  my %column_hash = ();

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
        my $error = "Matrix incomplete: undefined item at ($k, $i)\n";
        format_matrix_error($error, $warn);
      }
      if (defined $item && $column_hash{$item->[1]})
      {
        my $error = sprintf "Matrix invalid: two players play player %s in round %s\n", $item->[1], $i+1;
        format_matrix_error($error, $warn);
      }
      if (defined $item)
      {
        $column_hash{$item->[1]} = 1;
      }
    }

    foreach my $key (keys %column_hash)
    {
      if ($completion_check && !$column_hash{$key})
      {
        my $error =  sprintf "Matrix invalid: missing player number %s in round %s\n", $key, $i+1;
        format_matrix_error($error, $warn);
      }
    }
    for (my $i = 0; $i < $num_rows; $i++)
    {
      $column_hash{$i+1} = 0;
    }
  }

}

sub format_matrix_error
{
  my $error = shift;
  my $warn  = shift;
  if ($warn)
  {
    print $error;
  }
  else
  {
    die $error;
  }
}

sub insert_bye
{
  my $matrix_ref = shift;
  my $num_rows   = shift;
  my $num_cols   = shift;
  my $col        = shift;
  my $row        = shift;
  my $item       = shift;

  printf "No possible pairings, inserting a bye\n\nPlayer: %s\nRound: %s\n", $row+1, $col+1;
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
      die "Bye insert failed, attempted to erase a valid value\n";
    }
  }
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















