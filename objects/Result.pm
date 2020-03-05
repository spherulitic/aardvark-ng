#!/usr/bin/perl

package Result;

use strict;
use warnings;
use version; our $VERSION = qv('1');

use lib './modules';
use Constants;
use Utils;

sub add_to_gpr
{
  my $this        = shift;
  my $gpr         = shift;
  my $player_id   = shift;
  my $player_name = shift;

  # If I did it right, the only
  # null player_id's should be for 'bye_players'
  if ( Utils::player_name_is_bye($player_name) )
  {
    return;
  }

  my $opponent_number = $this->{$RESULT_OPPONENT_NUMBER};
  my $player_number   = $this->{$RESULT_PLAYER_NUMBER};
  my $round           = $this->{$RESULT_ROUND};

  my $n1 = $opponent_number;
  my $n2 = $player_number;

  if ( $n1 > $n2 )
  {
    $n1 = $n2;
    $n2 = $opponent_number;
  }

  my $gpr_key   = "$round-$n1-$n2";
  my $gpr_value = $gpr->{$gpr_key};

  my $result = {
    player_id => $player_id,
    score     => $this->get_score(),
    result    => $this->{$RESULT_CODED}
  };

  if ($gpr_value)
  {
    push @{ $gpr_value->{results} }, $result;
  }
  else
  {
    $gpr->{$gpr_key} = {
      game => {
        round        => $round,
        lexicon_id   => 1,               # Unused for now
        gcg_filename => 'example.gcg'    # Unused for now
      },
      results => [$result]
    };
  }

  return 1;
}

sub get_score
{
  my $this = shift;
  return $this->{$RESULT_SCORE};
}

sub get_tou_score
{
  my $this = shift;
  return $this->{$RESULT_TOU_SCORE};
}

sub new
{
  my $this = shift;

  my $result = {};

  my $tou_score       = shift;
  my $opponent_number = shift;
  my $player_is_first = shift;

  $result->{$RESULT_TOU_SCORE}       = $tou_score;
  $result->{$RESULT_OPPONENT_NUMBER} = $opponent_number;
  $result->{$RESULT_PLAYER_IS_FIRST} = $player_is_first;

  my $score = $tou_score;

  if ( $score > $TOU_MINIMUM_WIN_SCORE )
  {
    $score -= $TOU_BASE_WINNING_SCORE;
  }
  elsif ( $score > $TOU_BASE_TIE_SCORE )
  {
    $score -= $TOU_BASE_TIE_SCORE;
  }

  $result->{$RESULT_SCORE} = $score;

  my $self = bless $result, $this;
  return $self;
}

1;
