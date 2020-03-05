#!/usr/bin/perl

package Failure;

use strict;
use warnings;
use version; our $VERSION = qv('1');
use Data::Dumper;

use lib './modules';
use Constants;

sub add_to_traceback
{
  my $this = shift;
  my $item = shift;

  my $traceback = $this->{$FAILURE_TRACEBACK};
  if ($traceback)
  {
    $this->{$FAILURE_TRACEBACK} = $item . ' -> ' . $traceback;
  }
  else
  {
    $this->{$FAILURE_TRACEBACK} = $item;
  }

  return 1;
}

sub get_type
{
  my $this = shift;
  return $this->{$FAILURE_TYPE};
}

sub is_failure
{
  my $this = shift;
  return $this->{$FAILURE_REASON};
}

sub new
{
  my $this = shift;
  my $type = shift;

  my $failure = {};

  for my $i ( 0 .. scalar @{$FAILURE_FIELDS} - 1 )
  {
    my $field = $FAILURE_FIELDS->[$i];
    if ( $field eq $FAILURE_TYPE )
    {
      $failure->{$field} = $type;
    }
    else
    {
      $failure->{$field} = $EMPTY_STRING;
    }
  }
  my $self = bless $failure, $this;
  return $self;
}

sub set_failure
{
  my $this     = shift;
  my $reason   = shift;
  my $expected = shift;
  my $actual   = shift;
  my $diffs    = shift;

  $this->{$FAILURE_REASON}           = $reason;
  $this->{$FAILURE_EXPECTED_RESULTS} = $expected;
  $this->{$FAILURE_ACTUAL_RESULTS}   = $actual;
  $this->{$FAILURE_DIFF}             = $diffs;

  return 1;
}

sub to_string
{
  my $this = shift;

  if ( !$this->is_failure() )
  {
    return $EMPTY_STRING;
  }

  my $failure_string   = $EMPTY_STRING;
  my $max_length_field = 0;

  for my $i ( 0 .. scalar @{$FAILURE_FIELDS} - 1 )
  {
    my $field        = $FAILURE_FIELDS->[$i];
    my $field_length = length $field;
    if ( $field_length > $max_length_field )
    {
      $max_length_field = $field_length;
    }
  }
  for my $i ( 0 .. scalar @{$FAILURE_FIELDS} - 1 )
  {
    my $field = $FAILURE_FIELDS->[$i];
    my $value = $this->{$field};
    my $colon = q{:};
    if ( $field eq $FAILURE_DIFF )
    {
      $colon = q{ };
    }
    $failure_string .= (
      sprintf q{%-} . ( $max_length_field + 2 ) . q{s},
      ( $field . $colon )
      )
      . $value
      . $NEWLINE;
  }
  $failure_string .= $NEWLINE;
  return $failure_string;
}

1;