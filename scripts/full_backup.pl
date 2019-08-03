#!/usr/bin/perl

# This script backs up the database files
# and the .STS/.STA and .tou text files

use strict;
use warnings;
use DBI;
use Data::Dumper;

use lib "./modules";
use Constants;

require './scripts/backup_years.pl';

unless (caller)
{
  full_backup();
}

sub full_backup
{
  my $local_backup_dir = shift;
  my $remote_backup_location = shift;
  my $remote_user = shift;
  my $remote_host = shift;
  my $remote_db_user = shift;
  my $remote_db_password = shift;
  # Backup to local location
  my $working_directory = Constants::DEFAULT_WORKING_DIR;

  my $database_name = Constants::DATABASE_NAME;
  my $host_name     = Constants::DATABASE_HOST_NAME;
  my $user_name     = Constants::DATABASE_USER_NAME;
  my $password      = Constants::DATABASE_PASSWORD;

  my $textfiles_backup_prefix = Constants::TEXT_FILES_BACKUP_PREFIX;

  my $localtime = localtime();

  $localtime =~ s/\s+/_/g;

  my $database_backup_name  = $database_name . "_" . $localtime;
  my $textfiles_backup_name = $textfiles_backup_prefix . "_" . $localtime;

  print "$database_backup_name and $textfiles_backup_name\n";
  
  my $local_backup_fullname = $local_backup_dir . '/' . $textfiles_backup_name;

  # Make local backups
  backup_years($working_directory, $local_backup_fullname);
  my $local_database_cmd = "mysqldump --user=$user_name --password=$password $database_name | mysql --user=$user_name --password=$password $database_backup_name";

  system $local_database_cmd;
  
  # Make remote backup

  my $remote_files_cmd = "scp -r $local_backup_fullname $remote_user\@$remote_host:$remote_backup_location";
  system $remote_files_cmd;

  my $remote_database_cmd = "mysqldump -u $user_name -p'$password' $database_name | ssh $remote_user\@$remote_host mysql -u $remote_db_user -p'$remote_db_password' $database_backup_name";

  system $remote_database_cmd;

}

1;


