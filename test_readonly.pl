#!/usr/bin/perl

use warnings;
use strict;
use lib '.';

my %subs =
(
	yeet => \&theyeet,
	yoot => \&theyoot
);

$subs{yeet}->();

sub theyeet
{
	print 'been yeeten' . "\n";
}

sub theyoot
{
	print 'been yooten' . "\n";
}
