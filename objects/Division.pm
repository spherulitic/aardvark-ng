#!/usr/bin/perl

package Division;

use strict;
use warnings;
use Data::Dumper;

use lib './modules';
use Constants;

sub new
{
  my $this = shift;

  my $toufile         = shift;
  my $division_name   = shift;
  my $division_number = shift;
  my $players         = shift;
  my $game_data       = shift;

  my $division = $this->initialize(
                                    $toufile,
                                    $division_name,
                                    $division_number,
                                    $players,
                                    $game_data
                                  );

  $division->create_matrix();
  return $division;
}

sub set_valid
{
  my $this        = shift;
  my $valid_value = shift;
  $this->{Constants::DIVISION_VALID} = $valid_value;
}

sub to_string
{
  my $this = shift;

  my $number_of_rounds  = $this->{Constants::DIVISION_NUMBER_OF_ROUNDS};
  my @players           = @{$this->{Constants::DIVISION_PLAYERS}};
  my $number_of_players = scalar @players;

  my $division_name = $this->{Constants::DIVISION_NAME};

  my $division_string = "*$division_name\n";
  $division_string .= "                                      0\n";

  for (my $player_number = 0; $player_number < $number_of_players; $player_number++)
  {
    my $player_name = $this->{Constants::DIVISION_PLAYERS}->[$player_number];
    $division_string .= sprintf "%-30s", $player_name; 
    for (my $round = 0; $round < $number_of_rounds; $round++)
    {
      my $player_result    = $this->get_matrix_index($player_number, $round);
      my $opponent_number  = $player_result->{Constants::RESULT_OPPONENT_NUMBER};
      my $player_tou_score = $player_result->{Constants::RESULT_TOU_SCORE};
      my $player_is_first  = $player_result->{Constants::RESULT_PLAYER_IS_FIRST};
      my $plus = '';
      if ($player_is_first)
      {
        $plus = '+';
      }
      $division_string .= (sprintf "%6s", $player_tou_score) .
                          (sprintf "%5s", $plus . $opponent_number) . " ";
    }
    $division_string .= "\n";
  }
  return $division_string;
}

sub is_valid
{
  my $this = shift;
  return $this->{Constants::DIVISION_VALID};
}

sub set_verification_report
{
  my $this = shift;
  my $report = shift;
  $this->{Constants::DIVISION_VERIFICATION_REPORT} = $report;
}

sub set_not_valid
{
  my $this = shift;
  my $is_valid = shift;
  $this->{Constants::DIVISION_VALID} = $is_valid;
}

sub create_matrix
{
  my $this = shift;

  # The division matrix is a 1-d array modeled
  # as a 2-d array
  my $tournament_length;
  my $game_data = $this->{Constants::DIVISION_GAME_DATA};
  my @matrix = ();

  for (my $i = 0; $i < scalar @{$game_data}; $i++)
  {
    my @player_games = @{$game_data->[$i]};
    my $number_of_player_games = scalar @player_games;
    if (!$tournament_length)
    {
      $tournament_length = $number_of_player_games;
    }
    elsif ($number_of_player_games != $tournament_length)
    {
      $this->set_verification_report(
        Utils::format_error([
                              ['ERROR', 'Inconsistent number of games played'],
                              ['File', $this->{Constants::DIVISION_TOUFILE}],
                              ['Division', $this->{Constants::DIVISION_NAME}],
                              ['Player', $this->{Constants::DIVISION_PLAYERS}->[$i]]
                            ]));
      $this->set_not_valid();
      return;
    }
    for (my $k = 0; $k < $number_of_player_games; $k++)
    {
      $player_games[$k]->{Constants::RESULT_ROUND} = $k + 1;
      push @matrix, $player_games[$k];
    }
  }
  $this->{Constants::DIVISION_NUMBER_OF_ROUNDS} = $tournament_length;
  $this->{Constants::DIVISION_MATRIX} = \@matrix;
}

sub initialize
{
  my $this = shift;

  my $toufile         = shift;
  my $division_name   = shift;
  my $division_number = shift;
  my $players         = shift;
  my $game_data       = shift;

  my $division = {};

  $division->{Constants::DIVISION_TOUFILE}    = $toufile;
  $division->{Constants::DIVISION_NAME}       = $division_name;
  $division->{Constants::DIVISION_NUMBER}     = $division_number;
  $division->{Constants::DIVISION_PLAYERS}    = $players;
  $division->{Constants::DIVISION_GAME_DATA}  = $game_data;
  $division->{Constants::DIVISION_VALID}      = 1;
  $division->{Constants::DIVISION_MATRIX}     = [];

  my $self = bless $division, $this;
  return $self;
}

sub get_matrix_index
{
  my $this          = shift;
  my $player_number = shift;
  my $round         = shift;

  my $matrix = $this->{Constants::DIVISION_MATRIX};
  my $number_of_rounds = $this->{Constants::DIVISION_NUMBER_OF_ROUNDS};

  return $matrix->[ ($player_number *  $number_of_rounds) + $round ];
}

sub process
{
  my $this    = shift;
  my $correct = shift;

  my $filename      = $this->{Constants::DIVISION_TOUFILE};
  my $division_name = $this->{Constants::DIVISION_NAME};

  my $number_of_rounds  = $this->{Constants::DIVISION_NUMBER_OF_ROUNDS};
  my @players           = @{$this->{Constants::DIVISION_PLAYERS}};
  my $number_of_players = scalar @players;

  # At this point the matrix is guaranteed to be
  # rectangular with dimensions (number of players x number of games)
  # due to the checks in create_matrix

  for (my $round = 0; $round < $number_of_rounds; $round++)
  {
    # The outer loop iterates through each round while the
    # inner loop iterates through each player. For each
    # round we verify that each player is paired exactly
    # once and that the opponent of the opponent is the player
    for (my $player_number = 0; $player_number < $number_of_players; $player_number++)
    {
      my $player_result   = $this->get_matrix_index($player_number, $round);
      my $player_name     = $this->{Constants::DIVISION_PLAYERS}->[$player_number];
      my $opponent_number = $player_result->{Constants::RESULT_OPPONENT_NUMBER};

      $player_result->{Constants::RESULT_ROUND}         = $round;
      $player_result->{Constants::RESULT_PLAYER_NUMBER} = $player_number;

      if (! defined $player_result->{Constants::RESULT_SCORE})
      {
        my $message_type = 'ERROR';
        my $message      = 'Undefined score';
        if ($correct)
        {
          $message_type = 'WARNING';
          $message      = 'Undefined score set to zero';
          $player_result->{Constants::RESULT_SCORE} = 0;
        }
        $this->set_verification_report(
          Utils::format_error([
                                [$message_type, $message],
                                ['File', $filename],
                                ['Division', $division_name],
                                ['Round', $round + 1],
                                ['Player', $player_name],
                              ]));
        if (!$correct)
        {
          $this->set_valid(!$correct);
          return;
        }
      }

      if (! defined $opponent_number)
      {
        my $message_type = 'ERROR';
        my $message      = 'Undefined opponent';
        if ($correct)
        {
          $message_type = 'WARNING';
          $message      = 'Undefined opponent set to bye';
          $player_result->{Constants::RESULT_OPPONENT_NUMBER} = $player_number;
        }
        $this->set_verification_report(
          Utils::format_error([
                                [$message_type, $message],
                                ['File', $filename],
                                ['Division', $division_name],
                                ['Round', $round + 1 ],
                                ['Player', $player_name],
                              ]));
        if (!$correct)
        {
          $this->set_valid(!$correct);
          return;
        }
      }

      if ($opponent_number < 0 || $opponent_number > $number_of_players - 1)
      {
        my $message_type = 'ERROR';
        my $message      = 'Out of range opponent number';
        if ($correct)
        {
          $message_type = 'WARNING';
          $message      = 'Out of range opponent number set to bye';
          $player_result->{Constants::RESULT_OPPONENT_NUMBER} = $player_number;
        }
        $this->set_verification_report(
          Utils::format_error([
                                [$message_type, $message],
                                ['File', $filename],
                                ['Division', $division_name],
                                ['Round', $round + 1],
                                ['Player', $player_name],
                              ]));
        if (!$correct)
        {
          $this->set_valid(!$correct);
          return;
        }
      }

      my $opponent_result = $this->get_matrix_index($opponent_number, $round);
      my $opponent_opponent_number = $opponent_result->{Constants::RESULT_OPPONENT_NUMBER};
      if ($opponent_opponent_number != $player_number)
      {
        my $message_type = 'ERROR';
        my $message      = 'The opponent of the player\'s opponent is not the player';
        if ($correct)
        {
          $message_type = 'WARNING';
          $message     .= ' and was set to a bye';
          $player_result->{Constants::RESULT_OPPONENT_NUMBER} = $player_number;
        }

        $this->set_verification_report(
          Utils::format_error([
                                [$message_type, $message],
                                ['File', $filename],
                                ['Division', $division_name],
                                ['Round', $round + 1 ],
                                ['Player', $player_name],
                                ['Player\'s Opponent', $this->{Constants::DIVISION_PLAYERS}->[$opponent_number] ],
                                ['Player\'s Opponent\'s Opponent', $this->{Constants::DIVISION_PLAYERS}->[$opponent_opponent_number] ]
                              ]));
        if (!$correct)
        {
          $this->set_valid(!$correct);
          return;
        }
      }

      my $player_score   = $player_result->get_score();
      my $opponent_score = $opponent_result->get_score();
      my $spread = $player_score - $opponent_score;
      my $wins     = 0;
      my $losses   = 0;
      my $bye_wins = 0;
      my $byes     = 0;
      my $coded_result;
      if ($opponent_number == $player_number)
      {
        $byes = 1;
        my $tou_score = $player_result->get_tou_score();
        if ($tou_score > 2000)
        {
          $bye_wins = 1;
          $coded_result = 1;
        }
        elsif ($tou_score == 1350)
        {
          $bye_wins = 0.5;
          $coded_result = 0;
        }
        $player_result->{Constants::RESULT_SCORE} = 0;
      }
      else
      {
        if ($spread > 0)
        {
          $wins = 1;
          $coded_result = 1;
        }
        elsif ($spread == 0)
        {
          $wins   = 0.5;
          $losses = 0.5;
          $coded_result = 0;
        }
        else
        {
          $losses = 1;
          $coded_result = -1;
        }
      }
      $player_result->{Constants::RESULT_WINS}          = $wins;
      $player_result->{Constants::RESULT_LOSSES}        = $losses;
      $player_result->{Constants::RESULT_BYES}          = $byes;
      $player_result->{Constants::RESULT_BYE_WINS}      = $bye_wins;
      $player_result->{Constants::RESULT_SPREAD}        = $spread;
      $player_result->{Constants::RESULT_CODED}         = $coded_result;
    }
  }  
}

1;
