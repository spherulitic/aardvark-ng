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

sub add_games_to_existing_player
{
  my $dbh          = shift;
  my $player_id    = shift;
  my $games_played = shift;

  my $total_games_update
    = "UPDATE $PLAYERS_TABLE_NAME "
    . "SET total_games = total_games + $games_played WHERE id=$player_id";
  $dbh->do( $total_games_update, { RaiseError => 1 } );
  return $dbh->last_insert_id( undef, undef, undef, undef );
}

sub backup_years
{
  my $base_directory_name = shift;
  my $backup_dir          = shift;

  mkdir $backup_dir;

  $base_directory_name .= q{/};

  my @tournament_data_filenames = ();

  opendir my $base_directory, $base_directory_name
    or croak "Cannot open $base_directory_name: $OS_ERROR";
  my @year_directory_names
    = grep {/$DEFAULT_YEAR_REGEX/xms} readdir $base_directory;

  foreach my $year_directory_name (@year_directory_names)
  {
    my $year_directory_full_path_name
      = $base_directory_name . $year_directory_name;
    system "cp -r $year_directory_full_path_name $backup_dir";
  }
  return \@tournament_data_filenames;
}

sub check_country_flag_icons
{
  my $country_ref    = shift;
  my @countries      = @{$country_ref};
  my $warning_string = $EMPTY_STRING;

  opendir my $flag_dir_handle, $COUNTRY_FLAGS_DIR
    or croak "Cannot open  $COUNTRY_FLAGS_DIR: $OS_ERROR$NEWLINE";
  my @existing_flags = grep {/\w{3}[.]png/xms} readdir $flag_dir_handle;

  foreach my $ef (@existing_flags)
  {
    $ef =~ /(\w{3})/xms;
    if ( !$COUNTRY_TRIGRAPH_TO_COUNTRY_NAME_HASHREF->{$1} )
    {
      $warning_string .= Utils::format_error(
        [ [ 'WARNING', 'Invalid flag image name' ], [ 'File', $ef ] ] );
    }
  }

  my $extension = '.png';

  foreach my $country (@countries)
  {
    my $flag = $COUNTRY_FLAGS_DIR . q{/} . $country . $extension;
    if ( !( -e $flag ) )
    {
      $warning_string .= Utils::format_error(
        [ [ 'WARNING',      'Missing flag image' ],
          [ 'Country',      $country ],
          [ 'Missing File', $flag ],
        ]
      );
    }
  }
  return $warning_string;
}

sub compare_names
{
  my $tou_ref = shift;
  my $st_ref  = shift;

  my $not_in_tou = $EMPTY_STRING;
  my $not_in_st  = $EMPTY_STRING;

  foreach my $tou_key ( keys %{$tou_ref} )
  {
    if ( !( $st_ref->{$tou_key} ) && !Utils::player_name_is_bye($tou_key) )
    {
      $not_in_st .= $tou_key . ', ';
    }
  }

  foreach my $st_key ( keys %{$st_ref} )
  {
    if ( !$tou_ref->{$st_key} && !Utils::player_name_is_bye($st_key) )
    {
      $not_in_tou .= $st_key . ', ';
    }
  }

  if ( $not_in_tou || $not_in_st )
  {
    return [ $not_in_tou, $not_in_st ];
  }
  return 1;

}

sub connect_to_database
{
  my $database_name = Utils::get_environment_name($DATABASE_NAME);

  my $dbh
    = DBI->connect(
    "DBI:mysql:database=$database_name;host=$DATABASE_HOST_NAME",
    $DATABASE_USER_NAME, $DATABASE_PASSWORD, { RaiseError => 1 } );
  return $dbh;
}

sub convert_name
{
  my $name           = shift;
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
  my $trigraph          = shift;
  my $correct_trigraph  = $EMPTY_STRING;
  my $trigraph_warnings = $EMPTY_STRING;

  if ($trigraph)
  {
    if ( $COUNTRY_TRIGRAPH_TO_COUNTRY_NAME_HASHREF->{$trigraph} )
    {
      $correct_trigraph = $trigraph;
    }
    else
    {
      $correct_trigraph = $COUNTRY_TRIGRAPH_CONVERSION->{$trigraph};
    }

    if ( !$correct_trigraph )
    {
      $correct_trigraph = $DEFAULT_UNKNOWN_COUNTRY_TRIGRAPH;
    }
  }

  if ( !$trigraph || $correct_trigraph eq $DEFAULT_UNKNOWN_COUNTRY_TRIGRAPH )
  {
    $trigraph_warnings .= Utils::format_error(
      [ [ 'WARNING',  'Uncorrected country trigraph' ],
        [ 'Trigraph', $trigraph ],
      ]
    );
  }

  return ( $correct_trigraph, $trigraph_warnings );
}

sub convert_trigraph_to_country
{
  # Assumes a corrected trigraph
  my $trigraph = shift;

  my $country = $COUNTRY_TRIGRAPH_TO_COUNTRY_NAME_HASHREF->{$trigraph};
  if ( !$country )
  {
    $country = $DEFAULT_UNKNOWN_COUNTRY;
  }
  return $country;
}

sub copy_database_to_production
{
  my $production_database_name
    = Utils::get_environment_name($PRODUCTION_DATABASE_NAME);

  my $database_name = Utils::get_environment_name($DATABASE_NAME);

  system "echo 'DROP DATABASE IF EXISTS $production_database_name' | "
    . " mysql -u $DATABASE_USER_NAME --password='$DATABASE_PASSWORD'";
  system "echo 'CREATE DATABASE         $production_database_name' | "
    . "mysql -u $DATABASE_USER_NAME --password='$DATABASE_PASSWORD'";
  system "mysqldump -u  $DATABASE_USER_NAME --password='$DATABASE_PASSWORD' "
    . " $database_name | mysql -u $DATABASE_USER_NAME "
    . "--password='$DATABASE_PASSWORD' $production_database_name";
  return 1;
}

sub create_html_id
{
  my $html_element = shift;
  my $type         = shift;
  my $id           = shift;

  return ( join q{_}, ( $html_element, $type, $id ) );
}

sub determine_item_class
{
  my $key = shift;

  my $wins_column   = q{class='winscolumn'};
  my $losses_column = q{class='lossescolumn'};
  my $draws_column  = q{class='drawscolumn'};
  my $byes_column   = q{class='byescolumn'};

  my %class_hash = (
    tr_wins   => $wins_column,
    hh_wins   => $wins_column,
    tr_losses => $losses_column,
    hh_losses => $losses_column,
    hh_draws  => $draws_column,
    tr_byes   => $byes_column,
  );
  my $class_string = $class_hash{$key};
  if ( !$class_string )
  {
    $class_string = $EMPTY_STRING;
  }
  return $class_string;
}

sub determine_item_value
{
  my $arg_ref = shift;

  my $key       = $arg_ref->{key};
  my $raw_value = $arg_ref->{raw_value};
  my $item      = $arg_ref->{item};

  if ( !defined $raw_value )
  {
    return $EMPTY_STRING;
  }

  my $base_dir = $DEFAULT_SHORT_NAME_WORKING_DIR . q{/} . $HTML_DIR;

  my %value_hash = (
    tr_tournament_name => [ $TOURNAMENT_HTML_DIR, 't_id' ],
    opp_name           => [ $PLAYER_HTML_DIR,     'opp_id' ],
    tr_player_name     => [ $PLAYER_HTML_DIR,     'tr_player_id' ],
    name               => [ $PLAYER_HTML_DIR,     'id' ],
  );

  my $value = $raw_value;

  my $link_info = $value_hash{$key};

  if ($link_info)
  {
    $value = Utils::make_link( $base_dir, $link_info->[0],
      $item->{ $link_info->[1] } . '.html', $raw_value );
  }
  elsif ( $key eq 'p_country' || $key eq 'country' )
  {
    my $trigraph = $item->{$key};
    my $country  = Utils::convert_trigraph_to_country($trigraph);
    if ( $country ne $DEFAULT_UNKNOWN_COUNTRY )
    {
      $value
        = Utils::make_link( $base_dir, $RANKINGS_HTML_DIR, "$trigraph.html",
        $country );
    }
  }
  return $value;
}

sub drop_all_wespa_tables
{
  my $dbh            = shift;
  my $alt_names_hash = shift;

  my $database_name = Utils::get_environment_name($DATABASE_NAME);

  foreach my $table ( reverse @{$TABLE_CREATION_ORDER} )
  {
    if ( !$TABLE_DROP_EXCEPTIONS->{$table} )
    {
      $dbh->do("DROP TABLE IF EXISTS $table");
    }
  }

  foreach my $key ( keys %{$alt_names_hash} )
  {
    $key =~ s/'/''/gxms;
    my $delete_redundant_players
      = "DELETE FROM $PLAYERS_TABLE_NAME WHERE name = '$key'";
    $dbh->do( $delete_redundant_players, { RaiseError => 1 } );
  }

  my $reset_games_played
    = "UPDATE $PLAYERS_TABLE_NAME AS p SET p.total_games = 0";

  $dbh->do( $reset_games_played, { RaiseError => 1 } );

  my $reset_last_played
    = "UPDATE $PLAYERS_TABLE_NAME AS p SET p.last_played = '0001-01-01'";

  $dbh->do( $reset_last_played, { RaiseError => 1 } );

  return 1;
}

sub empty_string_if_nonpositive
{
  my $num = shift;
  if ( !$num || $num <= 0 )
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
  my $scratch_dir = Utils::get_environment_name($TOURNAMENT_DATA_DIR);

  Utils::execute_command("mkdir -p $scratch_dir");

  my @localtime_data = localtime;
  my $current_year
    = $localtime_data[$LOCALTIME_YEAR_INDEX] + $LOCALTIME_YEAR_BASE;

  for my $year ( $UPDATE_START_YEAR .. $current_year )
  {
    my $rf_cmd = "rm -rf $scratch_dir/$year";
    Utils::execute_command($rf_cmd);
    if ( -e "$UPDATE_SOURCE_DIR/$year" )
    {
      my $cp_cmd = "cp -r $UPDATE_SOURCE_DIR/$year $scratch_dir/";
      Utils::execute_command($cp_cmd);
    }
  }
  return 1;
}

sub format_error
{
  my $error_arrayref = shift;

  my $l                = scalar @{$error_arrayref};
  my $error_string     = $EMPTY_STRING;
  my $max_field_length = 0;

  for my $i ( 0 .. $l - 1 )
  {
    my $item1        = $error_arrayref->[$i]->[0];
    my $item1_length = length $item1;

    if ( $item1_length > $max_field_length )
    {
      $max_field_length = $item1_length;
    }
  }

  for my $i ( 0 .. $l - 1 )
  {
    my $item1 = $error_arrayref->[$i]->[0];
    my $item2 = $error_arrayref->[$i]->[1];

    if ( !$item1 ) { $item1 = 'undef'; }
    if ( !$item2 ) { $item2 = 'undef'; }

    $error_string
      .= ( sprintf q{%-} . ( $max_field_length + 2 ) . q{s}, $item1 . q{:} )
      . $item2
      . "$NEWLINE";
  }
  $error_string .= "$NEWLINE";
  return $error_string;
}

sub format_print
{
  my $input = shift;

  my @strings;

  if ( ref $input eq $PERL_ARRAY_REF_NAME )
  {
    @strings = @{$input};
  }
  else
  {
    @strings = ($input);
  }

  my $string = shift @strings;

  while ($string)
  {
    print $string or croak "Cannot print to STDOUT: $OS_ERROR$NEWLINE";
    $string = shift @strings;
  }

  return 1;
}

sub get_country_from_filename
{
  my $filename       = shift;
  my @filename_items = split /\//xms, $filename;
  return $filename_items[$COUNTRY_IN_FILENAME_INDEX];
}

sub get_environment_name
{
  my $name = shift;
  my $dir  = Cwd::getcwd();
  if ( $dir =~ /$DEV_ENV_KEYWORD/ixms )
  {
    return $name . $DEV_ENV_KEYWORD;
  }
  return $name;
}

sub get_iso_date
{
  my $time      = shift;
  my $separator = shift;

  my @t = localtime $time;
  $t[$LOCALTIME_YEAR_INDEX] += $LOCALTIME_YEAR_BASE;
  $t[$LOCALTIME_MONTH_INDEX]++;

  return sprintf "%04d$separator%02d$separator%02d",
    @t[ $LOCALTIME_YEAR_INDEX, $LOCALTIME_MONTH_INDEX, $LOCALTIME_DAY_INDEX ];
}

sub get_most_recent_tournament
{
  my $dbh      = shift;
  my $trigraph = shift;

  my $query;

  if ($trigraph)
  {
    $query
      = 'SELECT t.id AS id, t.name AS name '
      . "FROM $TOURNAMENT_RESULTS_TABLE_NAME AS tr, "
      . "$PLAYERS_TABLE_NAME AS p, "
      . "$DIVISIONS_TABLE_NAME AS d, "
      . "$TOURNAMENTS_TABLE_NAME AS t " . 'WHERE'
      . '      d.tournament_id = t.id        AND '
      . '      tr.division_id  = d.id        AND '
      . '      tr.player_id    = p.id        AND '
      . "      p.country       = '$trigraph' AND "
      . '      p.deceased      = 0           AND '
      . '      p.suspended     = 0           AND '
      . '      p.current       = 1 '
      . 'ORDER BY t.end_date DESC';
  }
  else
  {
    $query
      = 'SELECT id, name '
      . "FROM $TOURNAMENTS_TABLE_NAME "
      . 'GROUP BY end_date DESC';
  }
  my @tournament_name
    = @{ $dbh->selectall_arrayref( $query, { RaiseError => 1 } ) };
  return [ $tournament_name[0]->[0], $tournament_name[0]->[1] ];

}

sub get_perl_files
{
  my @files = ();

  foreach my $dir ( @{$PERL_DIRECTORIES} )
  {
    my $fh_dir;
    opendir $fh_dir, $dir;
    push @files,
      map { $dir . q{/} . $_ } ( grep {/[.]p[ml]/xms} readdir $fh_dir );
  }
  return @files;
}

sub get_player_photo
{
  my $name = shift;

  my $photo_dir
    = Utils::get_environment_name($DEFAULT_WORKING_DIR) . q{/} . $PHOTO_DIR;

  $name =~ s/\s//gxms;

  $name = lc $name;

  my $filename = $photo_dir . q{/} . $name . '.jpg';

  if ( -e $filename )
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
  my @year_directory_names = grep {/$year_regex/xms} readdir $base_directory;

  @year_directory_names = sort { $a <=> $b } @year_directory_names;

  for my $i ( 0 .. scalar @year_directory_names - 1 )
  {
    my $year_directory_name = $year_directory_names[$i];
    my $year_directory_full_path_name
      = $base_directory_name . $year_directory_name;

    opendir my $year_directory, $year_directory_full_path_name
      or croak "Cannot open $year_directory_full_path_name: $OS_ERROR";

    my @country_trigraphs
      = grep {/$country_trigraph_regex/xms} readdir $year_directory;

    foreach my $country_trigraph (@country_trigraphs)
    {
      my $trigraph_directory_full_path_name
        = $year_directory_full_path_name . q{/} . $country_trigraph;

      opendir my $trigraph_directory, $trigraph_directory_full_path_name
        or croak "Cannot open $trigraph_directory_full_path_name: $OS_ERROR";

      my @filenames = grep {/$file_regex/ixms} readdir $trigraph_directory;

      my @full_filenames
        = map { $trigraph_directory_full_path_name . q{/} . $_ } @filenames;

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

  my %tables         = %{$tables_ref};
  my @creation_order = @{$creation_order_ref};

  for my $i ( 0 .. scalar @creation_order - 1 )
  {
    my $key     = $creation_order[$i];
    my @columns = @{ $tables{$key} };

    my $columns_string = join ', ', @columns;

    my $statement = "CREATE TABLE IF NOT EXISTS $key ($columns_string)";

    $dbh->do($statement);
  }

  my $lexicons    = $LEXICONS;
  my $lexicons_tn = $LEXICONS_TABLE_NAME;

  Utils::insert_hash_list_into_table( $dbh, $lexicons_tn, $lexicons, 'name' );
  return 1;
}

sub insert_hash_into_table
{
  my $dbh     = shift;
  my $table   = shift;
  my $hashref = shift;

  my $keys_string   = q{(};
  my $values_string = q{(};

  foreach my $key ( keys %{$hashref} )
  {
    if ( defined $hashref->{$key} )
    {
      $keys_string   .= "$key,";
      $values_string .= "\"$hashref->{$key}\",";
    }
  }

  chop $keys_string;
  chop $values_string;

  if ( !$keys_string || !$values_string )
  {
    return;
  }

  $keys_string   .= q{)};
  $values_string .= q{)};
  my $insert_statement
    = "INSERT INTO $table $keys_string VALUE $values_string;";

  $dbh->do( $insert_statement, { RaiseError => 1 } );
  return $dbh->last_insert_id( undef, undef, undef, undef );
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
    my $id = Utils::insert_hash_into_table( $dbh, $table, $item );
    if ($last_insert_id_key_field)
    {
      $last_insert_id_hash->{ $item->{$last_insert_id_key_field} } = $id;
    }
  }
  return $last_insert_id_hash;
}

sub is_command
{
  my $filename = shift;
  $filename =~ s/^\s+|\s+$//gxms;
  my $filename_length = length $filename;
  return ( substr $filename, $filename_length - 1, $filename_length ) eq q{|};
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
  my $arg_ref = shift;

  my $games_ref       = $arg_ref->{games_ref};
  my $keys_ref        = $arg_ref->{keys_ref};
  my $row_class       = $arg_ref->{row_class};
  my $entry_id        = $arg_ref->{entry_id};
  my $title_length    = $arg_ref->{title_length};
  my $games_title_row = $arg_ref->{games_title_row};

  my $new_entry = $EMPTY_STRING;

  $new_entry .= Utils::make_row({
    item  => $games_ref->[0],
    keys  => $keys_ref,
    class => $row_class
  });

  $new_entry
    .= q{<tr style='border: none'>}
    . q{<td style='padding: 0px; border: 0px'></td>}
    . q{<td style='padding: 0px; border: 0px'  colspan='}
    . ( $title_length - 1 )
    . "'><div class='collapse' id='$entry_id'>"
    . "<table class='table'>$NEWLINE";

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
  my $arg_ref = shift;

  my $item     = $arg_ref->{item};
  my $keys     = $arg_ref->{keys};
  my $is_title = $arg_ref->{is_title};
  my $id       = $arg_ref->{id};
  my $class    = $arg_ref->{class};
  my $colspan  = $arg_ref->{colspan};

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
  for my $i ( 0 .. scalar @key_array - 1 )
  {
    my $key = $key_array[$i];
    my $val = $key;

    if ( !$is_title )
    {
      $val = $item->{$key};
    }

    $val = Utils::determine_item_value(
      { key => $key, raw_value => $val, item => $item } );
    $class = Utils::determine_item_class($key);

    $row_string .= sprintf "<$el $colspan_attr $class >%s</$el>", $val;
  }
  $row_string .= "</tr>$NEWLINE";

  return $row_string;
}

sub make_tab_div
{
  my $content   = shift;
  my $tabclass  = shift;
  my $linkclass = shift;

  my $content_length = scalar @{$content};

  my $div = "<br><div class='tab'>$NEWLINE";

  for my $i ( 0 .. $content_length - 1 )
  {
    my $text  = $content->[$i]->[0];
    my $id    = $content->[$i]->[1];
    my $width = $FULL_WIDTH / $content_length;
    $div
      .= q{<button id='button_}
      . $id
      . "' style='width: $width%' "
      . "class='$linkclass' "
      . "onclick=\"showContent(event, '$id', '$tabclass', '$linkclass')\">"
      . $text
      . '</button>';
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

sub parse_tou_header
{
  my $filename = shift;

  my $date;
  my $tournament_name;

  open my $tou_read, q{<}, $filename
    or croak "Cannot open .tou file $filename: $OS_ERROR";
  my $first_line = <$tou_read>;
  close $tou_read or croak "Cannot close .tou file $filename: $OS_ERROR";
  chomp $first_line;
  $first_line =~ s/[\r]//gxms;

  if ( $first_line =~ /^[*] . (\d\d) . (\d\d) . (\d\d\d\d) [ ] (.*)$/xms )
  {
    $date            = $3 . $2 . $1;
    $tournament_name = $4;
  }

  return ( $date, $tournament_name );
}

sub player_name_is_bye
{
  my $name = shift;

  $name = Utils::sanitize($name);
  if ( $name eq 'RUSSELLBYERS' )
  {
    return 0;
  }
  my $is_bye = $name =~ /BYE/ixms;
  return $is_bye;
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

    if ( $dl =~ /^[#]/xms || !$dl ) { next; }

    my @names = split /,/xms, $dl;

    for my $i ( 0 .. scalar @names - 1 )
    {
      my $trimmed_name = $names[$i];
      $trimmed_name =~ s/^\s+|\s+$//gxms;
      $names[$i] = $trimmed_name;
    }

    if ( !@names ) { next; }

    my $true_name = shift @names;

    foreach my $alt_name (@names)
    {
      if ( $alt_names_hash->{$alt_name} )
      {
        croak Utils::format_error(
          [ [ 'ERROR',            'alternative name already mapped' ],
            [ 'Alternative name', $alt_name ]
          ]
        );
      }
      $alt_names_hash->{$alt_name} = $true_name;
    }
  }
  return $alt_names_hash;
}

sub populate_deceased_players_hash
{
  my $alt_names_hash            = shift;
  my $deceased_players_filename = $INPUT_DIR . q{/} . $DECEASED_PLAYERS;

  my $deceased_players_hash = {};

  my @deceased_lines = Utils::write_file_to_array($deceased_players_filename);
  while (@deceased_lines)
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

  my $query_result
    = $dbh->selectall_arrayref( $query, { Slice => {}, RaiseError => 1 } );

  return $query_result;
}

sub rank_tournament_results
{
  my $tournament_results_ref = shift;

  my @tournament_results = @{$tournament_results_ref};

  my @ranked_tournament_results = reverse sort {
         $a->{wins} + $a->{bye_wins} <=> $b->{wins} + $b->{bye_wins}
      || $a->{spread} <=> $b->{spread}
  } @tournament_results;

  for my $i ( 0 .. scalar @ranked_tournament_results - 1 )
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

  my $tstamp = get_iso_date( time(), q{_} );

  my $dumpfile = 'mysqldump_' . $database_name . q{_} . $tstamp;

  my $dump_cmd
    = "mysqldump -u $DATABASE_USER_NAME --password='$DATABASE_PASSWORD' "
    . " $database_name $PLAYERS_TABLE_NAME > $LOG_DIR/$dumpfile";

  system $dump_cmd;

  my @players = @{
    $dbh->selectall_arrayref( "SELECT name, id FROM $PLAYERS_TABLE_NAME",
      { RaiseError => 1 } )
  };

  my $player_ids = join "$NEWLINE",
    ( map { $_->[0] . ', ' . $_->[1] } @players );

  Utils::write_string_to_file( $player_ids,
    "$LOG_DIR/player_ids_$database_name" . "$tstamp.txt" );

  if ($maybe_dev)
  {
    $maybe_dev = q{_} . $maybe_dev;
  }

  Utils::write_string_to_file( $player_ids,
    "$DEFAULT_WORKING_DIR/player_ids$maybe_dev.txt" );

  return 1;
}

sub sanitize
{
  my $name = shift;

  if ($name)
  {
    $name = uc $name;
    $name =~ s/\W//gxms;
  }

  return $name;
}

sub set_current_status
{
  my $dbh = shift;

  my $database_name = Utils::get_environment_name($DATABASE_NAME);
  my $datestring    = localtime;
  my $epoc          = time;

  $epoc -= $TWO_YEARS_IN_SECONDS;    # two years before current date.

  my $date_two_years_ago = get_iso_date( $epoc, q{-} );

  my $games_in_last_two_years
    = '(SELECT SUM(tr.wins + tr.losses) '
    . 'FROM tournaments AS t, divisions AS d, tournament_results AS tr '
    . 'WHERE p.id = tr.player_id AND '
    . '      tr.division_id = d.id AND '
    . "      d.tournament_id = t.id AND t.end_date > '$date_two_years_ago')";

  my $update_current
    = "UPDATE $PLAYERS_TABLE_NAME AS p "
    . 'SET p.current = '
    . '(CASE ' . 'WHEN '
    . "$games_in_last_two_years > 0 AND "
    . "p.total_games > $CURRENT_GAMES_MIN "
    . 'THEN 1 '
    . 'ELSE 0 ' . 'END)';

  $dbh->do( $update_current, { RaiseError => 1 } );

  return 1;
}

sub set_provisional_status
{
  my $dbh = shift;

  # Update provisional status for all players
  my $update_provisional
    = "UPDATE $PLAYERS_TABLE_NAME AS p "
    . 'SET p.provisional = '
    . '(CASE '
    . "WHEN p.total_games <  $PROVISIONAL_GAMES_MAX "
    . 'THEN 1 '
    . 'ELSE 0 ' . 'END)';

  $dbh->do( $update_provisional, { RaiseError => 1 } );

  return 1;
}

sub stat_objects
{
  my $tournament_stats = {
    'High Win' => {
      cond => sub {
        my $data = shift;
        return $data->{pr1_score} > $data->{pr2_score}
          && $data->{opp_rating} > $WESPA_START_RATING;
      },
      eval => sub {
        my $data = shift;
        return $data->{pr1_score};
      },
      sort => sub {
        my $c1 = shift;
        my $c2 = shift;
        $c2->{$STAT_KEY_NAME} <=> $c1->{$STAT_KEY_NAME};
      },
      titles => [ 'Rank', 'Player', 'Score', 'Opponent', 'Round' ],
      values => [
        $GAME_STATS_RANK_NAME, 'tr_player_name',
        $STAT_KEY_NAME,        'opp_name',
        'g_round'
      ],
      list => []
    },
    'High Loss' => {
      cond => sub {
        my $data = shift;
        return $data->{pr1_score} < $data->{pr2_score};
      },
      eval => sub {
        my $data = shift;
        return $data->{pr1_score};
      },
      sort => sub {
        my $c1 = shift;
        my $c2 = shift;
        $c2->{$STAT_KEY_NAME} <=> $c1->{$STAT_KEY_NAME};
      },
      titles => [ 'Rank', 'Player', 'Score', 'Opponent', 'Round' ],
      values => [
        $GAME_STATS_RANK_NAME, 'tr_player_name',
        $STAT_KEY_NAME,        'opp_name',
        'g_round'
      ],
      list => []
    },
    'High Spread' => {
      cond => sub {
        my $data = shift;
        return $data->{pr1_score} > $data->{pr2_score};
      },
      eval => sub {
        my $data = shift;
        return $data->{pr1_score} - $data->{pr2_score};
      },
      sort => sub {
        my $c1 = shift;
        my $c2 = shift;
        $c2->{$STAT_KEY_NAME} <=> $c1->{$STAT_KEY_NAME};
      },
      titles => [
        'Rank',           'Player', 'Opponent', 'Player Score',
        'Opponent Score', 'Spread', 'Round'
      ],
      values => [
        $GAME_STATS_RANK_NAME, 'tr_player_name',
        'opp_name',            'pr1_score',
        'pr2_score',           $STAT_KEY_NAME,
        'g_round'
      ],
      list => []
    },
    'High Combined' => {
      cond => sub {
        my $data = shift;

        # Ensure only one instance gets reported
        return $data->{tr_player_id} > $data->{opp_id};
      },
      eval => sub {
        my $data = shift;
        return $data->{pr1_score} + $data->{pr2_score};
      },
      sort => sub {
        my $c1 = shift;
        my $c2 = shift;
        $c2->{$STAT_KEY_NAME} <=> $c1->{$STAT_KEY_NAME};
      },
      titles =>
        [ 'Rank', 'Players', $EMPTY_STRING, 'Combined Score', 'Round' ],
      values => [
        $GAME_STATS_RANK_NAME, 'tr_player_name',
        'opp_name',            $STAT_KEY_NAME,
        'g_round'
      ],
      list => []
    },
    'Upsets' => {
      cond => sub {
        my $data = shift;
        return
             $data->{tr_start_rating}
          && $data->{opp_rating}
          && $data->{tr_start_rating} > 0
          && $data->{opp_rating} > 0
          && $data->{opp_rating} < $data->{tr_start_rating}
          && $data->{pr2_score} > $data->{pr1_score};
      },
      eval => sub {
        my $data = shift;
        return $data->{tr_start_rating} - $data->{opp_rating};
      },
      sort => sub {
        my $c1 = shift;
        my $c2 = shift;
        $c2->{$STAT_KEY_NAME} <=> $c1->{$STAT_KEY_NAME};
      },
      titles => [
        'Rank',            'Player',
        'Player Rating',   'Opponent',
        'Opponent Rating', 'Rating Difference',
        'Round'
      ],
      values => [
        $GAME_STATS_RANK_NAME, 'tr_player_name',
        'tr_start_rating',     'opp_name',
        'opp_rating',          $STAT_KEY_NAME,
        'g_round'
      ],
      list => []
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

  my $tou_query
    = "SELECT * FROM $LOADED_TOURNAMENTS_TABLE_NAME WHERE filename=\"$tou\"";

  my @tou_query_result
    = $dbh->selectrow_array( $tou_query, { RaiseError => 1 } );

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
  my %hash = ();
  foreach my $value (@{$array_ref})
  {
    $hash{$value} = 1;
  }
  return keys %hash;
}

sub update_record_by_id
{
  my $dbh             = shift;
  my $table_name      = shift;
  my $id              = shift;
  my $fields_hash_ref = shift;

  foreach my $key ( keys %{$fields_hash_ref} )
  {
    my $value  = $fields_hash_ref->{$key};
    my $update = "UPDATE $table_name SET $key = '$value' WHERE id=$id";
    $dbh->do( $update, { RaiseError => 1 } );
  }

  return 1;
}

sub write_file_to_array
{
  my $filename = shift;
  open my $fh, q{<}, $filename
    or croak "Cannot open file $filename: $OS_ERROR$NEWLINE";
  my @array = <$fh>;
  close $fh or croak "Cannot close file $filename: $OS_ERROR$NEWLINE";
  return @array;
}

sub write_file_to_string
{
  my $file = shift;
  my $string;

  $string = $EMPTY_STRING;
  my @file_array = Utils::write_file_to_array($file);
  while (@file_array)
  {
    $string .= shift @file_array;
  }

  return $string;
}

sub write_string_to_file
{
  my $string   = shift;
  my $filename = shift;

  open my $fh, q{>}, $filename
    or croak "Cannot open $filename: $OS_ERROR$NEWLINE";
  print {$fh} $string or croak "Cannot print to $filename: $OS_ERROR$NEWLINE";
  close $fh or croak "Cannot close $filename: $OS_ERROR$NEWLINE";

  return 1;
}

1;
