#!/usr/bin/perl

# This script contains generic utilities for migration

use strict;
use warnings;
use lib './modules';
use Constants;
use DBI;

sub uniq {
    my $array_ref = shift;
    my %seen;
    foreach my $item (@$array_ref) {
        $seen{$item} = 1;
    }
    return [keys %seen];
}

sub connect_to_database
{
  my $database_name = Constants::DATABASE_NAME;
  my $host_name     = Constants::DATABASE_HOST_NAME;
  my $port          = Constants::DATABASE_PORT;
  my $user_name     = Constants::DATABASE_USER_NAME;
  my $password      = Constants::DATABASE_PASSWORD;

  my %attributes = (RaiseError => 1, PrintError => 0);

  my $ssl_mode = Constants::DATABASE_SSL_MODE;
  my $ssl_ca   = Constants::DATABASE_SSL_CA;

  if ($ssl_mode && $ssl_mode ne 'DISABLED')
  {
    $attributes{'mysql_ssl_mode'} = $ssl_mode;
    $attributes{'mysql_ssl_ca_file'} = $ssl_ca if $ssl_ca;
  }

  my $dbh = DBI->connect(
    "DBI:mysql:database=$database_name;host=$host_name;port=$port",
    $user_name, $password, \%attributes);

  return $dbh;
}

# Command-line connection options for the bundled MySQL client (used by
# shelled-out mysqldump/mysql calls). Returns a string for interpolation.
sub database_cli_options
{
  my @options = ('-h', Constants::DATABASE_HOST_NAME,
                 '-P', Constants::DATABASE_PORT);

  my $ssl_mode = Constants::DATABASE_SSL_MODE;
  if ($ssl_mode && $ssl_mode ne 'DISABLED')
  {
    push @options, '--ssl';
    push @options, '--ssl-ca=' . Constants::DATABASE_SSL_CA
      if Constants::DATABASE_SSL_CA;
    push @options, '--ssl-verify-server-cert'
      if $ssl_mode =~ /^VERIFY/;
  }

  return join ' ', @options;
}

sub get_tournament_data_filenames
{
  my $base_directory_name    = shift;
  my $year_regex             = shift;
  my $country_trigraph_regex = shift;
  my $file_regex             = shift;

  $base_directory_name .= "/";

  my @tournament_data_filenames = (); 

  opendir my $base_directory, $base_directory_name
    or die "Cannot open $base_directory_name: $!";
  my @year_directory_names = grep(/$year_regex/, readdir($base_directory));

  @year_directory_names = sort {$a <=> $b} @year_directory_names;

  for(my $i = 0; $i <  scalar @year_directory_names; $i++)
  {
    my $year_directory_name = $year_directory_names[$i];
    my $year_directory_full_path_name =
      $base_directory_name . $year_directory_name;

    opendir my $year_directory, $year_directory_full_path_name
      or die "Cannot open $year_directory_full_path_name: $!";

    my @country_trigraphs =
      grep(/$country_trigraph_regex/, readdir($year_directory));

    foreach my $country_trigraph (@country_trigraphs)
    {
      my $trigraph_directory_full_path_name =
        $year_directory_full_path_name . "/" .  $country_trigraph;

      opendir my $trigraph_directory, $trigraph_directory_full_path_name
        or die "Cannot open $trigraph_directory_full_path_name: $!";

      my @filenames = grep(/$file_regex/i, readdir($trigraph_directory));

      my @full_filenames =
        map { $trigraph_directory_full_path_name . "/"  . $_} @filenames;

      push @tournament_data_filenames, @full_filenames;
    }
  }
  return \@tournament_data_filenames;
}


1;


