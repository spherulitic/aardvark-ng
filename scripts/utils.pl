#!/usr/bin/perl

# This script contains generic utilities for migration and webpage building

use strict;
use warnings;
use lib './modules';
use Constants;
use DBI;
use Cwd;

sub copy_database_to_production
{
  my $production_database_name = get_environment_name(Constants::PRODUCTION_DATABASE_NAME);

  my $database_name = get_environment_name(Constants::DATABASE_NAME);
  my $user_name     = Constants::DATABASE_USER_NAME;
  my $password      = Constants::DATABASE_PASSWORD;

  system "echo 'DROP DATABASE IF EXISTS $production_database_name' | mysql -u $user_name --password='$password'";
  system "echo 'CREATE DATABASE         $production_database_name' | mysql -u $user_name --password='$password'";
  system "mysqldump -h 127.0.0.1 --no-tablespaces -u $user_name --password='$password' $database_name | mysql -h 127.0.0.1 -u $user_name --password='$password' $production_database_name";
}

sub uniq {
    my $array_ref = shift;
    my %seen;
    foreach my $item (@$array_ref) {
        $seen{$item} = 1;
    }
    return [keys %seen];
}

sub create_html_id
{
  my $html_element = shift;
  my $type         = shift;
  my $id           = shift;

  return (join "_", ($html_element, $type, $id));
}

sub connect_to_database
{
  my $database_name = get_environment_name(Constants::DATABASE_NAME);
  my $host_name     = Constants::DATABASE_HOST_NAME;
  my $user_name     = Constants::DATABASE_USER_NAME;
  my $password      = Constants::DATABASE_PASSWORD;

  my $dbh = DBI->connect("DBI:mysql:database=$database_name;host=$host_name",
                         $user_name, $password,
                         {'RaiseError' => 1}); 
  return $dbh;
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


sub make_link
{
  my $base_dir = shift;
  my $dir      = shift;
  my $filename = shift;
  my $content  = shift;

  my $link = "<a href='/$base_dir/$dir/$filename'>$content</a>";
  return $link;
}

sub get_environment_name
{
  my $name = shift;
  my $keyword = Constants::DEV_ENV_KEYWORD;
  my $dir = getcwd();
  if ($dir =~ /$keyword/i)
  {
    return $name . $keyword;
  }
  return $name;
}

1;


