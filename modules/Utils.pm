#!/usr/bin/perl

package Utils;

use strict;
use warnings;
use version; our $VERSION = qv('1');
use DBI;
use Cwd;
use Data::Dumper;
use Carp;
use English qw( -no_match_vars ); 

use lib './modules';
use Constants;

sub write_file_to_array
{
  my $filename = shift;

  open(my $fh, '<', $filename) or croak "Cannot open file $filename: $OS_ERROR\n";
  my @array = <$fh>;
  close $fh or croak "Cannot close file $filename: $OS_ERROR\n";;
  return @array;
}

sub add_games_to_existing_player
{
  my $dbh          = shift;
  my $player_id    = shift;
  my $games_played = shift;  

  my $players_tn = $PLAYERS_TABLE_NAME;

  my $total_games_update = "UPDATE $players_tn SET total_games = total_games + $games_played WHERE id=$player_id";
  $dbh->do($total_games_update, {"RaiseError" => 1});
  return $dbh->last_insert_id(undef, undef, undef, undef);
}

sub backup_years
{
  my $base_directory_name = shift;
  my $backup_dir          = shift;

  my $year_regex = $DEFAULT_YEAR_REGEX;
  mkdir $backup_dir;

  $base_directory_name .= q{/};

  my @tournament_data_filenames = ();

  opendir my $base_directory, $base_directory_name or croak "Cannot open $base_directory_name: $OS_ERROR";
  my @year_directory_names = grep {/$year_regex/xms} readdir($base_directory);

  foreach my $year_directory_name (@year_directory_names)
  {
    my $year_directory_full_path_name = $base_directory_name . $year_directory_name;
    system "cp -r $year_directory_full_path_name $backup_dir";
  }
  return \@tournament_data_filenames;
}

sub check_country_flag_icons
{
  my $country_ref = shift;

  my @countries = @{$country_ref};

  my $filename_prefix = $COUNTRY_FLAGS_DIR;
  my $trigraph_hashref = $COUNTRY_TRIGRAPH_TO_COUNTRY_NAME_HASHREF;

  opendir my $flag_dir_handle, $filename_prefix or croak "Cannot open $filename_prefix: $OS_ERROR\n";
  my @existing_flags = grep { /[A-Z]{3}/xms } readdir($flag_dir_handle);

  foreach my $ef (@existing_flags)
  {
    $ef =~ /(([A-Z]{3}))/xms;
    if (!$trigraph_hashref->{$1})
    {   
      Utils::format_error([
                            ['WARNING', 'Invalid flag image name'],
                            ['File',  $ef]
                          ]);
    }   
  }

  my $extension = ".png";

  foreach my $country (@countries)
  {
    my $flag = $filename_prefix . q{/} . $country . $extension;
    if (!(-e $flag))
    {   
      Utils::format_error([
                            ['WARNING', 'Missing flag image'],
                            ['Country', $country],
                            ['Missing File', $flag],
                          ]);
    }   
  }
  return 1;
}

sub compare_names
{
  my $tou_ref = shift;
  my $st_ref  = shift;

  my $not_in_tou = $EMPTY_STRING;
  my $not_in_st  = $EMPTY_STRING;

  foreach my $tou_key (keys %{$tou_ref})
  {
      if (!($st_ref->{$tou_key}) && !Utils::player_name_is_bye($tou_key))
      {
        $not_in_st .= $tou_key . ', ';
      }
  }

  foreach my $st_key (keys %{$st_ref})
  {
    if (!$tou_ref->{$st_key} && !Utils::player_name_is_bye($st_key))
    {
      $not_in_tou .= $st_key . ", ";
    }
  }

  if ($not_in_tou || $not_in_st)
  {
    return [$not_in_tou,$not_in_st];
  }
  return 1;

}

sub connect_to_database
{
  my $database_name = Utils::get_environment_name($DATABASE_NAME);
  my $host_name     = $DATABASE_HOST_NAME;
  my $user_name     = $DATABASE_USER_NAME;
  my $password      = $DATABASE_PASSWORD;

  my $dbh = DBI->connect("DBI:mysql:database=$database_name;host=$host_name",
                         $user_name, $password,
                         {'RaiseError' => 1}); 
  return $dbh;
}

sub convert_name
{
  my $name = shift;
  my $alt_names_hash = shift;

  $name =~ s/^\s+|\s+$//gxms;

  my $true_name = $alt_names_hash->{$name};

  if ($true_name)
  {
    return $true_name;
  }
  return $name;
}

sub convert_trigraph
{
  my $trigraph = shift;
  my $trigraph_hash = $COUNTRY_TRIGRAPH_TO_COUNTRY_NAME_HASHREF;
  my $trigraph_correction_hash = $COUNTRY_TRIGRAPH_CONVERSION;

  if (!$trigraph)
  {
    return;
  }
 
  if ($trigraph_hash->{$trigraph})
  {
    return $trigraph;
  }

  my $correct_trigraph = $trigraph_correction_hash->{$trigraph};
  if ($correct_trigraph)
  {
    return $correct_trigraph;
  }

  if (length $trigraph == $TRIGRAPH_LENGTH)
  {
    Utils::format_error([
                          ['WARNING', 'Uncorrected country trigraph'],
                          ['Trigraph', $trigraph],
                        ]);
  }
  return;
}

sub copy_database_to_production
{
  my $production_database_name = Utils::get_environment_name($PRODUCTION_DATABASE_NAME);

  my $database_name = Utils::get_environment_name($DATABASE_NAME);
  my $user_name     = $DATABASE_USER_NAME;
  my $password      = $DATABASE_PASSWORD;

  system "echo 'DROP DATABASE IF EXISTS $production_database_name' | mysql -u $user_name --password='$password'";
  system "echo 'CREATE DATABASE         $production_database_name' | mysql -u $user_name --password='$password'";
  system "mysqldump -u $user_name --password='$password' $database_name | mysql -u $user_name --password='$password' $production_database_name";
  return 1;
}

sub create_html_id
{
  my $html_element = shift;
  my $type         = shift;
  my $id           = shift;

  return (join "_", ($html_element, $type, $id));
}

sub drop_all_wespa_tables
{
  my $dbh = shift;
  my $alt_names_hash = shift;

  my $database_name = Utils::get_environment_name($DATABASE_NAME);
  my $host_name     = $DATABASE_HOST_NAME;
  my $user_name     = $DATABASE_USER_NAME;
  my $password      = $DATABASE_PASSWORD;
  
  my $table_ref = $TABLE_CREATION_ORDER;
  my $exceptions = $TABLE_DROP_EXCEPTIONS;

    foreach my $t (reverse @{$table_ref})
  {
    if (!$exceptions->{$t})
    {
      $dbh->do("DROP TABLE IF EXISTS $t");
    }
  }
  
  my $players_tn = $PLAYERS_TABLE_NAME;

  foreach my $key (keys %{$alt_names_hash})
  {
    $key =~ s/'/''/gxms;
    my $delete_redundant_players =
      "DELETE FROM $players_tn WHERE name = '$key'"; 
    $dbh->do($delete_redundant_players, {"RaiseError" => 1}); 
  }

  my $reset_games_played = "UPDATE $players_tn AS p SET p.total_games = 0"; 
  
  $dbh->do($reset_games_played, {"RaiseError" => 1}); 

  my $reset_last_played = "UPDATE $players_tn AS p SET p.last_played = '0001-01-01'"; 
  
  $dbh->do($reset_last_played, {"RaiseError" => 1});

  return 1;
}

sub empty_string_if_nonpositive
{
  my $num = shift;
  if (!$num || $num <= 0)
  {
    return $EMPTY_STRING;
  }
  return $num;
}

sub execute_command
{
  my $cmd = shift;
  system $cmd;
  return 1;
}

sub fetch_local_tournament_data
{
  my $update_start_year = $UPDATE_START_YEAR;
  my $source_dir        = $UPDATE_SOURCE_DIR;
  my $scratch_dir       = Utils::get_environment_name($TOURNAMENT_DATA_DIR);

  Utils::execute_command("mkdir -p $scratch_dir");

  my @localtime_data = localtime();
  my $current_year = $localtime_data[$LOCALTIME_YEAR_INDEX] + $LOCALTIME_YEAR_BASE;

  for my $year ($update_start_year .. $current_year)
  {
    my $rf_cmd = "rm -rf $scratch_dir/$year";
    Utils::execute_command($rf_cmd);
    if (-e "$source_dir/$year")
    {
      my $cp_cmd = "cp -r $source_dir/$year $scratch_dir/";
      Utils::execute_command($cp_cmd);
    }
  }
  return 1;
}

sub format_error
{
  my $error_arrayref = shift;

  my $l = scalar @{$error_arrayref};
  my $error_string = $EMPTY_STRING;
  my $max_field_length = 0;

  for my $i (0 .. $l - 1)
  {
    my $item1 =  $error_arrayref->[$i]->[0];
    my $item1_length = length $item1;
    
    if ($item1_length > $max_field_length)
    {
      $max_field_length = $item1_length;
    }
  }

  for my $i (0 .. $l - 1)
  {
    my $item1 =  $error_arrayref->[$i]->[0];
    my $item2 =  $error_arrayref->[$i]->[1];

    if (!$item1){$item1 = 'undef';}
    if (!$item2){$item2 = 'undef';}

    $error_string .=  (sprintf q{%-} . ($max_field_length + 2) . q{s}, $item1 . q{:}) . $item2 . "\n";
  }
  $error_string .= "\n";
  print $error_string;
  return $error_string;
}

sub get_country_from_filename
{
  my $filename = shift;
  my @filename_items = split /\//xms, $filename;
  return $filename_items[$COUNTRY_IN_FILENAME_INDEX];
}

sub get_environment_name
{
  my $name = shift;
  my $keyword = $DEV_ENV_KEYWORD;
  my $dir = Cwd::getcwd();
  if ($dir =~ /$keyword/ixms)
  {
    return $name . $keyword;
  }
  return $name;
}

sub get_most_recent_tournament
{
  my $dbh      = shift;
  my $trigraph = shift;

  my $tournaments_tn        = $TOURNAMENTS_TABLE_NAME;
  my $divisions_tn          = $DIVISIONS_TABLE_NAME;
  my $tournament_results_tn = $TOURNAMENT_RESULTS_TABLE_NAME;
  my $players_tn            = $PLAYERS_TABLE_NAME;
  
  my $query;
  
  if ($trigraph)
  {
    $query =
    "
      SELECT t.id AS id, t.name AS name
      FROM $tournament_results_tn AS tr, $players_tn AS p, $divisions_tn AS d, $tournaments_tn AS t
      WHERE
            d.tournament_id = t.id        AND
            tr.division_id  = d.id        AND
            tr.player_id    = p.id        AND
            p.country       = '$trigraph' AND
            p.deceased      = 0           AND
            p.suspended     = 0           AND
            p.current       = 1
            
      ORDER BY t.end_date DESC
    ";
  }
  else
  {
    $query =
    "
      SELECT id, name
      FROM $tournaments_tn
      GROUP BY end_date DESC
    ";
  }
  my @tournament_name = @{$dbh->selectall_arrayref($query, {"RaiseError" => 1})};
  return [$tournament_name[0]->[0],  $tournament_name[0]->[1]];

}

sub get_player_photo
{
  my $name = shift;

  my $photo_dir = Utils::get_environment_name($DEFAULT_WORKING_DIR) . q{/} . $PHOTO_DIR;

  $name =~ s/\s//gxms;

  $name = lc $name;

  my $filename = $photo_dir . q{/} . $name . '.jpg';

  if (-e $filename)
  {
    return $filename;
  }
  return; 
}

sub get_tournament_data_filenames
{
  my $base_directory_name    = shift;
  my $year_regex             = shift;
  my $country_trigraph_regex = shift;
  my $file_regex             = shift;

  $base_directory_name .= q{/};

  my @tournament_data_filenames = (); 

  opendir my $base_directory, $base_directory_name
    or croak "Cannot open $base_directory_name: $OS_ERROR";
  my @year_directory_names = grep {/$year_regex/xms} readdir($base_directory);

  @year_directory_names = sort {$a <=> $b} @year_directory_names;

  for my $i (0 .. scalar @year_directory_names - 1)
  {
    my $year_directory_name = $year_directory_names[$i];
    my $year_directory_full_path_name =
      $base_directory_name . $year_directory_name;

    opendir my $year_directory, $year_directory_full_path_name
      or croak "Cannot open $year_directory_full_path_name: $OS_ERROR";

    my @country_trigraphs =
      grep { /$country_trigraph_regex/xms } readdir($year_directory);

    foreach my $country_trigraph (@country_trigraphs)
    {
      my $trigraph_directory_full_path_name =
        $year_directory_full_path_name . q{/} .  $country_trigraph;

      opendir my $trigraph_directory, $trigraph_directory_full_path_name
        or croak "Cannot open $trigraph_directory_full_path_name: $OS_ERROR";

      my @filenames = grep { /$file_regex/ixms } readdir($trigraph_directory);

      my @full_filenames =
        map { $trigraph_directory_full_path_name . q{/}  . $_} @filenames;

      push @tournament_data_filenames, @full_filenames;
    }
  }
  return \@tournament_data_filenames;
}

sub initialize_database
{
  my $dbh                = shift;
  my $tables_ref         = shift;
  my $creation_order_ref = shift;

  my %tables = %{$tables_ref};
  my @creation_order = @{$creation_order_ref};

  for my $i (0 .. scalar @creation_order - 1)
  {
    my $key = $creation_order[$i];
    my @columns = @{$tables{$key}};
    
    my $columns_string = join ', ', @columns;
   
    my $statement = "CREATE TABLE IF NOT EXISTS $key ($columns_string)";
    
    $dbh->do($statement);
  }

  my $lexicons               = $LEXICONS;
  my $lexicons_tn            = $LEXICONS_TABLE_NAME;

  Utils::insert_hash_list_into_table
  (
    $dbh,
    $lexicons_tn,
    $lexicons,
    'name'
  );
  return 1;
}

sub insert_hash_into_table
{
  my $dbh     = shift;
  my $table   = shift;
  my $hashref = shift;
 
  my $keys_string   = q{(};
  my $values_string = q{(};

  foreach my $key (keys %{$hashref})
  {
    if (defined $hashref->{$key})
    {
      $keys_string   .= "$key,";
      $values_string .= "\"$hashref->{$key}\",";
    }
  }

  chop($keys_string);
  chop($values_string);

  if (!$keys_string || !$values_string)
  {
    return;
  }

  $keys_string   .= q{)};
  $values_string .= q{)};

  $dbh->do("INSERT INTO $table $keys_string VALUE $values_string;", {"RaiseError" => 1}  );
  return $dbh->last_insert_id(undef, undef, undef, undef);
}

sub insert_hash_list_into_table
{
  my $dbh     = shift;
  my $table   = shift;
  my $listref = shift;

  my $last_insert_id_key_field = shift;

  my $last_insert_id_hash = {};

  my @list = @{$listref};

  foreach my $item (@list)
  {
    my $id = Utils::insert_hash_into_table($dbh, $table, $item);
    if ($last_insert_id_key_field)
    {
      $last_insert_id_hash->{$item->{$last_insert_id_key_field}} = $id;
    }
  }
  return $last_insert_id_hash;
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

sub make_new_entry_head
{
  my ($arg_ref) = @_;

  my $games_ref       = $arg_ref->{games_ref};
  my $keys_ref        = $arg_ref->{keys_ref};
  my $row_class       = $arg_ref->{row_class};
  my $entry_id        = $arg_ref->{entry_id};
  my $title_length    = $arg_ref->{title_length};
  my $games_title_row = $arg_ref->{games_row_title};

  my $new_entry = $EMPTY_STRING;

  $new_entry .=
      Utils::make_row
      (
        item => $games_ref->[0], 
        keys => $keys_ref,
        class => $row_class
      );

  $new_entry .= "<tr style='border: none'><td style='padding: 0px; border: 0px'></td><td style='padding: 0px; border: 0px'  colspan='" . ( $title_length - 1) . "'><div class='collapse' id='$entry_id'><table class='table'>\n";

  $new_entry .= $games_title_row;

  return $new_entry;
}

sub make_pretty
{
  my $name = shift;

  $name =~ s/_/ /gxms;

  return $name;
}

sub make_row
{
  my $arg_ref = @_;

  my $item      = $arg_ref->{item};
  my $keys      = $arg_ref->{keys};
  my $is_title  = $arg_ref->{is_title};
  my $id        = $arg_ref->{id};
  my $class     = $arg_ref->{class};
  my $colspan   = $arg_ref->{colspan};

  my $el = 'td';

  if ($is_title)
  {
    $el = 'th';
  }

  my $colspan_attr = $EMPTY_STRING;

  if ($colspan)
  {
    $colspan_attr = " colspan='$colspan' ";
  }

  my @key_array = @{$keys};

  my $id_string = $EMPTY_STRING;

  if ($id)
  {
    $id_string = " id='$id'"; 
  }

  my $class_string = $EMPTY_STRING;

  if ($class)
  {
    $class_string = " class='$class' ";
  }

  my $row_string = "        <tr $class_string $id_string>";
  for my $i (0 .. scalar @key_array - 1)
  {
    my $key = $key_array[$i];
    my $val = $key;
    my $class = $EMPTY_STRING;

    if (!$is_title)
    {
      $val = $item->{$key};
    }

    my $base_dir = $DEFAULT_SHORT_NAME_WORKING_DIR . q{/} . $HTML_DIR;
    my $tournament_dir = $TOURNAMENT_HTML_DIR;
    my $player_dir     = $PLAYER_HTML_DIR;
    my $rankings_dir   = $RANKINGS_HTML_DIR;
    my $trigraph_hashref = $COUNTRY_TRIGRAPH_TO_COUNTRY_NAME_HASHREF;

    if ($key eq 'tr_tournament_name')
    {
      $val = Utils::make_link($base_dir, $tournament_dir, $item->{'t_id'} . '.html', $val);
    }
    elsif ($key eq 'opp_name')
    {
      $val = Utils::make_link($base_dir, $player_dir, $item->{'opp_id'} . '.html', $val);
    }
    elsif ($key eq 'tr_player_name')
    {
      $val = Utils::make_link($base_dir, $player_dir, $item->{'tr_player_id'} . '.html', $val);
    }
    elsif ($key eq 'name')
    {
      $val = Utils::make_link($base_dir, $player_dir, $item->{'id'} . '.html', $val);
    }
    elsif ($key eq 'p_country' || $key eq 'country')
    {
      my $trig = $item->{'p_country'};

      if (!$trig)
      {
        $trig = $item->{'country'};
      }
      if ($trig)
      {
        my $country_fullname = $trigraph_hashref->{$trig};
        if ($country_fullname)
        {
          $val = Utils::make_link($base_dir, $rankings_dir, "$trig.html", $country_fullname);
        }
      }
    }
    elsif ($key eq 'tr_wins' || $key eq 'hh_wins')
    {
      $class = "class='winscolumn'";
    }
    elsif ($key eq 'tr_losses' || $key eq 'hh_losses')
    {
      $class = "class='lossescolumn'";
    }
    elsif ($key eq 'hh_draws')
    {
      $class = "class='drawscolumn'";
    }
    elsif ($key eq 'tr_byes')
    {
      $class = "class='byescolumn'";
    }
    if (!(defined $val))
    {
      $val = $EMPTY_STRING;
    }

    $row_string .= sprintf "<$el $colspan_attr $class >%s</$el>", $val;
  }
  $row_string .= "</tr>\n";

  return $row_string;
}

sub make_tab_div
{
  my $content   = shift;
  my $tabclass  = shift;
  my $linkclass = shift;

  my $content_length = scalar @{$content};

  my $div = "<br><div class='tab'>\n";

  for my $i (0 .. $content_length - 1)
  {
    my $text = $content->[$i]->[0];
    my $id   = $content->[$i]->[1];
    my $width = $FULL_WIDTH / $content_length;
    $div .= "<button id='button_" . $id . "' style='width: $width%' class='$linkclass' onclick=\"showContent(event, '$id', '$tabclass', '$linkclass')\">$text</button>";
  }
  $div .= '</div><br>';
  return $div;
}

sub negative_one_if_false
{
  my $s = shift;
  if ($s)
  {
    return $s;
  }
  return $NEGATIVE_ONE;
}

sub player_name_is_bye
{
  my $name = shift;

  $name = Utils::sanitize($name);

  if ($name eq 'RUSSELLBYERS')
  {
    return 1;
  }

  return ($name =~ /BYE/xms);
}

sub populate_alt_names_hash
{
  my $dup_filename = $INPUT_DIR . q{/} . $INPUT_MERGE_FILE;

  my $alt_names_hash = {};

  my @dup_lines = Utils::write_file_to_array($dup_filename);
  
  while (@dup_lines)
  {
    my $dl = shift @dup_lines;

    $dl =~ s/^\s+|\s+$//gxms;

    if ($dl =~ /^#/xms || !$dl){next;}

    my @names = split /,/xms, $dl;

    @names = map { $dl =~ s/^\s+|\s+$//grxms  } @names;

    if (!@names){next;}

    my $true_name = shift @names;

    foreach my $alt_name (@names)
    {
      if ($alt_names_hash->{$alt_name})
      {
        croak Utils::format_error([
                                    ['ERROR',            'alternative name already mapped'],
                                    ['Alternative name', $alt_name]
                                  ]);
      }
      $alt_names_hash->{$alt_name} = $true_name;
    }
  }
  return $alt_names_hash;
}

sub populate_deceased_players_hash
{
  my $alt_names_hash = shift;
  my $deceased_players_filename = $INPUT_DIR . q{/} .
                                  $DECEASED_PLAYERS;
  
  my $deceased_players_hash = {};

  my @deceased_lines = Utils::write_file_to_array($deceased_players_filename);
  while(@deceased_lines)
  {
    my $dl = shift @deceased_lines;

    $dl =~ s/^\s+|\s+$//gxms;

    my $true_name = $dl;
    my $alt_name  = $alt_names_hash->{$dl};

    if ($alt_name)
    {    
      $true_name = $alt_name;
    }    

    $deceased_players_hash->{$dl} = 1; 
  }
  return $deceased_players_hash;
}

sub query_table
{
  my $dbh         = shift;
  my $table       = shift;
  my $table_field = shift;
  my $query_field = shift;

  my $query = "SELECT * FROM $table WHERE $table_field='$query_field'";

  my $query_result = $dbh->selectall_arrayref($query, {Slice => {}, 'RaiseError' => 1});

  return $query_result;
}

sub rank_tournament_results
{
  my $tournament_results_ref = shift;

  my @tournament_results = @{$tournament_results_ref};

  my @ranked_tournament_results =
    sort
     { 
       $b->{wins} + $b->{bye_wins} <=> $a->{wins} + $a->{bye_wins} ||
       $b->{spread} <=> $a->{spread}
     } 
    @tournament_results;

  for my $i (0 .. scalar @ranked_tournament_results - 1)
  {
    $ranked_tournament_results[$i]->{position} = $i + 1;
  }
  return @ranked_tournament_results;
}

sub record_database
{
  my $dbh = shift;

  my $maybe_dev     = Utils::get_environment_name($EMPTY_STRING);
  my $database_name = Utils::get_environment_name($DATABASE_NAME);
  my $host_name     = $DATABASE_HOST_NAME;
  my $user_name     = $DATABASE_USER_NAME;
  my $password      = $DATABASE_PASSWORD;
  
  my $logs          = $LOG_DIR;
  my $players_tn    = $PLAYERS_TABLE_NAME;
  my $working_dir   = $DEFAULT_WORKING_DIR;

  my $tstamp = get_iso_date(time(), q{_});

  my $dumpfile = 'mysqldump_' . $database_name . '_' . $tstamp;

  my $dump_cmd = "mysqldump -u $user_name --password='$password' $database_name $players_tn > $logs/$dumpfile";

  system $dump_cmd;
 
  my @players = @{$dbh->selectall_arrayref("SELECT name, id FROM $players_tn", {"RaiseError" => 1} )};

  my $player_ids = join "\n", (map {$_->[0] . ', ' . $_->[1]} @players) ;
  
  Utils::write_string_to_file($player_ids, "$logs/player_ids_$database_name" . "$tstamp.txt");

  if ($maybe_dev)
  {
    $maybe_dev = q{_} . $maybe_dev;
  }

  Utils::write_string_to_file($player_ids, "$working_dir/player_ids$maybe_dev.txt");

  return 1;
}

sub sanitize
{
  my $name = shift;
  
  $name = uc $name;

  $name =~ s/[^A-Z]//gxms;

  return $name;
}

sub get_iso_date
{
  my $time      = shift;
  my $separator = shift;
  
  my @t = localtime($time);
  $t[$LOCALTIME_YEAR_INDEX] += $LOCALTIME_YEAR_BASE;
  $t[$LOCALTIME_MONTH_INDEX]++;
  
  return sprintf "%04d$separator%02d$separator%02d", @t[$LOCALTIME_YEAR_INDEX,$LOCALTIME_MONTH_INDEX,$LOCALTIME_DAY_INDEX];
}

sub set_current_status
{
  my $dbh = shift;

  my $players_tn        = $PLAYERS_TABLE_NAME;
  my $current_games_min = $CURRENT_GAMES_MIN;
  
  my $database_name = Utils::get_environment_name($DATABASE_NAME);
  my $host_name     = $DATABASE_HOST_NAME;
  my $user_name     = $DATABASE_USER_NAME;
  my $password      = $DATABASE_PASSWORD;
  
  my $datestring = localtime();
  my $epoc       = time();
  $epoc         -= $TWO_YEARS_IN_SECONDS;   # two years before current date.
  
  my $date_two_years_ago = get_iso_date($epoc, q{-});

  my $games_in_last_two_years =
  "
  (
    SELECT SUM(tr.wins + tr.losses)
    FROM tournaments AS t, divisions AS d, tournament_results AS tr
    WHERE p.id = tr.player_id AND
          tr.division_id = d.id AND
          d.tournament_id = t.id AND t.end_date > '$date_two_years_ago'
  )
  ";

  my $update_current =
  "
  UPDATE $players_tn AS p
  SET p.current =
  (
    CASE
      WHEN $games_in_last_two_years > 0 AND p.total_games > $current_games_min
        THEN 1
      ELSE 0
    END
  )
  ";

  $dbh->do($update_current, {'RaiseError' => 1});

  return 1;
}

sub set_provisional_status
{
  my $dbh = shift;
  my $players_tn            = $PLAYERS_TABLE_NAME;
  my $provisional_games_max = $PROVISIONAL_GAMES_MAX;

  # Update provisional status for all players 
  my $update_provisional =
  "
  UPDATE $players_tn AS p
  SET p.provisional =
  (
    CASE
      WHEN p.total_games < $provisional_games_max
        THEN 1
      ELSE 0
    END
  )
  ";
  $dbh->do($update_provisional, {'RaiseError' => 1});

  return 1;
}

sub stat_objects
{
  my $game_stats_rank_name = $GAME_STATS_RANK_NAME;
  my $stat_key_name        = $STAT_KEY_NAME;
  my $tournament_stats =
    {
      'High Win' =>
      {
        'cond' =>
        sub
        {
          my $data = shift;
          return $data->{pr1_score} > $data->{pr2_score} && $data->{opp_rating} > $WESPA_START_RATING;
        },
        'eval' =>
        sub
        {
          my $data = shift;
          return $data->{pr1_score};
        },
        'sort' =>
        sub
        {
          my $c1 = shift;
          my $c2 = shift;
          $c2->{$stat_key_name} <=> $c1->{$stat_key_name}
        },
        'titles' => ['Rank', 'Player', 'Score', 'Opponent', 'Round'],
        'values' => [$game_stats_rank_name, 'tr_player_name', $stat_key_name, 'opp_name', 'g_round'],
        'list'   => []
      },
      'High Loss' =>
      {
        'cond' =>
        sub
        {
          my $data = shift;
          return $data->{pr1_score} < $data->{pr2_score};
        },
        'eval' =>
        sub
        {
          my $data = shift;
          return $data->{pr1_score};
        },
        'sort' =>
        sub
        {
          my $c1 = shift;
          my $c2 = shift;
          $c2->{$stat_key_name} <=> $c1->{$stat_key_name}
        },
        'titles' => ['Rank', 'Player', 'Score', 'Opponent', 'Round'],
        'values' => [$game_stats_rank_name, 'tr_player_name', $stat_key_name, 'opp_name', 'g_round'],
        'list'   => []
      },
      'High Spread' =>
      {
        'cond' =>
        sub
        {
          my $data = shift;
          return $data->{pr1_score} > $data->{pr2_score}
        },
        'eval' =>
        sub
        {
          my $data = shift;
          return $data->{pr1_score} - $data->{pr2_score};
        },
        'sort' =>
        sub
        {
          my $c1 = shift;
          my $c2 = shift;
          $c2->{$stat_key_name} <=> $c1->{$stat_key_name}
        },
        'titles' => ['Rank', 'Player', 'Opponent', 'Player Score', 'Opponent Score', 'Spread', 'Round'],
        'values' => [$game_stats_rank_name, 'tr_player_name', 'opp_name', 'pr1_score', 'pr2_score', $stat_key_name, 'g_round'],
        'list'   => []
      },
      'High Combined' =>
      {
        'cond' =>
        sub
        {
          my $data = shift;
          # Ensure only one instance gets reported 
          return $data->{'tr_player_id'} > $data->{'opp_id'};
        },
        'eval' =>
        sub
        {
          my $data = shift;
          return $data->{pr1_score} + $data->{pr2_score};
        },
        'sort' =>
        sub
        {
          my $c1 = shift;
          my $c2 = shift;
          $c2->{$stat_key_name} <=> $c1->{$stat_key_name}
        },
        'titles' => ['Rank', 'Players', $EMPTY_STRING, 'Combined Score', 'Round'],
        'values' => [$game_stats_rank_name, 'tr_player_name', 'opp_name', $stat_key_name, 'g_round'],
        'list'   => []
      },
      'Upsets' =>
      {
        'cond' =>
        sub
        {
          my $data = shift;
          return $data->{'tr_start_rating'}     &&
                 $data->{'opp_rating'}          &&
                 $data->{'tr_start_rating'} > 0 &&
                 $data->{'opp_rating'}      > 0 && 
                 $data->{'opp_rating'}      < $data->{'tr_start_rating'} &&
                 $data->{'pr2_score'} > $data->{'pr1_score'};
        },
        'eval' =>
        sub
        {
          my $data = shift;
          return $data->{'tr_start_rating'} - $data->{'opp_rating'} ;
        },
        'sort' =>
        sub
        {
          my $c1 = shift;
          my $c2 = shift;
          $c2->{$stat_key_name} <=> $c1->{$stat_key_name}
        },
        'titles' => ['Rank', 'Player', 'Player Rating', 'Opponent', 'Opponent Rating', 'Rating Difference', 'Round'],
        'values' => [$game_stats_rank_name, 'tr_player_name', 'tr_start_rating', 'opp_name', 'opp_rating', $stat_key_name, 'g_round'],
        'list'   => []
      }
    };
  return $tournament_stats;
}

sub swap
{
  my $hashref = shift;
  my $attr1   = shift;
  my $attr2   = shift;

  my $tmp = $hashref->{$attr1};
  $hashref->{$attr1} = $hashref->{$attr2};
  $hashref->{$attr2} = $tmp;

  return 1;
}

sub tou_is_loaded
{
  my $dbh = shift;
  my $tou = shift;

  my $loaded_tournaments_tn = $LOADED_TOURNAMENTS_TABLE_NAME;

  my $tou_query = "SELECT * FROM $loaded_tournaments_tn WHERE filename=\"$tou\"";

  my @tou_query_result = $dbh->selectrow_array($tou_query, {"RaiseError" => 1});

  my $is_loaded = 0;

  if (@tou_query_result)
  {
    $is_loaded = 1;
  }

  return $is_loaded;
}

sub uniq
{
  my $array_ref = shift;
  my @array = @{$array_ref};
  my $hashref = map { $_ => 1 } @array;
  return keys %{$hashref};
}

sub update_record_by_id
{
  my $dbh             = shift;
  my $table_name      = shift;
  my $id              = shift;
  my $fields_hash_ref = shift;

  foreach my $key (keys %{$fields_hash_ref})
  {
    my $value = $fields_hash_ref->{$key};
    my $update = "UPDATE $table_name SET $key = '$value' WHERE id=$id";
    $dbh->do($update, {"RaiseError" => 1});
  }

  return 1;
}

sub write_file_to_string
{
  my $file = shift;
  my $string;
  
  if (-e $file)
  {
    $string = $EMPTY_STRING;
    my @file_array = Utils::write_file_to_array($file);
    while(@file_array)
    {
      $string .= shift @file_array;
    }
  }
  
  return $string;
}

sub write_string_to_file
{
  my $string   = shift;
  my $filename = shift;

  open(my $fh, q{>}, $filename) or croak "Cannot open $filename: $OS_ERROR\n";
  print $fh $string;
  close $fh or croak "Cannot close $filename: $OS_ERROR\n";

  return 1;
}

1;