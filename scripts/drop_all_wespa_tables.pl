#!/usr/bin/perl

use strict;
use warnings;
use DBI;
use Data::Dumper;

use lib "./modules";
use Constants;

my $database_name = Constants::DATABASE_NAME;
my $host_name     = Constants::DATABASE_HOST_NAME;
my $user_name     = Constants::DATABASE_USER_NAME;
my $password      = Constants::DATABASE_PASSWORD;

my $table_ref = Constants::TABLE_CREATION_ORDER;

my $dbh = DBI->connect("DBI:mysql:database=$database_name;host=$host_name",
                       $user_name, $password,
                       {'RaiseError' => 1});

foreach my $t (reverse @{$table_ref})
{
  $dbh->do("DROP TABLE IF EXISTS $t");
}





