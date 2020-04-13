#!/usr/bin/perl

package Update;

use strict;
use warnings;
use version; our $VERSION = qv('1');
use DBI;
use Carp;
use Data::Dumper;
use Getopt::Long;

use lib './modules';
use lib './objects';
use Constants;
use Utils;
use TOU;
use HTML;

if ( !caller )
{
  my $executive_key;

  GetOptions( $EXECUTIVE_KEY => \$executive_key, );

  if ( !$executive_key )
  {
    croak 'Do not run Update.pm directly, '
      . "use the top-level aardvark executable$NEWLINE";
  }

  my $tou_data_directory = Utils::get_environment_name($TOURNAMENT_DATA_DIR);

  # Get the list of every .tou file that needs to be processed
  my $filenames_array_ref = Utils::get_tournament_data_filenames(
    $tou_data_directory,             $DEFAULT_YEAR_REGEX,
    $DEFAULT_COUNTRY_TRIGRAPH_REGEX, $DEFAULT_FILE_REGEX
  );

  Utils::fetch_local_tournament_data();
  Update::load_tournament_data($filenames_array_ref);
  Update::update_html();
  Update::push_local_content();
}

sub load_tou_files
{
  my $dbh                   = shift;
  my $filenames_array_ref   = shift;
  my $alt_names_hash        = shift;
  my $deceased_players_hash = shift;

  my @filenames_array = @{$filenames_array_ref};

  # Keep some player data in memory
  # so I don't have to keep searching
  # the database
  my $player_data = {};

  my $loading_log       = $EMPTY_STRING;
  my $tou_ignore_errors = Utils::get_tou_ignore_errors();

  foreach my $filename (@filenames_array)
  {
    my $tou = TOU->new(
      { dbh                   => $dbh,
        filename              => $filename,
        alt_names_hash        => $alt_names_hash,
        deceased_players_hash => $deceased_players_hash,
        player_data           => $player_data,
        correct               => 0,
      }
    );

    $tou->load( $dbh, $player_data );

    my $tou_report = $tou->get_report();

    if ( $tou_ignore_errors->{ $tou->{$TOU_FILENAME} } )
    {
      Utils::format_print("*** IGNORED ***$NEWLINE");
    }
    else
    {
      $loading_log .= $tou_report;
    }

    Utils::format_print($tou_report);
  }
  if ($loading_log)
  {
    my $iso_date = Utils::get_iso_date( time, $LOG_DATE_SEPARATOR );
    my $loading_log_filename = "$LOG_DIR/$iso_date" . "_$TOU_LOAD_LOG_NAME";
    my $date_string          = localtime;
    $loading_log
      = Utils::make_log_header("TOU Error Log$NEWLINE$date_string")
      . $loading_log;
    Utils::write_string_to_file( $loading_log, $loading_log_filename );
    Utils::send_email_notification( "TOU Error Log for $date_string",
      $loading_log_filename, $TOU_ERROR_SUBSCRIBERS );
  }

  return 1;
}

sub load_tournament_data
{
  my $filenames_array_ref = shift;

  # This hash is used to consolidate the names that are considered duplciates
  my $alt_names_hash = Utils::populate_alt_names_hash();

  # This hash designated players that are deceased
  my $deceased_players_hash
    = Utils::populate_deceased_players_hash($alt_names_hash);

  my $dbh = Utils::connect_to_database();

  # Every TOU file is reprocessed from raw .tou files every day,
  # so most of the database is deleted. Only the players table
  # is preserved, with the exception of the total_games_played
  # and last_played columns which are both reset.
  Utils::drop_all_wespa_tables( $dbh, $alt_names_hash );

  # Take a backup of the players and print the player id numbers
  Utils::record_database($dbh);

  # Create the necessary tables
  Utils::initialize_database( $dbh, $TABLES, $TABLE_CREATION_ORDER );

  # Process every .tou file
  Update::load_tou_files( $dbh, $filenames_array_ref,
    $alt_names_hash, $deceased_players_hash );

  # After all tournaments are loaded into the database,
  # set the 'current' and 'provisional' status for each player
  Utils::set_current_status($dbh);
  Utils::set_provisional_status($dbh);

  # Everything so far has been done on a development
  # database. This now needs to be copied so that
  # CGI requests access the most current data
  Utils::copy_database_to_production();

  return 1;
}

sub push_local_content
{
  my $working_dir = $DEFAULT_WORKING_DIR;

  my $base_dir;

  if ( Utils::get_environment_name($EMPTY_STRING) )
  {
    $base_dir = '/srv/dev/';
  }
  else
  {
    $base_dir    = '/srv/iwi.wespa.org/';
    $working_dir = '/srv/iwi.wespa.org/aardvark';
  }

  # Copy new data to dev dir
  system "cp -r $HTML_DIR $working_dir";

  # Copy static html
  # Softlinking is much more convenient
  # in this case
  system "cp -rf $HTML_STATIC_DIR/* $base_dir";

  system "cp -rf $HTML_STATIC_DIR/js $working_dir";

  system "cp -rf css/* $working_dir";

  # Copy data html
  system "cp -r $HTML_DATA_DIR/. $base_dir";

  # Copy the cgi scripts
  system "cp -r $CGIBIN_DIR $working_dir";

  # Copy the flags
  system "cp -r $COUNTRY_FLAGS_DIR/ $working_dir";

  return 1;
}

sub update_cgi
{
  my $dbh = shift;

  my $base_dir      = $DEFAULT_SHORT_NAME_WORKING_DIR . q{/} . $HTML_DIR;
  my $database_name = Utils::get_environment_name($PRODUCTION_DATABASE_NAME);

  my $title = 'Tournament Results';

  system "mkdir -p $CGIBIN_DIR";

  my $tournament_cgi_script = <<"CGI"
#!/usr/bin/perl

use warnings;
use strict;
use CGI;
use DBI;

my \$cgi = CGI->new();

my \$startyear = sanitize(\$cgi->param('startyear'));
my \$endyear   = sanitize(\$cgi->param('endyear'));
my \$state     = sanitize(\$cgi->param('state'));
my \$partname  = sanitize(\$cgi->param('partname'));

\$startyear .= '-00-00';
\$endyear   .= '-12-31';

my \$dbh =
  DBI->connect("DBI:mysql:database=$database_name;host=$DATABASE_HOST_NAME",
                         '$DATABASE_USER_NAME', '$DATABASE_PASSWORD',
                         {RaiseError => 1}); 

my \$query =
"
  SELECT *
  FROM $TOURNAMENTS_TABLE_NAME AS t
  WHERE
    t.end_date >= '\$startyear' AND t.start_date <= '\$endyear'    
";

if (\$state ne 'all')
  {
  \$query .= " AND t.country = '\$state' ";
  }
else
  {
  \$state = 'All Countries';
  }

if (\$partname)
  {
  \$query .= " AND t.name LIKE '%\$partname%' ";
  }

\$query .= " ORDER BY t.start_date ";

my \@tournaments =
  \@{\$dbh->selectall_arrayref(\$query, {Slice => {}, RaiseError => 1})};

my \$title_row = "<tr><th>#</th><th>Date</th><th>Tournament</th></tr>";

my \$search_style = 'style="padding: 10px; border-bottom: 1px solid black;"';

my \$search_content =
"
<table class='searchparams'>
<tbody>
<tr><th \$search_style>Start Date</th><td \$search_style>\$startyear</td></tr>
<tr><th \$search_style>End Date</th><td \$search_style>\$endyear</td></tr>
<tr><th \$search_style>Country</th><td \$search_style>\$state</td></tr>
<tr><th \$search_style>Partial Name</th><td \$search_style>\$partname</td></tr>
</tbody>
</table>
";

my \$table_content = "";

for (my \$i = 0; \$i < scalar \@tournaments; \$i++)
  {
  my \$item = \$tournaments[\$i];
  my \$name = \$item->{name};
  my \$date = \$item->{start_date};
  my \$id   = \$item->{id};

  my \$row_class = '$HTML_ROWEVEN_CLASS';
    
  if (\$i % 2 == 1)
  {
    \$row_class = '$HTML_ROWODD_CLASS';
  }
  my \$num = \$i + 1;

  my \$url = '/' .
             '$base_dir' .
             '/' .
             '$TOURNAMENT_HTML_DIR' .
             '/' .
             \$id .
             '.html';
  my \$link = "<a href='\$url'>\$name</a>";
  \$table_content .=
    "<tr class='\$row_class'>
       <td>\$num</td>
       <td>\$date</td>
       <td>\$link</td>
     </tr>";
  }

my \$content =
"
\$search_content
<table class='table'>
<tbody>
\$title_row
\$table_content
</tbody>
</table>
";

my \$results_html_page .= <<STOP
$TEMPLATE_DOCTYPE
<html>
  <head>
  $TEMPLATE_META
  <title>$title</title>
  
  $TEMPLATE_SOURCES
  
  $TEMPLATE_STYLE
  
  </head>
  
  <body id='override'>
    $TEMPLATE_WESPA_IMAGE
    $TEMPLATE_NAV
    <div style="background-color:#90D1EF">
      
      <div  class="container">
        <div class="row">
          <div class="col-xs-12"
               style="background-color:white;
                      margin-top:10px;margin-bottom:0px">
            <h2><img style="float:right ; margin: 2px 2px 2px 20px;"
                     height="60"
                     width="60"
                     src="$HTML_PATH_TO_WORKING_DIR/../wespafb.jpg"
                     alt="WESPA" />
                       $title
            </h2>   
          </div>
        </div>
      </div>
      <div  style="background-color:white;padding-top:10px;"
            class="container">
        <div class="row">
          <div class="table-responsive">
            \$content
          </div>
        </div>
      </div>
      $TEMPLATE_FOOTER
    </div>
  </body>
</html>

STOP
;

print "Content-Type: text/html$NEWLINE$NEWLINE";
print \$results_html_page;

  sub sanitize
  {
  my \$s = shift;

  \$s = substr(\$s, 0, 255);
  \$s =~ s/ /_/g;
  \$s =~ s/\\W//g;
  \$s =~ s/_/ /g;
  return \$s;
  }

1;

CGI
    ;
  Utils::write_string_to_file( $tournament_cgi_script,
    $CGIBIN_DIR . q{/} . $TOURNAMENT_CGI_FILENAME );

  return 1;
}

sub update_dynamically_loaded_content
{
  my $dbh = shift;

  my @player_data = @{
    $dbh->selectall_arrayref(
      "SELECT * FROM $PLAYERS_TABLE_NAME",
      { Slice => {}, RaiseError => 1 }
    )
  };

  @player_data = reverse sort { $a->{rating} <=> $b->{rating} } @player_data;

  my @valid_player_data
    = grep { !$_->{deceased} && !$_->{suspended} && $_->{current} }
    @player_data;

  my $cutoff = List::Util::min( $FRONT_PAGE_RATINGS_CUTOFF,
    scalar @valid_player_data );

  my $peek_html = "<table class='table'>$NEWLINE";
  $peek_html .= Utils::make_row(
    { keys     => [ 'Rank', 'Player', 'Rating' ],
      is_title => 1,
      class    => $HTML_WHITE_CLASS
    }
  );
  for my $i ( 0 .. $cutoff - 1 )
  {
    my $row_class = $HTML_ROWEVEN_CLASS;
    if ( $i % 2 == 1 )
    {
      $row_class = $HTML_ROWODD_CLASS;
    }
    my $player = $valid_player_data[$i];
    $player->{rank} = $i + 1;
    $peek_html .= Utils::make_row(
      { item  => $player,
        keys  => [ 'rank', 'name', 'rating' ],
        class => $row_class
      }
    );
  }
  $peek_html .= "</table>$NEWLINE";

  my $peek_filename
    = $HTML_DATA_DIR . q{/} . $FRONT_PAGE_RATINGS_DATA_FILENAME;

  Utils::write_string_to_file( $peek_html, $peek_filename );

  my $player_search_filename
    = $HTML_DATA_DIR . q{/} . $PLAYER_SEARCH_DATA_FILENAME;

  my $player_search_html = HTML::get_datalist_html(
    { data  => \@player_data,
      title => 'Player Name:',
      href  => "/$DEFAULT_SHORT_NAME_WORKING_DIR/$HTML_DIR/$PLAYER_HTML_DIR",
      html_id        => 'search_input_players',
      input_id       => 'datalist_input_element_players',
      button_id      => 'player_button',
      data_value_key => 'id',
      value_key      => 'name'
    }
  );

  Utils::write_string_to_file( $player_search_html, $player_search_filename );

  my $country_search_filename
    = $HTML_DATA_DIR . q{/} . $COUNTRY_SEARCH_DATA_FILENAME;

  my @country_data = map { $_->{country} } @valid_player_data;

  @country_data = Utils::uniq( \@country_data );

  @country_data
    = grep { $COUNTRY_TRIGRAPH_TO_COUNTRY_NAME_HASHREF->{$_} } @country_data;

  @country_data = map {
    { trigraph => $_,
      country  => $COUNTRY_TRIGRAPH_TO_COUNTRY_NAME_HASHREF->{$_}
    }
  } @country_data;

  my $country_search_html = HTML::get_datalist_html(
    { data  => \@country_data,
      title => 'Country:',
      href => "/$DEFAULT_SHORT_NAME_WORKING_DIR/$HTML_DIR/$RANKINGS_HTML_DIR",
      html_id        => 'search_input_countries',
      input_id       => 'datalist_input_element_countries',
      button_id      => 'country_button',
      data_value_key => 'trigraph',
      value_key      => 'country'
    }
  );
  Utils::write_string_to_file( $country_search_html,
    $country_search_filename );

  my $uniq_country_query
    = 'SELECT DISTINCT country '
    . "FROM $TOURNAMENTS_TABLE_NAME WHERE country IS NOT NULL";
  my @all_countries = map { $_->[0] }
    @{ $dbh->selectall_arrayref( $uniq_country_query, { RaiseError => 1 } ) };

  my @localtime    = localtime;
  my $current_year = $localtime[$LOCALTIME_YEAR_INDEX] + $LOCALTIME_YEAR_BASE;
  my $year_options = $EMPTY_STRING;
  my $country_options = $EMPTY_STRING;

  for my $i ( $TOURNAMENT_SEARCH_START_YEAR .. $current_year )
  {
    $year_options .= "<option value='$i'>$i</option>$NEWLINE";
  }

  @all_countries
    = sort { $a->[1] cmp $b->[1] }
    ( map { [ $_, $COUNTRY_TRIGRAPH_TO_COUNTRY_NAME_HASHREF->{$_} ] }
      @all_countries );

  for my $i ( 0 .. scalar @all_countries - 1 )
  {
    my $trigraph = $all_countries[$i]->[0];
    my $fullname = $all_countries[$i]->[1];
    $country_options
      .= "<option value='$trigraph'>$fullname</option>$NEWLINE";
  }

  my $tournament_form = <<"TOURNAMENT_FORM"
  Between
    <select name='startyear'>$NEWLINE
      <option value='1993'>Before $TOURNAMENT_SEARCH_START_YEAR</option>
      $year_options
    </select> and$NEWLINE
    <select name='endyear'>$NEWLINE
      <option value='1999'>Before $TOURNAMENT_SEARCH_START_YEAR</option>
      $year_options
    </select> in
    <select name='state'>$NEWLINE
      <option selected='selected' value='all'>All countries</option>
      $country_options;
    </select>
  Partial name: <input name='partname' size='20' value=''>
  <input type='submit' value='Submit'>
  <br>
TOURNAMENT_FORM
    ;

  my $tournament_form_name
    = $HTML_DATA_DIR . q{/} . $TOURNAMENT_FORM_DATA_FILENAME;

  Utils::write_string_to_file( $tournament_form, $tournament_form_name );

  return 1;
}

sub update_html
{
  my $dbh = Utils::connect_to_database();

  system "mkdir -p $HTML_DIR";
  system "mkdir -p $HTML_DIR/$PLAYER_HTML_DIR";
  system "mkdir -p $HTML_DIR/$TOURNAMENT_HTML_DIR";
  system "mkdir -p $HTML_DIR/$RANKINGS_HTML_DIR";

  my @player_ids_to_create = ();

  my $query = 'SELECT id FROM ' . $TOURNAMENTS_TABLE_NAME;

  my @tournament_ids_to_create = map { $_->[0] }
    @{ $dbh->selectall_arrayref( $query, { RaiseError => 1 } ) };

  # Create new tournament html pages

  foreach my $tournament_id (@tournament_ids_to_create)
  {
    my @division_data = ();
    my @division_rows = @{
      Utils::query_table( $dbh, $DIVISIONS_TABLE_NAME,
        'tournament_id', $tournament_id )
    };

    foreach my $division_row (@division_rows)
    {
      my @players_in_division = @{
        Utils::query_table(
          $dbh,          $TOURNAMENT_RESULTS_TABLE_NAME,
          'division_id', $division_row->{id}
        )
      };

      push @player_ids_to_create,
        ( map { $_->{player_id} } @players_in_division );

      push @division_data,
        HTML::get_tournament_results_html_string( $dbh, $division_row->{id},
        $HTML_ID_TOURNAMENT_TYPE );
    }
    my $tournament_filename
      = "$HTML_DIR/$TOURNAMENT_HTML_DIR/$tournament_id.html";

    my $tournament_html_page
      = HTML::get_tournament_template_html_string( \@division_data );

    Utils::write_string_to_file( $tournament_html_page,
      $tournament_filename );
  }

  my $countries_query = "SELECT * FROM $PLAYERS_TABLE_NAME";

  my @all_players = @{
    $dbh->selectall_arrayref( $countries_query,
      { Slice => {}, RaiseError => 1 } )
  };

  @all_players = grep {
         $_->{country}
      && $COUNTRY_TRIGRAPH_TO_COUNTRY_NAME_HASHREF->{ $_->{country} }
  } @all_players;

  my @all_countries = map { $_->{country} } @all_players;

  @all_countries = Utils::uniq( \@all_countries );

  my @country_rankings_to_create
    = map { $_->{country} }
    ( grep { !$_->{deceased} && !$_->{suspended} && $_->{current} }
      @all_players );

  @country_rankings_to_create = Utils::uniq( \@country_rankings_to_create );

  my %valid_link_countries = map { $_ => 1 } @country_rankings_to_create;

  @player_ids_to_create = Utils::uniq( \@player_ids_to_create );
  @player_ids_to_create = sort { $a <=> $b } @player_ids_to_create;

  # Update the player html pages that have been changed
  foreach my $player_id (@player_ids_to_create)
  {
    my @player
      = @{ Utils::query_table( $dbh, $PLAYERS_TABLE_NAME, 'id', $player_id )
      };

    my $player_name      = $player[0]->{name};
    my $country_trigraph = $player[0]->{country};
    my $games_played     = $player[0]->{total_games};
    my $rating           = $player[0]->{rating};
    my $photo_filename   = $player[0]->{photo};

    if ( !$country_trigraph )
    {
      $country_trigraph = $EMPTY_STRING;
    }

    if ( !$photo_filename )
    {
      # Move to constants
      $photo_filename = 'noimage.gif';
    }
    else
    {
      $photo_filename =~ s/.*\/([^\/]+)$/$1/gxms;
    }

    my $player_info = {
      player_name      => $player_name,
      country_trigraph => $country_trigraph,
      games_played     => $games_played,
      rating           => $rating,
      photo_filename   => $photo_filename,
      valid_ranking    => $valid_link_countries{$country_trigraph}
    };

    my $player_tournament_history
      = HTML::get_tournament_results_html_string( $dbh, $player_id,
      $HTML_ID_PLAYER_TYPE );
    my $player_head_to_head_history
      = HTML::get_tournament_results_html_string( $dbh, $player_id,
      $HTML_ID_HEAD_TO_HEAD_TYPE );

    my $player_tournament_history_html = $player_tournament_history->{html};
    my $player_tournament_history_data = $player_tournament_history->{data};

    my $player_head_to_head_history_html
      = $player_head_to_head_history->{html};

    my $player_html_page = HTML::get_player_template_html_string(
      $player_info,                      $player_tournament_history_html,
      $player_head_to_head_history_html, $player_tournament_history_data
    );

    # print $html_page;
    my $player_html_filename
      = $HTML_DIR . q{/} . $PLAYER_HTML_DIR . q{/} . "$player_id.html";

    Utils::write_string_to_file( $player_html_page, $player_html_filename );
  }

  # Update the full ranking list

  Utils::check_country_flag_icons( \@country_rankings_to_create );

  Update::update_rankings_html( $dbh, \@country_rankings_to_create );

  Update::update_dynamically_loaded_content($dbh);

  Update::update_cgi();

  my $all_time_stats = HTML::get_alltime_stats_results_html_string($dbh);
  my $all_time_stats_html_page
    = HTML::get_alltime_template_html_string($all_time_stats);
  Utils::write_string_to_file( $all_time_stats_html_page,
    $HTML_DIR . '/alltime_stats.html' );

  return 1;
}

sub update_rankings_html
{
  my $dbh           = shift;
  my $countries_ref = shift;

  my $base_dir = $DEFAULT_SHORT_NAME_WORKING_DIR . q{/} . $HTML_DIR;
  my $tournament_id;
  my $tournament_name;

  ( $tournament_id, $tournament_name )
    = Utils::get_most_recent_tournament($dbh);

  my $full_rankings_data = {
    'title'           => 'WESPA RATINGS',
    'tournament_link' => Utils::make_link(
      $base_dir,                $TOURNAMENT_HTML_DIR,
      $tournament_id . '.html', $tournament_name,
    )
  };

  my $full_ranking_html_string = HTML::get_rankings_html_string($dbh);
  my $full_ranking_html_page
    = HTML::get_rankings_template_html_string( $full_ranking_html_string,
    $full_rankings_data );
  my $full_ranking_filename
    = $HTML_DIR . q{/} . $RANKINGS_HTML_DIR . '/full_rankings.html';
  Utils::write_string_to_file( $full_ranking_html_page,
    $full_ranking_filename );

  my @countries = @{$countries_ref};
  foreach my $country (@countries)
  {
    if ( !$country ) { next; }
    my $country_fullname
      = $COUNTRY_TRIGRAPH_TO_COUNTRY_NAME_HASHREF->{$country};
    if ( !$country_fullname )
    {
      Utils::format_error(
        [ [ 'WARNING',  'Unmapped country trigraph' ],
          [ 'Trigraph', $country ]
        ]
      );
      next;
    }

    ( $tournament_id, $tournament_name )
      = Utils::get_most_recent_tournament( $dbh, $country );

    if ( !$tournament_id )
    {
      # No tournaments have been played in this country
      next;
    }

    my $rankings_data = {
      'title'           => $country_fullname . ' RATINGS',
      'tournament_link' => Utils::make_link(
        $base_dir,                $TOURNAMENT_HTML_DIR,
        $tournament_id . '.html', $tournament_name,
      )
    };

    my $country_ranking_html_string
      = HTML::get_rankings_html_string( $dbh, $country );
    my $country_ranking_html_page
      = HTML::get_rankings_template_html_string( $country_ranking_html_string,
      $rankings_data );
    my $country_ranking_filename
      = $HTML_DIR . q{/} . $RANKINGS_HTML_DIR . "/$country.html";
    Utils::write_string_to_file( $country_ranking_html_page,
      $country_ranking_filename );
  }

  return 1;
}

1;
