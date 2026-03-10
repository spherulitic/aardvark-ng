#!/usr/bin/perl

# This script backs up the database files
# and the .STS/.STA and .tou text files

use strict;
use warnings;
use DBI;
use Data::Dumper;
use Getopt::Long;
use Pod::Usage qw(pod2usage);

use lib "./modules";
use Constants;

require './scripts/backup_years.pl';

unless (caller)
{
  my $local_backup_dir       = '';
  my $remote_backup_location = '';
  my $remote_user            = '';
  my $remote_host            = '';
  my $remote_db_user         = '';
  my $remote_db_password     = '';

  my $help = 0;

GetOptions (
            'lbackup:s'     => \$local_backup_dir,
            'rbackup:s'     => \$remote_backup_location,
            'username:s'    => \$remote_user,
            'hostname:s'    => \$remote_host,
            'dbusername:s'  => \$remote_db_user,
            'dbpassword:s'  => \$remote_db_password,
            'help|?'        => \$help
           );

  my $bad_args = 0;

  if
  (
    (
      $remote_backup_location ||
      $remote_user            ||
      $remote_host            ||
      $remote_db_user         ||
      $remote_db_password
    ) &&
    !
    (
      $remote_backup_location &&
      $remote_user            &&
      $remote_host            &&
      $remote_db_user         &&
      $remote_db_password
    )
  )
  {
    $bad_args = 1;
  }

  if (!$local_backup_dir)
  {
    print "Must specify a local backup directory\n";
  }
  if ($bad_args)
  {
    print "Remote arguments incomplete\n";
  }

  pod2usage(1) if $help || $bad_args || !$local_backup_dir;

  full_backup
  (
    $local_backup_dir,
    $remote_backup_location,
    $remote_user,
    $remote_host,
    $remote_db_user,
    $remote_db_password
  );
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

  $localtime =~ s/[\s+:]/_/g;

  my $database_backup_name  = $database_name . "_" . $localtime;
  my $textfiles_backup_name = $textfiles_backup_prefix . "_" . $localtime;

  print "$database_backup_name and $textfiles_backup_name\n";
  
  my $local_backup_fullname = $local_backup_dir . '/' . $textfiles_backup_name;

  # Make local backups

  backup_years($working_directory, $local_backup_fullname);
  my $local_database_cmd =
  "
    mysql -h 127.0.0.1 --user=$user_name --password=$password -e 'CREATE DATABASE $database_backup_name;'
    mysqldump -h 127.0.0.1 --no-tablespaces --user=$user_name --password=$password $database_name | mysql -h 127.0.0.1 --user=$user_name --password=$password $database_backup_name

  ";

  system $local_database_cmd;
  
  # Make remote backup
  # NOT COMPLETED
  if ($remote_backup_location)
  {
    my $remote_files_cmd = "scp -r $local_backup_fullname $remote_user\@$remote_host:$remote_backup_location";
    system $remote_files_cmd;

    my $remote_database_cmd = "mysqldump -h 127.0.0.1 -u $user_name -p'$password' $database_name | ssh $remote_user\@$remote_host mysql -h 127.0.0.1 -u $remote_db_user -p'$remote_db_password' $database_backup_name";

    system $remote_database_cmd;
  }
}

__END__

=head1 SYNOPSIS

  ./scripts/full_backup.pl -l=<localbackup> [-r=<remotebackup>] [-u=<remoteusername>] [-h=<remotehostname>] [-dbu=<databaseusername>] [-dbp=<databasepassword>]

  Options:
    -h,   --help         this message
    -l,   --lbackup      location of local backup for .tou and .STA/.STS files
    -r,   --rbackub      location of remote backup for .tou and .STA/.STS files
    -u,   --username     ssh username of the remote connection
    -h,   --hostname     ssh hostname of the remote connection
    -dbu, --dbusername   database username of the remote database
    -dbp, --dbpassword   database password of the remote database

=cut


