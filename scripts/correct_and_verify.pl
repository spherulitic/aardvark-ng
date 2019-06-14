#!/usr/bin/perl

# This script validates .tou files and corrects and rewrites them if possible

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

  my $reports_string = parse_reports(correct_and_verify_tournament($input_filename, $output_filename), $input_filename, $output_filename);
  print $reports_string;
}

sub parse_reports
{

  # A report is returned from the correct_and_verify_tournament subroutine
  # This subroutine is basically a toString method for the report

  my $reports_ref     = shift;
  my $input_filename  = shift;
  my $output_filename = shift;


  my $stmt = "";

  my @reports_array = @{$reports_ref};

  my $pad = 30;

  my $rewrite = 0;

  for (my $i = 0; $i < scalar @reports_array; $i++)
  {
    # The reports_array contains a report for each division in the .tou file
    # If no errors were found the content of the report will be the empty
    # string
    my $warning_string = '';
    my @div_report = @{$reports_array[$i]};
    my $div_name = shift @div_report;
    my $was_rewritten = shift @div_report;
    $rewrite  = $rewrite || $was_rewritten;
    my $div_added = 0;
    for (my $k = 0; $k < scalar @div_report; $k++)
    {
      my $title   = $div_report[$k]->[0];
      my $content = $div_report[$k]->[1];

      if ($content)
      {
        if (!$stmt)
        {
          $stmt .= (sprintf "%-" . $pad  ."s", "WARNING:") .
                   "possibly attempted to correct invalid file\n";

          $stmt .= (sprintf "%-" . $pad  ."s", "File:") . "$input_filename\n";
        }
        if (!$div_added)
        {
          $stmt .= (sprintf "%-" . $pad . "s", "Division:") . $div_name ."\n";
          $div_added = 1;
        }
        $stmt .= (sprintf "%-" . $pad . "s", $title) . $content . "\n";
      }
    }
  }
  if ($stmt)
  {
    my $rewrite_status = "Not rewritten";
    if ($rewrite)
    {
      $rewrite_status = $output_filename
    }
    $stmt .= (sprintf "%-" . $pad . "s", "File Rewrite Location:") . $rewrite_status . "\n";
  }
  return $stmt;
}

sub correct_and_verify_tournament
{

    # This subroutine attempts to correct and verify the input .tou specified
    # by $input_filename. If at least one correction is made, a new .tou file
    # is written to $output_filename

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

    my $file_has_changed = 0;
    my $format_correction = 0;

    open(INPUT_FILE, "<", $input_filename)
      or die "Cannot open .tou file $input_filename: $!";

    while(<INPUT_FILE>)
    {
      $file_contents{$line_number} = $_;
      chomp $_;
      my $at_end = $_ =~ /END OF FILE/;
      if ($_ =~ /^\*(.*)/ || $at_end)
      {
        # If this is the end of the division, verify the division
        if (@division_data_array)
        {
          my $div_report = correct_and_verify_division(\@division_data_array, $tourney_length, $new_lines_hashref, $format_correction);
          $file_has_changed = $file_has_changed || $div_report->[0];
          unshift @{$div_report}, $div_name;
          push @division_reports, $div_report;
        }
        # Prepare loop for a new division
        if (!$at_end)
        {
          $div_name = $1;
          $div_name =~ s/^\s+|\s+$//g;
          @division_data_array = ();
          $tourney_length = 0;
          $format_correction = 0;
        }
      }
      elsif ($_ =~ /\w\s+(\d+\s+\+?\d+(\s+|$))+/)
      {

        # If a winning negative score is listed, correct it by adding 2000
        # to ensure compliance with the .tou format
        if ($_ =~ /2\s?(\-\d+)/)
        {    
        format_error([
                       ["WARNING:      ", "converting negative winning score"],
                       ["File:         ", $input_filename],
                       ["Line:         ", $_."\n"],
                       ["Rewritten to: ", $output_filename]
                     ]);
          my $neg_score = $1 + 2000;
          $_ =~ s/2\s?\-\d+/$neg_score/g;
          $format_correction = 1;
        }

        my @player_game_data = split/\s+/, $_;
    
        my @games = ();

        my $games_played = () = $_ =~ /(\d+\s+\+?\d+(?:\s+|$))/g;

        $tourney_length = max($games_played, $tourney_length);

        for(my $i = 0; $i < $games_played; $i++)
        {
          my $opp_number  = pop @player_game_data;
          my $score       = pop @player_game_data;

          my $first_string = '';
       
          if ($opp_number =~ /\+/)
          {
            $first_string = '+';
          }

          $opp_number =~ s/\D//g;
          $score      =~ s/\D//g;

          unshift @games, [$score, $opp_number, $first_string];
        }

        my $player_name = join " ", @player_game_data;
        $player_name =~ s/^\s+|\s+$//g;

        unshift @games, $player_name;

        # If this is the first division listed in this .tou file, prepend the
        # current line number of the file to the division data. The line
        # number will be needed if a correction is made and the file needs
        # to be rewritten

        if (!@division_data_array)
        {
          unshift @division_data_array, $line_number;
        }
        
        push @division_data_array, \@games;
      }
      $line_number++; 
    }

    # If the file has changed, rewrite it using the new_lines_hashref
    if ($file_has_changed)
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

    return \@division_reports;
}

sub correct_and_verify_division
{
  my $division_data_arrayref = shift;
  my $tourney_length         = shift;
  my $new_lines_hashref      = shift;
  my $format_correction      = shift;

  my @division_data_array    = @{$division_data_arrayref};

  my $start_line = shift @division_data_array;

  my $num_players = scalar @division_data_array;

  # Create a matrix representation of the division. With the matrix
  # abstraction the division becomes easier to verify, correct, and
  # rewrite.

  my ($division_matrix_ref, $player_names_ref, $num_missing_games) = @{create_division_matrix($division_data_arrayref, $tourney_length)};

  my $bye_report = "";

  # If players are missing games, the matrix will be jagged.
  # Before verification, the matrix must be square, so byes are put in place
  # of missing games.

  if ($num_missing_games > 0)
  {
    $bye_report = fill_division_with_byes($division_matrix_ref, $num_players, $tourney_length, $num_missing_games);
  }

  # If the division matrix is valid, the validate_division subroutine will
  # return the empty string. If not, the subroutine will return the errors
  # it found.

  my $valid_report      = validate_division($division_matrix_ref, $num_players, $tourney_length);

  my $correction_report = "";

  my $correction_needed = 0;

  # If the $valid_report is not the empty string, errors were found, so the
  # correct_division_pairings subroutine is called to attempt to correct the
  # errors.

  if ($valid_report)
  {
    $correction_needed = 1;
    $correction_report = correct_division_pairings($division_matrix_ref, $num_players, $tourney_length, $player_names_ref);
  }
  
  # After correction, revalidate, as the correction may have failed or further
  # corrupted the division data.

  $valid_report      = validate_division($division_matrix_ref, $num_players, $tourney_length);
  
  my $pop_report = "";

  my $rewrite_needed = ($num_missing_games || $correction_needed) && !$valid_report || $format_correction;

  # If a rewrite is needed, populate the $new_lines_hashref which will be used
  # to rewrite the .tou file.

  if ($rewrite_needed)
  {
    populate_new_lines_hashref($division_matrix_ref, $player_names_ref, $tourney_length, $new_lines_hashref, $start_line);
  }

  return [$rewrite_needed, ["Missing games status:", $bye_report], ["Correction status:", $correction_report],["Errors:", $valid_report]];
}

sub create_division_matrix
{
  my $division_data_arrayref = shift;
  my $tourney_length        = shift;

  my @division_data_array    = @{$division_data_arrayref};

  my $start_line = shift @division_data_array;

  my $num_players = scalar @division_data_array;

  my @player_names = ();

  my @division_matrix = ();

  my $num_missing_games = 0;

  # The division matrix is a 1-d array modeling a 2-d array.
  # To get the element [a, b], use division_matrix[(tourney_length * a) + b]

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
  return [\@division_matrix, \@player_names, $num_missing_games];
}


sub fill_division_with_byes
{
  # This subroutine replaces missing games with byes

  my $division_matrix_ref = shift;
  my $num_players         = shift;
  my $tourney_length      = shift;
  my $num_missing_games   = shift;

  my $byes_to_add = $num_missing_games;

  my $bye_report = "";

  while($num_missing_games > 0)
  {
    # In this loop, find the earliest missing game that must be a bye
    # If arbitrary missing games are replaced with byes, valid pairing
    # data could be lost.

    my $min_col = $tourney_length;
    my $min_row = -1;
    row: for (my $row = 0; $row < $num_players; $row++)
    {
      my $num_missing = num_missing_games_in_row($division_matrix_ref,
                                                 $tourney_length, $row);
      if ($num_missing > 0)
      {
        for (my $col = 0; $col < $tourney_length; $col++)
        {
          # Here we are iterating over every missing game.
          # If a player was a missing game in a round where
          # they could be potentially playing someone else,
          # a bye should not be added. 
          my $pp = potential_pairing($division_matrix_ref, $num_players,
                                     $tourney_length, $col, $row);

          # If there is no potential pairing and the bye is before
          # the current minimum round bye, update the minimum round bye
          # with this bye.

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
      $bye_report .= insert_bye($division_matrix_ref, $num_players, $tourney_length, $min_col, $min_row, [Constants::DEFAULT_BYE_SCORE, $min_row+1]);
      $num_missing_games--;
    }
    else
    {
      $bye_report .= "cannot fill the division, not enough info\n";
      last;
    }
  }

  $bye_report =  "added $byes_to_add byes\n\n" . $bye_report;

  return $bye_report;
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
    # Create a new line for the .tou
    # First the player name is listed, followed by the game data
    # as per the .tou format

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
    # The item is [score, opponent number, '+' is player went first else '']
    my $item = $matrix_ref->[$row * $num_cols + $i];
    my $score = $item->[0];
    my $opp   = $item->[2] . $item->[1];
    $s .= (sprintf "%6s", $score ) . (sprintf "%6s", $opp) . " ";
  }
  return $s . "\n";
}

sub correct_division_pairings
{

  # Attempt to correct an invalid division matrix

  my $matrix_ref = shift;
  my $num_rows   = shift;
  my $num_cols   = shift;
  my $player_names_ref = shift;

  my $corrections     = "";
  my $num_corrections = 0;

  # Start correcting from round 1 to the last round

  for (my $i = 0; $i < $num_cols; $i++)
  {
    # Get the invalid pairings for this round
    my @badpairings = find_bad_pairings($matrix_ref, $num_rows, $num_cols, $i);
    while(1)
    {
      @badpairings = find_bad_pairings($matrix_ref, $num_rows, $num_cols, $i);
      my $old_num_badpairings = scalar @badpairings;
      while(@badpairings)
      {
        # Here, $ip is the 1-indexed player number which is invalidly paired.
        # We have to use $ip-1 because the division matrix is 0-indexed while
        # the .tou file is 1-indexed.

        my $ip = shift @badpairings;
        my $old_pairing =  $matrix_ref->[($ip-1) * $num_cols + $i]->[1];
        my $pairing_found = 0;
  
        my @missing = find_missing($matrix_ref, $num_rows, $num_cols, $i);
  
        # Iterate through all of the players whose numbers do not appear.
        # These players are listed in the @missing array. If a missing
        # player has $ip as an opponent. Unpair $ip with the old bad
        # pairing and pair them with the player who is missing from the
        # division.

        while(@missing)
        {
          my $m = shift @missing;
          my $missing_opp = $matrix_ref->[($m-1) * $num_cols + $i]->[1];
          if ($missing_opp && $missing_opp == $ip)
          {
            $matrix_ref->[($ip-1) * $num_cols + $i]->[1] = $m;
            my $cor = sprintf "   Round %3s: [%3s, %3s] -> [%3s, %3s] (pairing)\n", $i+1, $ip, $old_pairing, $ip, $m;
            $corrections .= $cor;
            # print $cor;
            # print "Pairing $ip with $m in round " . ($i+1) . "\n";
            # print division_matrix_to_string($player_names_ref, $matrix_ref, $num_cols, $i, $ip);
            $num_corrections++;
            $pairing_found = 1;
          }
        }
      }
      # Update the invalid pairings array
      @badpairings = find_bad_pairings($matrix_ref, $num_rows, $num_cols, $i);
      my $new_num_badpairings = scalar @badpairings;
      
      # If the number of invalid pairings pairings did not change after the
      # attempted corrections, abort this phase of the corrections
      # as there is not enough information to correct in this phase.
      if ($old_num_badpairings == $new_num_badpairings)
      {
        last;
      }
    }

    # Assume players playing nonexistent players get byes
    for (my $k = 0; $k < $num_rows; $k++)
    {
      my $item = $matrix_ref->[$k * $num_cols + $i];
      if (defined $item)
      {
        my $opp = $item->[1];
        if ($opp < 0 || $opp > $num_rows)
        {
          # If a player is paired with a non existent player number assume a bye
          $corrections .= sprintf "   Round %3s: [%3s, %3s] -> [%3s, %3s] (bye, invalid player number)\n", $i+1, $k+1, $opp, $k+1, $k+1;
          $item->[1] = $k+1;
          $item->[0] = Constants::DEFAULT_BYE_SCORE;
          $opp       = $k+1;
          $num_corrections++;
        }
      }
    }
    # If pairings can't be found assume byes
    @badpairings = find_bad_pairings($matrix_ref, $num_rows, $num_cols, $i);
    while(@badpairings)
    {
      my $ip = shift @badpairings;
      my $old_pairing =  $matrix_ref->[($ip-1) * $num_cols + $i]->[1];

      # If no opp plays this player, assume they have a bye
      $matrix_ref->[($ip - 1) * $num_cols + $i]->[1] = $ip;
      $matrix_ref->[($ip - 1) * $num_cols + $i]->[0] = Constants::DEFAULT_BYE_SCORE;

      my $cor.= sprintf "   Round %3s: [%3s, %3s] -> [%3s, %3s] (bye, no valid opponent)\n", $i+1, $ip, $old_pairing, $ip, $ip;
      $corrections .= $cor;
      $num_corrections++;
    }
  }
  if ($num_corrections)
  {
    return "made $num_corrections corrections\n\n" . $corrections;
  }
  return "";
}

sub find_missing
{
  my $matrix_ref = shift;
  my $num_rows   = shift;
  my $num_cols   = shift;
  my $i          = shift;

  # This subroutine returns an array of players whose player numbers do not
  # appear in the column for round $i + 1

  my %missing_hash = ();
  for (my $b = 0; $b < $num_rows; $b++)
  {
    $missing_hash{$b+1} = 1;
  }
  for (my $b = 0; $b < $num_rows; $b++)
  {
    my $opp = $matrix_ref->[$b * $num_cols + $i]->[1];
    if ($missing_hash{$opp})
    {
      delete $missing_hash{$opp};
    }
  }
  my @a = keys %missing_hash;
  return @a;
}

sub find_bad_pairings
{
  my $matrix_ref = shift;
  my $num_rows   = shift;
  my $num_cols   = shift;
  my $i          = shift;

  # This subroutine returns an array of invalid pairings for round $i + 1.
  # A pairing is invalid if the opponent of the opponent of the player is
  # not the player themself.

  my @badpairings = ();
  for (my $k = 0; $k < $num_rows; $k++)
  {
    my $item = $matrix_ref->[$k * $num_cols + $i];
    if (defined $item)
    {
      my $opp = $item->[1];
      my $opp_opp = $matrix_ref->[($opp-1) * $num_cols + $i]->[1];
      if (!$opp_opp || $opp_opp != $k + 1)
      {
        push @badpairings, $k+1;
      }
   }
  }
  return @badpairings;
}

sub validate_division
{

  # This subroutine validates a division matrix by ensuring the following:
  #   - There is data for every player in every round
  #   - For every round, every player number appear exactly once
  #   - The opponent of the opponent of the player is the player themself

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
        # Check that each matrix entry has data.
        $report_string .= sprintf "   undefined item at (%s, %s)\n", $k, $i;
      }
      if (defined $item)
      {
        if ($column_hash{$item->[1]})
        {
          # Check that a player isn't paired against more than one person.
          $report_string .= 
            sprintf "   more than one player plays player %s in round %s\n",
                    $item->[1], $i+1;
        }
        $column_hash{$item->[1]} += 1;
        my $opp = $item->[1];
        my $opp_opp = $matrix_ref->[($opp-1) * $num_cols + $i]->[1];
        if (!$opp_opp || $opp_opp != $k + 1)
        {
          if (!$opp_opp)
          {
            $opp_opp = "undef";
          }
          # Check that the opponent of the opponent of the player is the
          # player.
          $report_string .=
            sprintf "   opponent of opponent is not player
                        (player, opp, opp of opp) = (%s, %s, %s)
                        in round %s\n", $k+1, $opp, $opp_opp, $i+1;
        }
      }
    }
    foreach my $key (keys %column_hash)
    {
      if ($completion_check && !$column_hash{$key})
      {
        # Check that the player is paired against someone as opposed to no one.
        $report_string .=
          sprintf "   missing player number             %s in round %s\n",
                  $key, $i+1;
      }
    }
    foreach my $key (keys %column_hash)
    {
      $column_hash{$key} = 0;
    }
  }
  if ($report_string)
  {
    $report_string = "\n" . $report_string;
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

  # Insert a bye in the division matrix at column $col and row $row.
  # Shift the succeeding (by round) player data by one round.
  for (my $i = $col; $i < $num_cols; $i++)
  {
    my $replaced_value = $matrix_ref->[$row * $num_cols + $i];
    $matrix_ref->[$row * $num_cols + $i] = $item;

    $item = $replaced_value;

    if ($i == $num_cols - 1 && defined $item)
    {
      return sprintf "Bye insert failed at (%s, %s), attempted to erase a valid value\n", $col, $row;
    }
    
    if (!(defined $item))
    {
      last;
    }
  }
  return sprintf "   Round %3s:            -> [%3s, %3s] (bye)\n", $col+1, $row+1, $row+1;
}

sub potential_pairing
{
  my $matrix_ref = shift;
  my $num_rows   = shift;
  my $num_cols   = shift;
  my $column     = shift;
  my $row        = shift;

  # Find a potential pairing for the player in row $row and the round
  # corresponding to column $col. Depending on how many missing
  # games each player has, the potential game data that makes the
  # valid pairing could be separated by more than one column.

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
      $sum++;
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

1;











