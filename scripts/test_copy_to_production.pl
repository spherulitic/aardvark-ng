#!/usr/bin/perl

# FOR TESTING PURPOSES ONLY

use strict;
use warnings;
use DBI;
use Data::Dumper;

use lib "./modules";
use Constants;

require "./scripts/utils.pl";


copy_database_to_production();

1;



