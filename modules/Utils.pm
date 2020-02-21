#!/usr/bin/perl

package Utils;

use strict;
use warnings;
use DBI;
use Cwd;
use Data::Dumper;

use lib './modules';
use Constants;

sub add_games_to_existing_player
{
  my $dbh          = shift;
  my $player_id    = shift;
  my $games_played = shift;  

  my $players_tn = Constants::PLAYERS_TABLE_NAME;

  my $total_games_update = "UPDATE $players_tn SET total_games = total_games + $games_played WHERE id=$player_id";
  $dbh->do($total_games_update, {"RaiseError" => 1});
  return $dbh->last_insert_id(undef, undef, undef, undef);
}

sub backup_years
{
  my $base_directory_name = shift;
  my $backup_dir          = shift;

  my $year_regex = Constants::DEFAULT_YEAR_REGEX;
  mkdir $backup_dir;

  $base_directory_name .= "/";

  my @tournament_data_filenames = ();

  opendir my $base_directory, $base_directory_name or die "Cannot open $base_directory_name: $!";
  my @year_directory_names = grep(/$year_regex/, readdir($base_directory));

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

  my $filename_prefix = Constants::COUNTRY_FLAGS_DIR;
  my $trigraph_hashref = Constants::COUNTRY_TRIGRAPH_TO_COUNTRY_NAME_HASHREF;

  opendir my $flag_dir_handle, $filename_prefix or die "Cannot open $filename_prefix: $!\n";
  my @existing_flags = grep (/[A-Z]{3}/, readdir($flag_dir_handle));

  foreach my $ef (@existing_flags)
  {
    $ef =~ /(([A-Z]{3}))/;
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
    my $flag = $filename_prefix . '/' . $country . $extension;
    if (!(-e $flag))
    {   
      Utils::format_error([
                            ['WARNING', 'Missing flag image'],
                            ['Country', $country],
                            ['Missing File', $flag],
                          ]);
    }   
  }
}

sub compare_names
{
  my $tou_ref = shift;
  my $st_ref  = shift;

  my $not_in_tou = "";
  my $not_in_st  = "";

  foreach my $tou_key (keys %{$tou_ref})
  {
      if (!($st_ref->{$tou_key}) && !Utils::player_name_is_bye($tou_key))
      {
        $not_in_st .= $tou_key . ", ";
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
  return 0;

}

sub connect_to_database
{
  my $database_name = Utils::get_environment_name(Constants::DATABASE_NAME);
  my $host_name     = Constants::DATABASE_HOST_NAME;
  my $user_name     = Constants::DATABASE_USER_NAME;
  my $password      = Constants::DATABASE_PASSWORD;

  my $dbh = DBI->connect("DBI:mysql:database=$database_name;host=$host_name",
                         $user_name, $password,
                         {'RaiseError' => 1}); 
  return $dbh;
}

sub convert_name
{
  my $name = shift;
  my $alt_names_hash = shift;

  $name =~ s/^\s+|\s+$//g;

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
  my $trigraph_hash = Constants::COUNTRY_TRIGRAPH_TO_COUNTRY_NAME_HASHREF;
  my $trigraph_correction_hash = Constants::COUNTRY_TRIGRAPH_CONVERSION;

  if (!$trigraph)
  {
    return undef;
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

  if (length $trigraph == 3)
  {
    Utils::format_error([
                          ['WARNING', 'Uncorrected country trigraph'],
                          ['Trigraph', $trigraph],
                        ]);
  }
  return undef;
}

sub copy_database_to_production
{
  my $production_database_name = Utils::get_environment_name(Constants::PRODUCTION_DATABASE_NAME);

  my $database_name = Utils::get_environment_name(Constants::DATABASE_NAME);
  my $user_name     = Constants::DATABASE_USER_NAME;
  my $password      = Constants::DATABASE_PASSWORD;

  system "echo 'DROP DATABASE IF EXISTS $production_database_name' | mysql -u $user_name --password='$password'";
  system "echo 'CREATE DATABASE         $production_database_name' | mysql -u $user_name --password='$password'";
  system "mysqldump -u $user_name --password='$password' $database_name | mysql -u $user_name --password='$password' $production_database_name";
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

  my $database_name = Utils::get_environment_name(Constants::DATABASE_NAME);
  my $host_name     = Constants::DATABASE_HOST_NAME;
  my $user_name     = Constants::DATABASE_USER_NAME;
  my $password      = Constants::DATABASE_PASSWORD;
  
  my $table_ref = Constants::TABLE_CREATION_ORDER;
  my $exceptions = Constants::TABLE_DROP_EXCEPTIONS;

    foreach my $t (reverse @{$table_ref})
  {
    if (!$exceptions->{$t})
    {
      $dbh->do("DROP TABLE IF EXISTS $t");
    }
  }
  
  my $players_tn = Constants::PLAYERS_TABLE_NAME;

  foreach my $key (keys %{$alt_names_hash})
  {
    $key =~ s/'/''/g;
    my $delete_redundant_players =
    "   
    DELETE FROM $players_tn
    WHERE name = '$key'
    "; 
    $dbh->do($delete_redundant_players, {"RaiseError" => 1}); 
  }

  my $reset_games_played =
  "
  UPDATE $players_tn AS p
  SET p.total_games = 0
  "; 
  
  $dbh->do($reset_games_played, {"RaiseError" => 1}); 

  my $reset_last_played =
  "
  UPDATE $players_tn AS p
  SET p.last_played = '0001-01-01'
  "; 
  
  $dbh->do($reset_last_played, {"RaiseError" => 1}); 
}

sub empty_string_if_nonpositive
{
  my $num = shift;
  if (!$num || $num <= 0)
  {
    return "";
  }
  return $num;
}

sub execute_command
{
  my $cmd = shift;
  system $cmd;
}

sub fetch_local_tournament_data
{
  my $update_start_year = Constants::UPDATE_START_YEAR;
  my $source_dir        = Constants::UPDATE_SOURCE_DIR;
  my $scratch_dir       = Utils::get_environment_name(Constants::TOURNAMENT_DATA_DIR);

  Utils::execute_command("mkdir -p $scratch_dir");

  my @localtime_data = localtime();
  my $current_year = $localtime_data[5] + 1900;

  for (my $year = $update_start_year; $year <= $current_year; $year++)
  {
    my $rf_cmd = "rm -rf $scratch_dir/$year";
    Utils::execute_command($rf_cmd);
    if (-e "$source_dir/$year")
    {
      my $cp_cmd = "cp -r $source_dir/$year $scratch_dir/";
      Utils::execute_command($cp_cmd);
    }
  }
}

sub write_file_to_string
{
  my $file = shift;
  my $string = '';
  if (-e $file)
  {
    open (my $fh, '<', $file);
    while(<$fh>)
    {
      $string .= $_;
    }
  }
  return $string;
}

sub format_error
{
  my $error_arrayref = shift;

  my $l = scalar @{$error_arrayref};
  my $error_string = '';
  my $max_field_length = 0;

  for (my $i = 0; $i < $l; $i++)
  {
    my $item1 =  $error_arrayref->[$i]->[0];
    my $item1_length = length $item1;
    
    if ($item1_length > $max_field_length)
    {
      $max_field_length = $item1_length;
    }
  }

  for (my $i = 0; $i < $l; $i++)
  {
    my $item1 =  $error_arrayref->[$i]->[0];
    my $item2 =  $error_arrayref->[$i]->[1];

    if (!$item1){$item1 = "undef";}
    if (!$item2){$item2 = "undef";}

    $error_string .=  (sprintf '%-' . ($max_field_length + 2).'s', $item1 . ':') . $item2 . "\n";
  }
  $error_string .= "\n";
  print $error_string;
  return $error_string;
}

sub get_environment_name
{
  my $name = shift;
  my $keyword = Constants::DEV_ENV_KEYWORD;
  my $dir = Cwd::getcwd();
  if ($dir =~ /$keyword/i)
  {
    return $name . $keyword;
  }
  return $name;
}

sub get_most_recent_tournament
{
  my $dbh      = shift;
  my $trigraph = shift;

  my $tournaments_tn        = Constants::TOURNAMENTS_TABLE_NAME;
  my $divisions_tn          = Constants::DIVISIONS_TABLE_NAME;
  my $tournament_results_tn = Constants::TOURNAMENT_RESULTS_TABLE_NAME;
  my $players_tn            = Constants::PLAYERS_TABLE_NAME;
  
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

  my $photo_dir = Utils::get_environment_name(Constants::DEFAULT_WORKING_DIR) . "/" . Constants::PHOTO_DIR;

  $name =~ s/\s//g;

  $name = lc $name;

  my $filename = $photo_dir . "/" . $name . ".jpg";

  if (-e $filename)
  {
    return $filename;
  }
  return undef; 
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

sub initialize_database
{
  my $dbh                = shift;
  my $tables_ref         = shift;
  my $creation_order_ref = shift;

  my %tables = %{$tables_ref};
  my @creation_order = @{$creation_order_ref};

  for(my $i = 0; $i < scalar @creation_order; $i++)
  {
    my $key = $creation_order[$i];
    my @columns = @{$tables{$key}};
    
    my $columns_string = join ", ", @columns;
   
    my $statement = "CREATE TABLE IF NOT EXISTS $key ($columns_string)";
    
    $dbh->do($statement);
  }

  my $lexicons               = Constants::LEXICONS;
  my $lexicons_tn            = Constants::LEXICONS_TABLE_NAME;

  Utils::insert_hash_list_into_table
  (
    $dbh,
    $lexicons_tn,
    $lexicons,
    'name'
  );

}

sub insert_hash_into_table
{
  my $dbh     = shift;
  my $table   = shift;
  my $hashref = shift;
 
  my $keys_string   = "(";
  my $values_string = "(";

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

    return undef;
  }

  $keys_string   .= ")";
  $values_string .= ")";

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
  my $games_ref       = shift;
  my $keys_ref        = shift;
  my $row_class       = shift;
  my $entry_id        = shift;
  my $title_length    = shift;
  my $games_title_row = shift;

  my $new_entry = "";

      $new_entry .=
          Utils::make_row
          (
            $games_ref->[0], 
            $keys_ref,
            0,
            0,
            $row_class
          );

      $new_entry .= "<tr style='border: none'><td style='padding: 0px; border: 0px'></td><td style='padding: 0px; border: 0px'  colspan='" . ( $title_length - 1) . "'><div class='collapse' id='$entry_id'><table class='table'>\n";

      $new_entry .= $games_title_row;

  return $new_entry;
}

sub make_pretty
{
  my $name = shift;

  $name =~ s/_/ /g;

  return $name;
}

sub make_row
{
  my $item      = shift;
  my $keys      = shift;
  my $is_title  = shift;
  my $id        = shift;
  my $class     = shift;
  my $colspan   = shift;

  my $el = "td";

  if ($is_title)
  {
    $el = "th";
  }

  my $colspan_attr = "";

  if ($colspan)
  {
    $colspan_attr = " colspan='$colspan' ";
  }

  my @key_array = @{$keys};

  my $id_string = "";

  if ($id)
  {
    $id_string = " id='$id'"; 
  }

  my $class_string = "";

  if ($class)
  {
    $class_string = " class='$class' ";
  }

  my $row_string = "        <tr $class_string $id_string>";
  for (my $i = 0; $i < scalar @key_array; $i++)
  {
    my $key = $key_array[$i];
    my $val = $key;
    my $class = '';

    if (!$is_title)
    {
      $val = $item->{$key};
    }

    my $base_dir = Constants::DEFAULT_SHORT_NAME_WORKING_DIR . '/' . Constants::HTML_DIR;
    my $tournament_dir = Constants::TOURNAMENT_HTML_DIR;
    my $player_dir     = Constants::PLAYER_HTML_DIR;
    my $rankings_dir   = Constants::RANKINGS_HTML_DIR;
    my $trigraph_hashref = Constants::COUNTRY_TRIGRAPH_TO_COUNTRY_NAME_HASHREF;

    if ($key eq 'tr_tournament_name')
    {
      $val = Utils::make_link($base_dir, $tournament_dir, $item->{'t_id'} . ".html", $val);
    }
    elsif ($key eq 'opp_name')
    {
      $val = Utils::make_link($base_dir, $player_dir, $item->{'opp_id'} . ".html", $val);
    }
    elsif ($key eq 'tr_player_name')
    {
      $val = Utils::make_link($base_dir, $player_dir, $item->{'tr_player_id'} . ".html", $val);
    }
    elsif ($key eq 'name')
    {
      $val = Utils::make_link($base_dir, $player_dir, $item->{'id'} . ".html", $val);
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
      $val = "";
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

  for (my $i = 0; $i < $content_length; $i++)
  {
    my $text = $content->[$i]->[0];
    my $id   = $content->[$i]->[1];
    my $width = 100 / $content_length;
    $div .= "<button id='button_" . $id . "' style='width: $width%' class='$linkclass' onclick=\"showContent(event, '$id', '$tabclass', '$linkclass')\">$text</button>";
  }
  $div .= "</div><br>";
  return $div;
}

sub negative_one_if_false
{
  my $s = shift;
  if ($s)
  {
    return $s;
  }
  return -1;
}

sub player_name_is_bye
{
  my $name = shift;

  $name = Utils::sanitize($name);

  if ($name eq "RUSSELLBYERS")
  {
    return 0;
  }

  return ($name =~ /BYE/);
}

sub populate_alt_names_hash
{
  my $dup_filename = Constants::INPUT_DIR . "/" . Constants::INPUT_MERGE_FILE;

  my $alt_names_hash = {};

  open(DUP, "<", $dup_filename);

  while(<DUP>)
  {
    chomp $_;

    $_ =~ s/^\s+|\s+$//g;

    if ($_ =~ /^#/ || !$_){next;}

    my @names = split /,/, $_;

    @names = map { $_ =~ s/^\s+|\s+$//gr  } @names;

    if (!@names){next;}

    my $true_name = shift @names;

    foreach my $alt_name (@names)
    {
      if ($alt_names_hash->{$alt_name})
      {
        print "ERROR:    alt name already mapped\n";
        print "Alt name: $alt_name\n";
        die;
      }
      $alt_names_hash->{$alt_name} = $true_name;
    }
  }
  return $alt_names_hash;
}

sub populate_deceased_players_hash
{
  my $alt_names_hash = shift;
  my $deceased_players_filename = Constants::INPUT_DIR . "/" .
                                  Constants::DECEASED_PLAYERS;
  
  my $deceased_players_hash = {};

  open(DECEASED, "<", $deceased_players_filename);
  while(<DECEASED>)
  {
    chomp $_;
    $_ =~ s/^\s+|\s+$//g;

    my $true_name = $_;
    my $alt_name  = $alt_names_hash->{$_};

    if ($alt_name)
    {    
      $true_name = $alt_name;
    }    

    $deceased_players_hash->{$_} = 1; 
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

  my $query_result = $dbh->selectall_arrayref($query, {Slice => {}, "RaiseError" => 1});

  return $query_result;
}

sub tou_is_loaded
{
  my $dbh = shift;
  my $tou = shift;

  my $loaded_tournaments_tn = Constants::LOADED_TOURNAMENTS_TABLE_NAME;

  my $tou_query = "SELECT * FROM $loaded_tournaments_tn WHERE filename=\"$tou\"";

  my @tou_query_result = $dbh->selectrow_array($tou_query, {"RaiseError" => 1});

  my $is_loaded = 0;

  if (@tou_query_result)
  {
    $is_loaded = 1;
  }

  return $is_loaded;
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

  for (my $i = 0; $i < scalar @ranked_tournament_results; $i++)
  {
    $ranked_tournament_results[$i]->{'position'} = $i + 1;
  }
  return @ranked_tournament_results;
}

sub record_database
{
  my $dbh = shift;

  my $maybe_dev     = Utils::get_environment_name('');
  my $database_name = Utils::get_environment_name(Constants::DATABASE_NAME);
  my $host_name     = Constants::DATABASE_HOST_NAME;
  my $user_name     = Constants::DATABASE_USER_NAME;
  my $password      = Constants::DATABASE_PASSWORD;
  
  my $logs          = Constants::LOG_DIR;
  my $players_tn    = Constants::PLAYERS_TABLE_NAME;
  my $working_dir   = Constants::DEFAULT_WORKING_DIR;

  my @t = localtime;
  $t[5] += 1900;
  $t[4]++;

  my $tstamp = sprintf "%04d_%02d_%02d", @t[5,4,3];

  my $dumpfile = 'mysqldump_' . $database_name . '_' . $tstamp;

  my $dump_cmd = "mysqldump -u $user_name --password='$password' $database_name $players_tn > $logs/$dumpfile";

  system $dump_cmd;
 
  my @players = @{$dbh->selectall_arrayref("SELECT name, id FROM $players_tn", {"RaiseError" => 1} )};

  my $player_ids = join "\n", (map {$_->[0] . ', ' . $_->[1]} @players) ;
  open(my $fh, '>', "$logs/player_ids_$database_name" . "$tstamp.txt");
  print $fh $player_ids;
  close $fh;

  if ($maybe_dev)
  {
    $maybe_dev = '_' . $maybe_dev;
  }

  open(my $fh_cur, '>', "$working_dir/player_ids$maybe_dev.txt");
  print $fh_cur $player_ids;
  close $fh_cur;
}

sub sanitize
{
  my $name = shift;
  
  $name = uc $name;

  $name =~ s/[^A-Z]//g;

  return $name;
}

sub set_current_status
{
  my $dbh = shift;

  my $players_tn        = Constants::PLAYERS_TABLE_NAME;
  my $current_games_min = Constants::CURRENT_GAMES_MIN;
  
  my $database_name = Utils::get_environment_name(Constants::DATABASE_NAME);
  my $host_name     = Constants::DATABASE_HOST_NAME;
  my $user_name     = Constants::DATABASE_USER_NAME;
  my $password      = Constants::DATABASE_PASSWORD;
  
  my $datestring = localtime();
  my $epoc = time();
  $epoc = $epoc - (24 * 60 * 60 * 365 * 2);   # two years before current date.
  
  my @t = localtime($epoc);
  $t[5] += 1900;
  $t[4]++;
  
  my $date_two_years_ago = sprintf "%04d-%02d-%02d", @t[5,4,3];

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

  $dbh->do($update_current, {"RaiseError" => 1});
}

sub set_provisional_status
{
  my $dbh = shift;
  my $players_tn            = Constants::PLAYERS_TABLE_NAME;
  my $provisional_games_max = Constants::PROVISIONAL_GAMES_MAX;

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
  $dbh->do($update_provisional, {"RaiseError" => 1});
}

sub stat_objects
{
  my $game_stats_rank_name = Constants::GAME_STATS_RANK_NAME;
  my $stat_key_name        = Constants::STAT_KEY_NAME;
  my $tournament_stats =
    {
      'High Win' =>
      {
        'cond' =>
        sub
        {
          my $data = shift;
          return $data->{'pr1_score'} > $data->{'pr2_score'} && $data->{'opp_rating'} > 500;
        },
        'eval' =>
        sub
        {
          my $data = shift;
          return $data->{'pr1_score'};
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
          return $data->{'pr1_score'} < $data->{'pr2_score'};
        },
        'eval' =>
        sub
        {
          my $data = shift;
          return $data->{'pr1_score'};
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
          return $data->{'pr1_score'} > $data->{'pr2_score'}
        },
        'eval' =>
        sub
        {
          my $data = shift;
          return $data->{'pr1_score'} - $data->{'pr2_score'};
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
          return $data->{'pr1_score'} + $data->{'pr2_score'};
        },
        'sort' =>
        sub
        {
          my $c1 = shift;
          my $c2 = shift;
          $c2->{$stat_key_name} <=> $c1->{$stat_key_name}
        },
        'titles' => ['Rank', 'Players', '', 'Combined Score', 'Round'],
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
}

sub get_country_from_filename
{
  my $filename = shift;
  my @filename_items = split /\//, $filename;
  return $filename_items[-2];
}

sub uniq
{
  my $array_ref = shift;
  my @array = @{$array_ref};
  my $hashref = map { $_ => 1 } @array;
  return keys %{$hashref};
}

sub write_string_to_file
{
  my $string   = shift;
  my $filename = shift;

  open(my $fh, '>', $filename);
  print $fh $string;
  close $fh; 
}

1;
