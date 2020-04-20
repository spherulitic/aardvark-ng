package Ratings;

use strict;
use warnings;
use version; our $VERSION = qv('1');
use Data::Dumper;

sub is_ratable
{
  my $date = shift;

  return 0;
}

sub rate_division
{
  my $division     = shift;
  my $ranking_info = shift;

  return 1;
}

1;
