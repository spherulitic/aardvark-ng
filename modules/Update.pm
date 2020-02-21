#!/usr/bin/perl

package Update;

use strict;
use warnings;
use DBI;
use Data::Dumper;

use lib './modules';
use lib './objects';
use Constants;
use Utils;
use TOU;
use HTML;

unless (caller)
{
  # Utils::chdir_strict();
  my @t = localtime();
  $t[5] += 1900;
  $t[4]++;
  
  my $logname = (sprintf "%04d-%02d-%02d", @t[5,4,3]) . '_cronjob.log';

  Utils::fetch_local_tournament_data();
  Update::load_all_tournament_data();
  Update::update_html();
  Update::push_local_content(); 
}

sub load_all_tou_files
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

  foreach my $filename (@filenames_array)
  {
    my $tou = TOU->new(
                        $dbh,
                        $filename,
                        $alt_names_hash,
                        $deceased_players_hash,
                        $player_data
                      );

    $tou->load($dbh, $player_data);
    # Testing code:
    last;
  }
}

sub load_all_tournament_data
{
  my $tables                 = Constants::TABLES;
  my $creation_order         = Constants::TABLE_CREATION_ORDER;
  my $lexicons               = Constants::LEXICONS;
  my $lexicons_tn            = Constants::LEXICONS_TABLE_NAME;
  my $working_directory      = Utils::get_environment_name(Constants::DEFAULT_WORKING_DIR);
  my $tou_data_directory     = Utils::get_environment_name(Constants::TOURNAMENT_DATA_DIR);
  my $year_regex             = Constants::DEFAULT_YEAR_REGEX;
  my $country_trigraph_regex = Constants::DEFAULT_COUNTRY_TRIGRAPH_REGEX;
  my $file_regex             = Constants::DEFAULT_FILE_REGEX;

  # This hash is used to consolidate the names that are considered duplciates
  my $alt_names_hash = Utils::populate_alt_names_hash();

  # This hash designated players that are deceased
  my $deceased_players_hash = Utils::populate_deceased_players_hash($alt_names_hash);

  my $dbh = Utils::connect_to_database();

  # Every TOU file is reprocessed from raw .tou files every day,
  # so most of the database is deleted. Only the players table
  # is preserved, with the exception of the total_games_played
  # and last_played columns which are both reset.
  Utils::drop_all_wespa_tables($dbh, $alt_names_hash);

  # Take a backup of the players and print the player id numbers
  Utils::record_database($dbh);

  # Create the necessary tables
  Utils::initialize_database($dbh, $tables, $creation_order);

  # Get the list of every .tou file that needs to be processed
  my $filenames_array_ref = Utils::get_tournament_data_filenames
                              (
                                $tou_data_directory,
                                $year_regex,
                                $country_trigraph_regex,
                                $file_regex
                              );
  # Process every .tou file
  Update::load_all_tou_files(
                              $dbh,
                              $filenames_array_ref,
                              $alt_names_hash,
                              $deceased_players_hash
                            );


  # After all tournaments are loaded into the database,
  # set the 'current' and 'provisional' status for each player
  Utils::set_current_status($dbh);
  Utils::set_provisional_status($dbh);

  # Everything so far has been done on a development
  # database. This now needs to be copied so that
  # CGI requests access the most current data
  Utils::copy_database_to_production();
}


sub push_local_content 
{
  my $cwd = Cwd::getcwd();

  my $working_dir         = Constants::DEFAULT_WORKING_DIR;
  my $html_dir            = Constants::HTML_DIR;
  my $cgibin_dir          = Constants::CGIBIN_DIR;
  my $html_static_dir     = Constants::HTML_STATIC_DIR;
  my $html_data_dir       = Constants::HTML_DATA_DIR;
  my $player_html_dir     = Constants::PLAYER_HTML_DIR;
  my $tournament_html_dir = Constants::TOURNAMENT_HTML_DIR;
  my $rankings_html_dir   = Constants::RANKINGS_HTML_DIR;
  my $flags_dir           = Constants::COUNTRY_FLAGS_DIR;

  my $base_dir;
 
  if (Utils::get_environment_name(''))
  {
    $base_dir = '/srv/dev/'
  }
  else
  {
    $base_dir    = '/srv/iwi.wespa.org/';
    $working_dir = '/srv/iwi.wespa.org/aardvark';
  }

  # Copy new data to dev dir
  system "cp -r $html_dir $working_dir";

  # Copy static html
  # Softlinking is much more convenient
  # in this case
  system "cp -rf $html_static_dir/* $base_dir";

  system "cp -rf css/* $working_dir";

  # Copy data html
  system "cp -r $html_data_dir/. $base_dir";

  # Copy the cgi scripts
  system "cp -r $cgibin_dir $working_dir";

  # Copy the flags
  system "cp -r $flags_dir/ $working_dir";
  
}

sub update_cgi
{
  my $dbh = shift;

  my $html_path = Constants::HTML_PATH_TO_WORKING_DIR;
  my $doctype   = Constants::TEMPLATE_DOCTYPE;
  my $meta      = Constants::TEMPLATE_META;
  my $lang      = Constants::TEMPLATE_LANG;
  my $wespa_img = Constants::TEMPLATE_WESPA_IMAGE;
  my $sources   = Constants::TEMPLATE_SOURCES;
  my $style     = Constants::TEMPLATE_STYLE;
  my $scripts   = Constants::TEMPLATE_SCRIPTS;
  my $nav       = Constants::TEMPLATE_NAV;
  my $footer    = Constants::TEMPLATE_FOOTER;
  my $base_dir  = Constants::DEFAULT_SHORT_NAME_WORKING_DIR . '/' . Constants::HTML_DIR;
  my $tournament_dir = Constants::TOURNAMENT_HTML_DIR;

  my $database_name = Utils::get_environment_name(Constants::PRODUCTION_DATABASE_NAME);
  my $host_name     = Constants::DATABASE_HOST_NAME;
  my $user_name     = Constants::DATABASE_USER_NAME;
  my $password      = Constants::DATABASE_PASSWORD;

  my $tournaments_tn = Constants::TOURNAMENTS_TABLE_NAME;

  my $cgi_dir  = Constants::CGIBIN_DIR;
 
  my $title = "Tournament Results";
 
  system "mkdir -p $cgi_dir";

  my $filename = Constants::TOURNAMENT_CGI_FILENAME;

  my $tournament_cgi_script = <<CGI
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

my \$dbh = DBI->connect("DBI:mysql:database=$database_name;host=$host_name",
                         '$user_name', '$password',
                         {'RaiseError' => 1}); 

my \$query =
"
  SELECT *
  FROM $tournaments_tn AS t
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

my \@tournaments = \@{\$dbh->selectall_arrayref(\$query, {Slice => {}, "RaiseError" => 1})};

my \$title_row = "<tr><th>#</th><th>Date</th><th>Tournament</th></tr>";

my \$search_style = 'style="padding: 10px; border-bottom: 1px solid black;"';

my \$search_content =
"
<table class='searchparams'>
<tbody>
<tr><th \$search_style>Start Date            </th><td \$search_style>\$startyear</td></tr>
<tr><th \$search_style>End Date              </th><td \$search_style>\$endyear</td></tr>
<tr><th \$search_style>Country               </th><td \$search_style>\$state</td></tr>
<tr><th \$search_style>Partial Name          </th><td \$search_style>\$partname</td></tr>
</tbody>
</table>
";

my \$table_content = "";

for (my \$i = 0; \$i < scalar \@tournaments; \$i++)
{
  my \$item = \$tournaments[\$i];
  my \$name = \$item->{'name'};
  my \$date = \$item->{'start_date'};
  my \$id   = \$item->{'id'};

  my \$row_class = 'roweven';
    
  if (\$i % 2 == 1)
  {
    \$row_class = 'rowodd';
  }
  my \$num = \$i + 1;

  my \$url = '/' . '$base_dir' . '/' . '$tournament_dir' . '/' . \$id . '.html';
  my \$link = "<a href='\$url'>\$name</a>";
  \$table_content .= "<tr class='\$row_class'><td>\$num</td><td>\$date</td><td>\$link</td></tr>";
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
$doctype
<html>
  <head>
  $meta
  <title>$title</title>
  
  $sources
  
  $style
  
  </head>
  
  <body id='override'>
    $wespa_img
    $nav
    <div style="background-color:#90D1EF">
      
      <div  class="container">
        <div class="row">
          <div class="col-xs-12" style="background-color:white;margin-top:10px;margin-bottom:0px">
            <h2><img style="float:right ; margin: 2px 2px 2px 20px;" height="60" width="60" src="$html_path/../wespafb.jpg" alt="WESPA" />$title</h2>   
          </div>
        </div>
      </div>
      <div  style="background-color:white;padding-top:10px;"  class="container">
        <div class="row">
          <div class="table-responsive">
            \$content
          </div>
        </div>
      </div>
      $footer
    </div>
  </body>
</html>

STOP
;

print "Content-Type: text/html\n\n";
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
  Utils::write_string_to_file($tournament_cgi_script, $cgi_dir . '/' . $filename);
}

sub update_dynamically_loaded_content
{
  my $dbh               = shift;

  my $players_table = Constants::PLAYERS_TABLE_NAME;
  my @player_data = @{$dbh->selectall_arrayref("SELECT * FROM $players_table"  , {Slice => {}, "RaiseError" => 1})};

  @player_data = sort {$b->{'rating'} <=> $a->{'rating'}} @player_data;

  my @valid_player_data = grep { !$_->{'deceased'} && !$_->{'suspended'} && $_->{'current'}} @player_data;   

  my $cutoff = Constants::FRONT_PAGE_RATINGS_CUTOFF;

  $cutoff = List::Util::min($cutoff, scalar @valid_player_data);

  my $peek_html = "<table class='table'>\n";
  $peek_html .=
    Utils::make_row
    (
      0,
      ['Rank', 'Player', 'Rating'],
      1,
      0,
      'white'
    );

  for (my $i = 0; $i < $cutoff; $i++)
  {
    my $row_class = 'roweven';
    if ($i % 2 == 1)
    {
      $row_class = 'rowodd';
    }
    my $player = $valid_player_data[$i];
    $player->{'rank'} = $i + 1;
    $peek_html .= Utils::make_row($player, ['rank', 'name', 'rating'], 0, 0, $row_class);
  }
  $peek_html .= "</table>\n";

  my $peek_filename = Constants::HTML_DATA_DIR . '/' . Constants::FRONT_PAGE_RATINGS_DATA_FILENAME;

  Utils::write_string_to_file($peek_html, $peek_filename);

  my $player_search_filename = Constants::HTML_DATA_DIR . '/' . Constants::PLAYER_SEARCH_DATA_FILENAME;

  my $working_dir = Constants::DEFAULT_SHORT_NAME_WORKING_DIR;
  my $html_dir = Constants::HTML_DIR;
  my $player_dir = Constants::PLAYER_HTML_DIR;

  my $player_search_html =
    HTML::get_datalist_html
    (
      \@player_data,
      "Player Name:",
      "/$working_dir/$html_dir/$player_dir",
      "search_input_players",
      "datalist_input_element_players",
      'player_button',
      'id',
      'name'
    );

  Utils::write_string_to_file($player_search_html, $player_search_filename);

  my $country_search_filename = Constants::HTML_DATA_DIR . '/' . Constants::COUNTRY_SEARCH_DATA_FILENAME;

  my $rankings_dir = Constants::RANKINGS_HTML_DIR;

  my @country_data = map { $_->{'country'}  } @valid_player_data;

  @country_data = Utils::uniq(\@country_data);

  my $trigraph_hashref = Constants::COUNTRY_TRIGRAPH_TO_COUNTRY_NAME_HASHREF;

  @country_data = grep {$trigraph_hashref->{$_}} @country_data;

  @country_data = map { {'trigraph' => $_, 'country' => $trigraph_hashref->{$_}}   } @country_data;

  my $country_search_html =
    HTML::get_datalist_html
    (
      \@country_data,
      "Country:",
      "/$working_dir/$html_dir/$rankings_dir",
      "search_input_countries",
      "datalist_input_element_countries",
      'country_button',
      'trigraph',
      'country'
    );

  Utils::write_string_to_file($country_search_html, $country_search_filename);

  my $tournaments_tn = Constants::TOURNAMENTS_TABLE_NAME;
  my $uniq_country_query = "SELECT DISTINCT country FROM $tournaments_tn WHERE country IS NOT NULL";
  my @all_countries = map {$_->[0]} @{$dbh->selectall_arrayref($uniq_country_query, {"RaiseError" => 1})};

  my @localtime = localtime();
  my $current_year = $localtime[5] + 1900;
  my $year_options = "";
  my $country_options = "";
  

  for (my $i = 2000; $i <= $current_year; $i++)
  {
    $year_options .= "<option value='$i'>$i</option>\n";
  }

  @all_countries = sort {$a->[1] cmp $b->[1]} (map { [$_, $trigraph_hashref->{$_}]  } @all_countries);

  for (my $i = 0; $i < scalar @all_countries; $i++)
  {
    my $trigraph = $all_countries[$i]->[0];
    my $fullname = $all_countries[$i]->[1];
    $country_options .= "<option value='$trigraph'>$fullname</option>\n";
  }

  my $tournament_form = "Between <select name='startyear'>\n<option value='1993'>Before 2000</option>";

  $tournament_form .= $year_options;
 
  $tournament_form .= "</select> and\n";

  $tournament_form .= "<select name='endyear'>\n<option value='1999'>Before 2000</option>";
  
  $tournament_form .= $year_options;

  $tournament_form .= "</select> in <select name='state'>\n<option selected='selected' value='all'>All countries</option>";

  $tournament_form .= $country_options;

  $tournament_form .= "</select>  Partial name: <input name='partname' size='20' value=''> <input type='submit' value='Submit'> <br>";

  my $tournament_form_name = Constants::HTML_DATA_DIR . '/' . Constants::TOURNAMENT_FORM_DATA_FILENAME;

  Utils::write_string_to_file($tournament_form, $tournament_form_name); 

}

sub update_html
{
  my $dbh = Utils::connect_to_database();

  my $html_dir            = Constants::HTML_DIR;
  my $player_html_dir     = Constants::PLAYER_HTML_DIR;
  my $tournament_html_dir = Constants::TOURNAMENT_HTML_DIR;
  my $rankings_html_dir   = Constants::RANKINGS_HTML_DIR;
  my $flags_dir           = Constants::COUNTRY_FLAGS_DIR;

  system "mkdir -p $html_dir";
  system "mkdir -p $html_dir/$player_html_dir";
  system "mkdir -p $html_dir/$tournament_html_dir";
  system "mkdir -p $html_dir/$rankings_html_dir";

  my @player_ids_to_create = ();

  my $query = "SELECT id FROM " . Constants::TOURNAMENTS_TABLE_NAME;

  my @tournament_ids_to_create = map { $_->[0]  }  @{$dbh->selectall_arrayref($query, {"RaiseError" => 1})};

  # Create new tournament html pages

  foreach my $tournament_id (@tournament_ids_to_create)
  {
    # if ($tournament_id != 38){next;}
    my @division_data = ();
    my @division_rows = @{Utils::query_table(
                                              $dbh,
                                              Constants::DIVISIONS_TABLE_NAME,
                                              'tournament_id',
                                              $tournament_id
                                            )};

    foreach my $division_row (@division_rows)
    {
      my @players_in_division =
        @{Utils::query_table(
                              $dbh,
                              Constants::TOURNAMENT_RESULTS_TABLE_NAME,
                              'division_id',
                              $division_row->{id}
                            )};

      push @player_ids_to_create, (map { $_->{player_id} } @players_in_division);

      push @division_data,
        HTML::get_tournament_results_html_string(
                                                  $dbh,
                                                  $division_row->{id},
                                                  Constants::HTML_ID_TOURNAMENT_TYPE
                                                );
    }
    my $tournament_filename = "$html_dir/$tournament_html_dir/$tournament_id.html";

    my $tournament_html_page = HTML::get_tournament_template_html_string
    (
      \@division_data
    );

    Utils::write_string_to_file($tournament_html_page, $tournament_filename);
  }

  my $players_tn = Constants::PLAYERS_TABLE_NAME;

  my $countries_query = 
    "
      SELECT *
      FROM $players_tn
    ";


  my $trigraph_hashref = Constants::COUNTRY_TRIGRAPH_TO_COUNTRY_NAME_HASHREF;

  my @all_players = @{$dbh->selectall_arrayref($countries_query, {Slice => {}, "RaiseError" => 1})};

  @all_players = grep {$_->{'country'} && $trigraph_hashref->{$_->{'country'}}} @all_players;

  my @all_countries = map { $_->{'country'}  } @all_players;

  @all_countries = Utils::uniq(\@all_countries);

  my @country_rankings_to_create = map { $_->{'country'}  } (grep { !$_->{'deceased'} && !$_->{'suspended'} && $_->{'current'}   } @all_players);
  @country_rankings_to_create = Utils::uniq(\@country_rankings_to_create);

  my %valid_link_countries = map { $_ => 1 } @country_rankings_to_create;

  @player_ids_to_create = Utils::uniq(\@player_ids_to_create);
  @player_ids_to_create = sort {$a <=> $b} @player_ids_to_create;

  # Update the player html pages that have been changed
  foreach my $player_id (@player_ids_to_create)
  {
    my @player = @{Utils::query_table($dbh, Constants::PLAYERS_TABLE_NAME, "id", $player_id)};
  
    my $player_name      = $player[0]->{'name'};
    my $country_trigraph = $player[0]->{'country'};
    my $games_played     = $player[0]->{'total_games'};
    my $rating           = $player[0]->{'rating'};
    my $photo_filename   = $player[0]->{'photo'};

    if (!$country_trigraph)
    {
      $country_trigraph = "";
    }

    if (!$photo_filename)
    {
      $photo_filename = 'noimage.gif';
    }
    else
    {
      $photo_filename =~ /\/([^\/]+)$/;
      $photo_filename = $1;
    }

    my $player_info =
    {
      'player_name'      => $player_name,
      'country_trigraph' => $country_trigraph,
      'games_played'     => $games_played,
      'rating'           => $rating,
      'photo_filename'   => $photo_filename,
      'valid_ranking'    => $valid_link_countries{$country_trigraph}
    };

    my $player_tournament_history   = HTML::get_tournament_results_html_string($dbh, $player_id, Constants::HTML_ID_PLAYER_TYPE);
    my $player_head_to_head_history = HTML::get_tournament_results_html_string($dbh, $player_id, Constants::HTML_ID_HEAD_TO_HEAD_TYPE);

    my $player_tournament_history_html = $player_tournament_history->[0];
    my $player_tournament_history_data = $player_tournament_history->[1];

    my $player_head_to_head_history_html = $player_head_to_head_history->[0];

    my $player_html_page = HTML::get_player_template_html_string
    (
      $player_info,
      $player_tournament_history_html,
      $player_head_to_head_history_html,
      $player_tournament_history_data
    );
  
    # print $html_page;
    my $filename =  Constants::HTML_DIR . '/' . Constants::PLAYER_HTML_DIR . '/' . $player_id . ".html";

    Utils::write_string_to_file($player_html_page, $filename);
  }

  # Update the full ranking list

  Utils::check_country_flag_icons(\@country_rankings_to_create);

  Update::update_rankings_html($dbh, \@country_rankings_to_create);

  Update::update_dynamically_loaded_content($dbh);

  Update::update_cgi(); 

  my $all_time_stats = HTML::get_alltime_stats_results_html_string($dbh);
  my $all_time_stats_html_page = HTML::get_alltime_template_html_string($all_time_stats);
  Utils::write_string_to_file($all_time_stats_html_page,Constants::HTML_DIR . '/alltime_stats.html');
}

sub update_rankings_html
{
  my $dbh = shift;
  my $countries_ref = shift;

  my $trigraph_hashref = Constants::COUNTRY_TRIGRAPH_TO_COUNTRY_NAME_HASHREF;
  my $base_dir = Constants::DEFAULT_SHORT_NAME_WORKING_DIR . '/' . Constants::HTML_DIR;
  my $tournament_dir = Constants::TOURNAMENT_HTML_DIR;

  my $most_recent_tournament = Utils::get_most_recent_tournament($dbh);
  my $full_rankings_data =
    {
      'title' => "WESPA RATINGS",
      'tournament_link'        => Utils::make_link
                                  (
                                    $base_dir,
                                    $tournament_dir,
                                    $most_recent_tournament->[0] . ".html",
                                    $most_recent_tournament->[1],
                                  )
    };

  my $full_ranking_html_string = HTML::get_rankings_html_string($dbh);
  my $full_ranking_html_page =
    HTML::get_rankings_template_html_string
    (    
      $full_ranking_html_string,
      $full_rankings_data
    );   
  my $full_ranking_filename = Constants::HTML_DIR . '/' . Constants::RANKINGS_HTML_DIR . "/full_rankings.html";
  Utils::write_string_to_file($full_ranking_html_page, $full_ranking_filename);

  my @countries = @{$countries_ref};
  foreach my $country (@countries)
  {
    if (!$country){next;}
    my $country_fullname = $trigraph_hashref->{$country};
    if (!$country_fullname)
    {    
      print "Unmapped country trigraph: $country\n";
      next;
    }    
    my $most_recent_tournament = Utils::get_most_recent_tournament($dbh, $country);


    my $rankings_data = 
    {    
      'title' => $country_fullname . " RATINGS",
      'tournament_link'        => Utils::make_link
                                  (
                                    $base_dir,
                                    $tournament_dir,
                                    $most_recent_tournament->[0] . ".html",
                                    $most_recent_tournament->[1],
                                  )
    };   

    my $country_ranking_html_string = HTML::get_rankings_html_string($dbh, $country);
    my $country_ranking_html_page =
       HTML::get_rankings_template_html_string
       (
         $country_ranking_html_string,
         $rankings_data
       );
    my $country_ranking_filename = Constants::HTML_DIR . '/' . Constants::RANKINGS_HTML_DIR . "/$country.html";
    HTML::write_string_to_file($country_ranking_html_page, $country_ranking_filename); 
  }
}



1;
