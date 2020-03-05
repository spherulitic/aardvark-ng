#!/usr/bin/perl

package Division;

use strict;
use warnings;
use version; our $VERSION = qv('1');
use Data::Dumper;

use lib './modules';
use Constants;

sub create_matrix
{
  my $this = shift;

  # The division matrix is a 1-d array modeled
  # as a 2-d array
  my $tournament_length;
  my $game_data = $this->{$DIVISION_GAME_DATA};
  my @matrix    = ();

  for my $i ( 0 .. scalar @{$game_data} - 1 )
  {
    my @player_games           = @{ $game_data->[$i] };
    my $number_of_player_games = scalar @player_games;
    if ( !$tournament_length )
    {
      $tournament_length = $number_of_player_games;
    }
    elsif ( $number_of_player_games != $tournament_length )
    {
      # Covered by TC 12
      $this->set_verification_report(
        Utils::format_error(
          [ [ 'ERROR',    'Inconsistent number of games played' ],
            [ 'File',     $this->{$DIVISION_TOUFILE} ],
            [ 'Division', $this->{$DIVISION_NAME} ],
            [ 'Player',   $this->{$DIVISION_PLAYERS}->[$i] ]
          ]
        )
      );
      $this->set_valid(0);
      return;
    }
    for my $k ( 0 .. $number_of_player_games - 1 )
    {
      $player_games[$k]->{$RESULT_ROUND} = $k + 1;
      push @matrix, $player_games[$k];
    }
  }
  $this->{$DIVISION_NUMBER_OF_ROUNDS} = $tournament_length;
  $this->{$DIVISION_MATRIX}           = \@matrix;

  return 1;
}

sub get_matrix_index
{
  my $this          = shift;
  my $player_number = shift;
  my $round         = shift;

  my $matrix           = $this->{$DIVISION_MATRIX};
  my $number_of_rounds = $this->{$DIVISION_NUMBER_OF_ROUNDS};

  return $matrix->[ ( $player_number * $number_of_rounds ) + $round ];
}

sub initialize
{
  my ( $this, $arg_ref ) = @_;

  my $filename        = $arg_ref->{filename};
  my $division_name   = $arg_ref->{division_name};
  my $division_number = $arg_ref->{division_number};
  my $players         = $arg_ref->{players};
  my $game_data       = $arg_ref->{game_data};

  my $division = {};

  $division->{$DIVISION_TOUFILE}   = $filename;
  $division->{$DIVISION_NAME}      = $division_name;
  $division->{$DIVISION_NUMBER}    = $division_number;
  $division->{$DIVISION_PLAYERS}   = $players;
  $division->{$DIVISION_GAME_DATA} = $game_data;
  $division->{$DIVISION_VALID}     = 1;
  $division->{$DIVISION_MATRIX}    = [];

  my $self = bless $division, $this;
  return $self;
}

sub is_valid
{
  my $this = shift;
  return $this->{$DIVISION_VALID};
}

sub new
{
  my ( $this, $arg_ref ) = @_;

  my $filename        = $arg_ref->{filename};
  my $division_name   = $arg_ref->{division_name};
  my $division_number = $arg_ref->{division_number};
  my $players         = $arg_ref->{players};
  my $game_data       = $arg_ref->{game_data};

  my $division = $this->initialize(
    filename        => $filename,
    division_name   => $division_name,
    division_number => $division_number,
    players         => $players,
    game_data       => $game_data
  );

  $division->create_matrix();
  return $division;
}

sub process
{
  my $this    = shift;
  my $correct = shift;

  if ( !$this->is_valid() )
  {
    return;
  }

  my $filename      = $this->{$DIVISION_TOUFILE};
  my $division_name = $this->{$DIVISION_NAME};

  my $number_of_rounds  = $this->{$DIVISION_NUMBER_OF_ROUNDS};
  my @players           = @{ $this->{$DIVISION_PLAYERS} };
  my $number_of_players = scalar @players;

  # At this point the matrix is guaranteed to be
  # rectangular with dimensions (number of players x number of games)
  # due to the checks in create_matrix

  for my $round ( 0 .. $number_of_rounds - 1 )
  {
    # The outer loop iterates through each round while the
    # inner loop iterates through each player. For each
    # round we verify that each player is paired exactly
    # once and that the opponent of the opponent is the player
    for my $player_number ( 0 .. $number_of_players - 1 )
    {
      my $player_result   = $this->get_matrix_index( $player_number, $round );
      my $player_name     = $this->{$DIVISION_PLAYERS}->[$player_number];
      my $opponent_number = $player_result->{$RESULT_OPPONENT_NUMBER};

      if ( $opponent_number < 0 || $opponent_number > $number_of_players - 1 )
      {
        # Covered by TC 13
        my $message_type = 'ERROR';
        my $message      = 'Out of range opponent number';
        if ($correct)
        {
          $message_type = 'WARNING';
          $message      = 'Out of range opponent number set to bye';
          $player_result->{$RESULT_OPPONENT_NUMBER} = $player_number;
        }
        $this->set_verification_report(
          Utils::format_error(
            [ [ $message_type,     $message ],
              [ 'File',            $filename ],
              [ 'Division',        $division_name ],
              [ 'Round',           $round + 1 ],
              [ 'Player',          $player_name ],
              [ 'Opponent Number', $opponent_number + 1 ],
            ]
          )
        );
        if ( !$correct )
        {
          $this->set_valid(0);
          return;
        }
      }

      $player_result->{$RESULT_ROUND}         = $round;
      $player_result->{$RESULT_PLAYER_NUMBER} = $player_number;

      my $opponent_result
        = $this->get_matrix_index( $opponent_number, $round );
      my $opponent_opponent_number
        = $opponent_result->{$RESULT_OPPONENT_NUMBER};
      if ( $opponent_opponent_number != $player_number )
      {
        # Covered by TC 14
        my $message_type = 'ERROR';
        my $message
          = q{The opponent of the player's opponent is not the player};
        if ($correct)
        {
          $message_type = 'WARNING';
          $message .= ' and was set to a bye';
          $player_result->{$RESULT_OPPONENT_NUMBER} = $player_number;
        }

        $this->set_verification_report(
          Utils::format_error(
            [ [ $message_type, $message ],
              [ 'File',        $filename ],
              [ 'Division',    $division_name ],
              [ 'Round',       $round + 1 ],
              [ 'Player',      $player_name . " ($player_number)" ],
              [ q{Player's Opponent},
                $this->{$DIVISION_PLAYERS}->[$opponent_number]
                  . " ($opponent_number)"
              ],
              [ q{Player's Opponent's Opponent},
                $this->{$DIVISION_PLAYERS}->[$opponent_opponent_number]
                  . " ($opponent_opponent_number)"
              ]
            ]
          )
        );
        if ( !$correct )
        {
          $this->set_valid(0);
          return;
        }
      }

      my $player_score   = $player_result->get_score();
      my $opponent_score = $opponent_result->get_score();
      my $spread         = $player_score - $opponent_score;
      my $wins           = 0;
      my $losses         = 0;
      my $bye_wins       = 0;
      my $byes           = 0;
      my $coded_result;

      if ( $opponent_number == $player_number )
      {
        $byes = 1;
        my $tou_score = $player_result->get_tou_score();
        if ( $tou_score > $TOU_BASE_WINNING_SCORE )
        {
          $bye_wins     = 1;
          $coded_result = $RESULT_CODED_WIN;
        }
        elsif ( $tou_score == $TOU_TIE_SCORE_RESULT )
        {
          $bye_wins     = $TOU_TIE_VALUE;
          $coded_result = $RESULT_CODED_TIE;
        }
        $player_result->{$RESULT_SCORE} = 0;
      }
      else
      {
        if ( $spread > 0 )
        {
          $wins         = 1;
          $coded_result = $RESULT_CODED_WIN;
        }
        elsif ( $spread == 0 )
        {
          $wins         = $TOU_TIE_VALUE;
          $losses       = $TOU_TIE_VALUE;
          $coded_result = $RESULT_CODED_TIE;
        }
        else
        {
          $losses       = 1;
          $coded_result = $RESULT_CODED_LOSS;
        }
      }
      $player_result->{$RESULT_WINS}     = $wins;
      $player_result->{$RESULT_LOSSES}   = $losses;
      $player_result->{$RESULT_BYES}     = $byes;
      $player_result->{$RESULT_BYE_WINS} = $bye_wins;
      $player_result->{$RESULT_SPREAD}   = $spread;
      $player_result->{$RESULT_CODED}    = $coded_result;
    }
  }
  return 0;
}

sub set_valid
{
  my $this        = shift;
  my $valid_value = shift;
  $this->{$DIVISION_VALID} = $valid_value;

  return 1;
}

sub set_verification_report
{
  my $this   = shift;
  my $report = shift;
  $this->{$DIVISION_VERIFICATION_REPORT} = $report;

  return 1;
}

sub to_string
{
  my $this = shift;

  my $number_of_rounds  = $this->{$DIVISION_NUMBER_OF_ROUNDS};
  my @players           = @{ $this->{$DIVISION_PLAYERS} };
  my $number_of_players = scalar @players;

  my $division_name = $this->{$DIVISION_NAME};

  my $division_string = "*$division_name\n";
  $division_string .= ( q{ } x $TOU_ZERO_PADDING ) . "0\n";

  for my $player_number ( 0 .. $number_of_players - 1 )
  {
    my $player_name = $this->{$DIVISION_PLAYERS}->[$player_number];
    $division_string .= sprintf '%-30s', $player_name;
    for my $round ( 0 .. $number_of_rounds - 1 )
    {
      my $player_result   = $this->get_matrix_index( $player_number, $round );
      my $opponent_number = $player_result->{$RESULT_OPPONENT_NUMBER};
      my $player_tou_score = $player_result->{$RESULT_TOU_SCORE};
      my $player_is_first  = $player_result->{$RESULT_PLAYER_IS_FIRST};
      my $plus             = $EMPTY_STRING;
      if ($player_is_first)
      {
        $plus = q{+};
      }
      $division_string .= ( sprintf '%6s', $player_tou_score )
        . ( sprintf '%5s', $plus . ( $opponent_number + 1 ) ) . q{ };
    }
    $division_string .= "\n";
  }
  return $division_string;
}

1;