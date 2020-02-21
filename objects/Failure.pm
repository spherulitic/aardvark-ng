#!/usr/bin/perl

package Failure;

use strict;
use warnings;
use Data::Dumper;

use lib './modules';
use Constants;

sub add_to_traceback
{
  my $this = shift;
  my $item = shift;

  my $traceback = $this->{Constants::FAILURE_TRACEBACK};
  if ($traceback)
  {
    $this->{Constants::FAILURE_TRACEBACK} = $item . ' -> ' . $traceback;
  }
  else
  {
    $this->{Constants::FAILURE_TRACEBACK} = $item;
  }
}

sub get_type
{
  my $this = shift;
  return $this->{Constants::FAILURE_TYPE};
}

sub is_failure
{
  my $this = shift;
  return $this->{Constants::FAILURE_REASON};
}

sub new
{
  my $this = shift;
  my $type = shift;

  my $failure = {};

  my $failure_fields = Constants::FAILURE_FIELDS;

  for (my $i = 0; $i < scalar @{$failure_fields}; $i++)
  {
    my $field = $failure_fields->[$i];
    if ($field eq Constants::FAILURE_TYPE)
    {
      $failure->{$field} = $type;
    }
    else
    {
      $failure->{$field} = '';
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

  $this->{Constants::FAILURE_REASON}           = $reason;
  $this->{Constants::FAILURE_EXPECTED_RESULTS} = $expected;
  $this->{Constants::FAILURE_ACTUAL_RESULTS}   = $actual;
  $this->{Constants::FAILURE_DIFF}             = $diffs;
}

sub to_string
{
  my $this = shift;

  if (!$this->is_failure())
  {
    return '';
  }

  my $failure_fields = Constants::FAILURE_FIELDS;
  my $failure_string = '';
  my $max_length_field = 0;

  for (my $i = 0; $i < scalar @{$failure_fields}; $i++)
  {
    my $field = $failure_fields->[$i];
    my $field_length = length $field;
    if ($field_length > $max_length_field)
    {
      $max_length_field = $field_length;
    }
  }
  for (my $i = 0; $i < scalar @{$failure_fields}; $i++)
  {
    my $field = $failure_fields->[$i];
    my $value = $this->{$field};
    my $colon = ':';
    if ($field eq Constants::FAILURE_DIFF)
    {
      $colon = ' ';
    }
    $failure_string .= (sprintf "%-" . ($max_length_field + 2)  . 's' , ($field . $colon)) . $value . "\n";
  }
  $failure_string .= "\n";
  return $failure_string;
}

1;