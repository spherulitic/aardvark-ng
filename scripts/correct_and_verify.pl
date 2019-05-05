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

  my $reports_string = parse_reports(correct_and_verify_tournament($input_filename, $output_filename), $input_filename, $output_filename);
  print $reports_string;
}

sub parse_reports
{
  my $reports_ref     = shift;
  my $input_filename  = shift;
  my $output_filename = shift;


  my $stmt = "";

  my @reports_array = @{$reports_ref};

  my $pad = 30;

  my $rewrite = 0;

  for (my $i = 0; $i < scalar @reports_array; $i++)
  {
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
          $stmt .= (sprintf "%-" . $pad  ."s", "WARNING:") . "possibly attempted to correct invalid file\n";
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
          my $div_report = correct_and_verify_division(\@division_data_array, $tourney_length, $new_lines_hashref);
          $file_has_changed = $file_has_changed || $div_report->[0];
          unshift @{$div_report}, $div_name;
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
  my $tourney_length        = shift;
  my $new_lines_hashref     = shift;

  my @division_data_array    = @{$division_data_arrayref};

  my $start_line = shift @division_data_array;

  my $num_players = scalar @division_data_array;

  my ($division_matrix_ref, $player_names_ref, $num_missing_games) = @{create_division_matrix($division_data_arrayref, $tourney_length)};

  my $bye_report = "";

  if ($num_missing_games > 0)
  {
    $bye_report = fill_division_with_byes($division_matrix_ref, $num_players, $tourney_length, $num_missing_games);
  }

  my $valid_report      = validate_division($division_matrix_ref, $num_players, $tourney_length);

  my $correction_report = "";

  my $correction_needed = 0;

  if ($valid_report)
  {
    $correction_needed = 1;
    $correction_report = correct_division_pairings($division_matrix_ref, $num_players, $tourney_length, $player_names_ref);
  }
  
  $valid_report      = validate_division($division_matrix_ref, $num_players, $tourney_length);
  
  my $pop_report = "";

  my $rewrite_needed = ($num_missing_games || $correction_needed) && !$valid_report;

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
  # Crunch time

  my $division_matrix_ref = shift;
  my $num_players         = shift;
  my $tourney_length      = shift;
  my $num_missing_games   = shift;

  my $byes_to_add = $num_missing_games;

  my $bye_report = "";

  while($num_missing_games > 0)
  {
    my $min_col = $tourney_length;
    my $min_row = -1;
    row: for (my $row = 0; $row < $num_players; $row++)
    {
      my $num_missing = num_missing_games_in_row($division_matrix_ref, $tourney_length, $row);
      if ($num_missing > 0)
      {
        for (my $col = 0; $col < $tourney_length; $col++)
        {
          my $pp = potential_pairing($division_matrix_ref, $num_players, $tourney_length, $col, $row);
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

sub correct_division_pairings
{
  my $matrix_ref = shift;
  my $num_rows   = shift;
  my $num_cols   = shift;
  my $player_names_ref = shift;

  my $corrections     = "";
  my $num_corrections = 0;

  for (my $i = 0; $i < $num_cols; $i++)
  {
    my @badpairings = find_bad_pairings($matrix_ref, $num_rows, $num_cols, $i);
    # Corrections go here probably
    # print division_matrix_to_string($player_names_ref, $matrix_ref, $num_cols);
    # First correct bad pairings
    while(1)
    {
      @badpairings = find_bad_pairings($matrix_ref, $num_rows, $num_cols, $i);
      my $old_num_badpairings = scalar @badpairings;
      while(@badpairings)
      {
        # print "The bad pairings:\n";
        # print Dumper(\@badpairings);
        my $ip = shift @badpairings;
        my $old_pairing =  $matrix_ref->[($ip-1) * $num_cols + $i]->[1];
        my $pairing_found = 0;
  
        my @missing = find_missing($matrix_ref, $num_rows, $num_cols, $i);
  
        # print "The missing:\n";
        # print Dumper(\@missing);
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
      @badpairings = find_bad_pairings($matrix_ref, $num_rows, $num_cols, $i);
      my $new_num_badpairings = scalar @badpairings;
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
      # print "The bad pairings for the byes:\n";
      # print Dumper(\@badpairings);
      my $ip = shift @badpairings;
      my $old_pairing =  $matrix_ref->[($ip-1) * $num_cols + $i]->[1];

      # If no opp plays this player, assume they have a bye
      # print "Giving $ip a bye in round " . ($i+1) . "\n";
      $matrix_ref->[($ip - 1) * $num_cols + $i]->[1] = $ip;
      $matrix_ref->[($ip - 1) * $num_cols + $i]->[0] = Constants::DEFAULT_BYE_SCORE;

      my $cor.= sprintf "   Round %3s: [%3s, %3s] -> [%3s, %3s] (bye, no valid opponent)\n", $i+1, $ip, $old_pairing, $ip, $ip;
      $corrections .= $cor;
      # print $cor;
      # print division_matrix_to_string($player_names_ref, $matrix_ref, $num_cols, $i, $ip);
      $num_corrections++;
      # $correct_string .= sprintf "   unable to find an opponent for player %s in round %s\n", $ip, $i+1;
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

  # Create missing array
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
      if (defined $item)
      {
        if ($column_hash{$item->[1]})
        {
          $report_string .= sprintf "   more than one player plays player %s in round %s\n", $item->[1], $i+1;
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
          $report_string .= sprintf "   opponent of opponent is not player (player, opp, opp of opp) = (%s, %s, %s) in round %s\n", $k+1, $opp, $opp_opp, $i+1;
        }
      }
    }
    foreach my $key (keys %column_hash)
    {
      if ($completion_check && !$column_hash{$key})
      {
        $report_string .=  sprintf "   missing player number             %s in round %s\n", $key, $i+1;
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

  # printf "No possible pairings, inserting a bye\n\nPlayer: %s\nRound: %s\n", $row+1, $col+1;
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















