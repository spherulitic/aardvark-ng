#!/usr/bin/perl

package HTML;


use strict;
use warnings;
use version; our $VERSION = qv('1');
use Data::Dumper;

use lib './modules';
use Constants;
use Utils;

sub get_alltime_stats_results_html_string
{
  my $dbh = shift;
  my $player_type       = $HTML_ID_PLAYER_TYPE;
  my $tournament_type   = $HTML_ID_TOURNAMENT_TYPE;
  my $head_to_head_type = $HTML_ID_HEAD_TO_HEAD_TYPE;

  my $tr_table_name = $TOURNAMENT_RESULTS_TABLE_NAME;
  my $g_table_name  = $GAMES_TABLE_NAME;
  my $pr_table_name = $PLAYER_RESULTS_TABLE_NAME;
  my $p_table_name  = $PLAYERS_TABLE_NAME;
  my $t_table_name  = $TOURNAMENTS_TABLE_NAME;
  my $d_table_name  = $DIVISIONS_TABLE_NAME;

  my $sth = $dbh->prepare(
  "
  SELECT
    tr1.start_rating    AS tr_start_rating,
    p1.name             AS tr_player_name,
    p1.id               AS tr_player_id,
    pr1.score           AS pr1_score,
    tr2.start_rating    AS opp_rating,
    p2.name             AS opp_name,
    p2.id               AS opp_id,
    pr2.score           AS pr2_score,
    g.round             AS g_round,
    tr1.tournament_name AS tr_tournament_name,
    t.id                AS t_id
  FROM
    $g_table_name AS g, $pr_table_name AS pr1, $pr_table_name AS pr2, $p_table_name AS p1, $p_table_name AS p2, $tr_table_name AS tr1, $tr_table_name AS tr2, $d_table_name AS d, $t_table_name AS t
  WHERE
    g.id = pr1.game_id AND g.id = pr2.game_id       AND
    pr1.player_id = p1.id AND pr2.player_id = p2.id AND
    p1.id = tr1.player_id AND p2.id = tr2.player_id AND
    p1.id > p2.id                       AND
      g.division_id   = tr1.division_id AND
      g.division_id   = tr2.division_id AND
      g.division_id   = d.id            AND
      d.tournament_id = t.id
  ");

  $sth->execute();
 
  my $all_stats = Utils::stat_objects();
  my $game_stats_rank_name = $GAME_STATS_RANK_NAME;
  my $stat_key_name        = $STAT_KEY_NAME;

  my $tournament_results_hashref = {};
  my $alltime_cutoff = $ALLTIME_CUTOFF;

  foreach my $key (keys %{$all_stats})
  {
    my $statitem = $all_stats->{$key};

    my @value_list = @{$statitem->{'values'}};
    push @value_list, 'tr_tournament_name';
    $statitem->{'values'} = \@value_list;

    my @titles = @{$statitem->{'titles'}};
    push @titles, 'Tournament';
    $statitem->{'titles'} = \@titles;
  }


  while (my $data = $sth->fetchrow_hashref)
  {
    for (my $y = 0; $y < 2; $y++)
    {
      if ($y == 1)
      {
        Utils::swap($data, 'tr_start_rating', 'opp_rating');
        Utils::swap($data, 'tr_player_name',  'opp_name');
        Utils::swap($data, 'tr_player_id',    'opp_id');
        Utils::swap($data, 'pr1_score',       'pr2_score');
      }
      foreach my $key (keys %{$all_stats})
      {
        my $statitem = $all_stats->{$key};
        if ($statitem->{'cond'}->($data))
        {
          my $stat = $statitem->{'eval'}->($data);
          my @value_list = @{$statitem->{'values'}};
          my $statdata = {};
          foreach my $val (@value_list)
          {
            my $dataitem = $data->{$val};
            if ($dataitem)
            {
              $statdata->{$val} = $dataitem;
            }
          }
          $statdata->{'tr_player_id'} = $data->{'tr_player_id'};
          $statdata->{'opp_id'}       = $data->{'opp_id'};
          $statdata->{'t_id'}         = $data->{'t_id'};


          $statdata->{$stat_key_name} = $stat;

          push @{$statitem->{'list'}}, $statdata;
          my @statlist = @{$statitem->{'list'}};
          @statlist = sort {$statitem->{sort}->($a, $b)} @statlist;
          while (scalar @statlist > $alltime_cutoff)
          {
            pop @statlist;
          }
          $statitem->{'list'} = \@statlist;
        } 
      }
    }
  }
  foreach my $key (keys %{$all_stats})
  {
    my $statitem = $all_stats->{$key};
    my @statlist = @{$statitem->{'list'}};
    for (my $i = 0; $i < scalar @statlist; $i++)
    {
      $statlist[$i]->{$game_stats_rank_name} = $i + 1;
    }
  }

  my $all_stats_html = {};

    foreach my $key (keys %{$all_stats})
    {
      my $dataitem = $all_stats->{$key};

      my $html_string = "       <table class='table'>\n";
      $html_string    .=
          Utils::make_row
          ({
            keys     => $dataitem->{titles},
            is_title => 1
          });

      my @statlist = @{$dataitem->{'list'}};
      for (my $i = 0; $i < scalar @statlist; $i++)
      {
        my $sub_row_class = 'roweven';
    
        if ($i % 2 == 1)
        {
          $sub_row_class = 'rowodd';
        }

        my $statitem = $statlist[$i];

        $html_string .=
          Utils::make_row
          ({
            item => $statitem, 
            keys => $dataitem->{'values'},
            class => $sub_row_class
          });
      }
      $html_string .= "        </table>";

      $all_stats_html->{$key} = $html_string;
    }
  return $all_stats_html;
}

sub get_alltime_template_html_string
{
  my $stats = shift;

  my $html_path = $HTML_PATH_TO_WORKING_DIR;
  my $doctype   = $TEMPLATE_DOCTYPE;
  my $meta      = $TEMPLATE_META;
  my $lang      = $TEMPLATE_LANG;
  my $wespa_img = $TEMPLATE_WESPA_IMAGE;
  my $sources   = $TEMPLATE_SOURCES;
  my $style     = $TEMPLATE_STYLE;
  my $scripts   = $TEMPLATE_SCRIPTS;
  my $nav       = $TEMPLATE_NAV;
  my $footer    = $TEMPLATE_FOOTER;

  my @ids_to_click = ();
  
  my $display_none_style = "style='display:none;'";


  my $stats_tabclass    = "stats_tab";
  my $stats_tablink     = "stats_tablink";


  my $stats_content = "";
  my @stats_tabdata = ();

  my $stats_order_ref = $TOURNAMENT_STATS_ORDER;

  for (my $k = 0; $k < scalar @{$stats_order_ref}; $k++)
  {
    my $cat = $stats_order_ref->[$k];
    my $stat_id =  "stats_$cat";
    push @stats_tabdata, [$cat, $stat_id];

    my $stat_html = $stats->{$cat};
    $stats_content .= "<div id='$stat_id' class='$stats_tabclass' $display_none_style>$stat_html</div>\n";
    if ($k == 0)
    {
      push @ids_to_click, "button_$stat_id";
    }
  }

  $stats_content = Utils::make_tab_div(\@stats_tabdata, $stats_tabclass, $stats_tablink) . $stats_content;


  my $ids_to_click_javascript_array = "[";

  for (my $i = 0; $i < scalar @ids_to_click; $i++)
  {
    my $id = $ids_to_click[$i];
    $ids_to_click_javascript_array .= "'$id'";
    if ($i != (scalar @ids_to_click) - 1)
    {
      $ids_to_click_javascript_array .= ", ";
    }
  }

  $ids_to_click_javascript_array .= "]";

  my $tournament_html_page = "";

  $tournament_html_page .= <<"STOP";
$doctype
<html>
  <head>
  $meta
  <title>All Time Stats</title>
  
  $sources
  
  $style
  
  <script type="text/javascript">
 
    $scripts

   
    window.onload = function()
    { 
      var ids = $ids_to_click_javascript_array;
      for (var i = 0; i < ids.length; i++)
      {
        var id = ids[i];
        document.getElementById(id).click();
      }
    }
  </script>

  </head>
  
  <body id='override'>
    $wespa_img
    $nav
    <div style="background-color:#90D1EF">
      <div style="background-color:white;padding-top:10px;" class="container">
        <h2>All Time Stats</h2>
        <hr>
        <div class="row">
          <div class="col-md-12 col-xs-12 col-sm-12">
            $stats_content
          </div>
        </div>
      </div>
      $footer
    </div>
  </div>
  </body>
</html>

STOP

  return $tournament_html_page;
}

sub get_datalist_html
{
  my $arg_ref = @_;

  my $data           = $arg_ref->{data};
  my $title          = $arg_ref->{title};
  my $href           = $arg_ref->{href};
  my $html_id        = $arg_ref->{html_id};
  my $input_id       = $arg_ref->{input_id};
  my $button_id      = $arg_ref->{button_id};
  my $data_value_key = $arg_ref->{data_value_key};
  my $value_key      = $arg_ref->{value_key};

  my $escaped_char = "&quot;";

  my $function = <<"FUNCTION"

          var input = document.getElementById('$input_id');
          var options = Array.from(document.getElementById('$html_id').options).map(function(el)
          {
            return el.value;
          }); 
          var relevantOptions = options.filter
          (
            function(option)
            {
              return option.toLowerCase().includes(input.value.toLowerCase());
            }
          );

          if (relevantOptions.length == 1 && relevantOptions[0] === input.value)
          {
            var pname = document.getElementById('$input_id').value;
            var pid   = document.querySelector('#$html_id option[value=$escaped_char'+pname+'$escaped_char]').dataset.value;

            if (pid)
            {
              window.location.href = '$href/' + pid + '.html';
            }
          }
          else if (relevantOptions.length > 0)
          {
            input.value = relevantOptions.shift();
          }
          else
          {
            alert('Choose an option by typing in the box and selecting an option from the pop-up menu.');
          }
FUNCTION
;


  my $input_function = <<"FUNCTION"

    onkeypress=
    "
      (function (event)
      {
        if (event.keyCode == 13)
        {
          $function
        }
      })(event)
    "
FUNCTION
;

  my $submit_function = <<"FUNCTION"
    onclick=
      "
        (function ()
        {
          $function 
        })()
      " 

FUNCTION
;

  my $html =
  "
  $title
  <input list='$html_id' id='$input_id' $input_function>
    <datalist id='$html_id'>
  ";

  my @data_array = @{$data};

  foreach my $item (@data_array)
  {
    my $name = $item->{$value_key};
    my $id   = $item->{$data_value_key};
    $html .= "<option data-value='$id' value=\"$name\"></option>\n";
  }

  $html .= "    </datalist>\n";


  $html .= "<input type='button' value='Submit' id='$button_id' $submit_function>";
  return $html
}

sub get_player_template_html_string
{
  my $player_info = shift;
  my $player_tournament_history_html = shift;
  my $player_head_to_head_history_html = shift;
  my $player_tournament_history_data = shift;

  my $html_path = $HTML_PATH_TO_WORKING_DIR;
  my $doctype   = $TEMPLATE_DOCTYPE;
  my $meta      = $TEMPLATE_META;
  my $lang      = $TEMPLATE_LANG;
  my $wespa_img = $TEMPLATE_WESPA_IMAGE;
  my $sources   = $TEMPLATE_SOURCES;
  my $style     = $TEMPLATE_STYLE;
  my $scripts   = $TEMPLATE_SCRIPTS;
  my $nav       = $TEMPLATE_NAV;
  my $footer    = $TEMPLATE_FOOTER;

  my $player_name      = $player_info->{'player_name'};
  my $country_trigraph = $player_info->{'country_trigraph'};
  my $games_played     = $player_info->{'games_played'};
  my $rating           = $player_info->{'rating'};
  my $photo_filename   = $player_info->{'photo_filename'};
  my $valid_ranking    = $player_info->{'valid_ranking'};

  my $country = $country_trigraph;

  my $wins          = $player_tournament_history_data->{'wins'};
  my $losses        = $player_tournament_history_data->{'losses'};
  my $draws         = $player_tournament_history_data->{'draws'};
  my $total_score   = $player_tournament_history_data->{'total_score'};
  my $total_against = $player_tournament_history_data->{'total_against'};

  my $rounding = $ROUNDING_PLACE;

  my $average_for     = sprintf("%.$rounding"."f",  ($total_score / $games_played));
  my $average_against = sprintf("%.$rounding"."f",  ($total_against / $games_played));

  my $under_300 = $player_tournament_history_data->{'over'}->{'300-'};
  my $over_300 = $player_tournament_history_data->{'over'}->{'300'};
  my $over_400 = $player_tournament_history_data->{'over'}->{'400'};
  my $over_500 = $player_tournament_history_data->{'over'}->{'500'};
  my $over_600 = $player_tournament_history_data->{'over'}->{'600'};

  my $win_percentage  = sprintf("%.$rounding"."f",  100 *   ($wins / $games_played));
  my $loss_percentage = sprintf("%.$rounding"."f",  100 *   ($losses / $games_played));
  my $draw_percentage = sprintf("%.$rounding"."f",  100 *    ($draws / $games_played));

  my $under_300_percentage = sprintf("%.$rounding"."f",  100 *   ($under_300 / $games_played));
  my $over_300_percentage = sprintf("%.$rounding"."f",  100 *   ($over_300 / $games_played));
  my $over_400_percentage = sprintf("%.$rounding"."f",  100 *   ($over_400 / $games_played));
  my $over_500_percentage = sprintf("%.$rounding"."f",  100 *    ($over_500 / $games_played));
  my $over_600_percentage = sprintf("%.$rounding"."f",  100 *   ($over_600 / $games_played));

  my $special_games_data = $player_tournament_history_data->{'special_games'};

  my @special_games_keys = ('high_game', 'low_game', 'biggest_win', 'biggest_loss', 'high_loss', 'low_win');

  my $special_games_html_string = "";

  for (my $i = 0; $i < scalar @special_games_keys; $i++)
  {
    my $key = $special_games_keys[$i];
    $special_games_html_string .= HTML::special_game_to_html($key, $special_games_data->{$key});
  }

  my $player_tabclass = "player_tab";
  my $player_tablink  = "player_tablink";

  my $results_html_id      = 'results';
  my $head_to_head_html_id = 'head_to_head';


  my $country_rankings = "";

  my $trigraph_hashref = $COUNTRY_TRIGRAPH_TO_COUNTRY_NAME_HASHREF;
  my $country_fullname = $trigraph_hashref->{$country};

  my $valid_country_html      = "";

  if ($country_fullname)
  {
    $country_rankings = $country_fullname;

    my $country_png = "$html_path/flags/$country.png";
    if ($valid_ranking)
    {
      my $country_rankings_link = $DEFAULT_SHORT_NAME_WORKING_DIR . '/' . $HTML_DIR . '/' . $RANKINGS_HTML_DIR . '/' . "$country.html";
      $country_rankings = "<a href='/$country_rankings_link'>$country_fullname</a>";
    }

    $valid_country_html = 
    "
            <div>
              <IMG SRC='$country_png' alt='$country'>
              <p>$country_rankings</p>
            </div>
    ";

  }

  my $tabs = Utils::make_tab_div([['Results', $results_html_id], ['Head to Head', $head_to_head_html_id]], $player_tabclass, $player_tablink);

  my $player_html_page = "";

  $player_html_page .= <<"STOP";
$doctype
<html $lang>
  <head>
    $meta
    <title>$player_name</title>
    
    $sources
    
    $style
      
    <script >

      $scripts
    
      function show_tournament_entry(id)
      {
        document.getElementById('button_$results_html_id').click();
        \$('#' + id).collapse('show');
      } 

      function show_head_to_head_entry(id)
      {
        document.getElementById('button_$head_to_head_html_id').click();
        \$('#' + id).collapse('show');
      }

      window.onload = function() { document.getElementById('button_$results_html_id').click();}
    </script>
  </head>
  
  <body id='override'>
    $wespa_img
    $nav
    <div style="background-color:#90D1EF">
      <div style="background-color:white;padding-top:10px;" class="container">
        <div class="row">
          <div class="col-xs-8 col-md-8" style="margin-top:10px;margin-bottom:0px">
            <h2>$player_name</h2>
            $valid_country_html
          </div>
          <div class="col-xs-4 col-md-4" style="padding-top:20px;">
            <img src='$html_path/icons/$photo_filename' title='$player_name' alt='$player_name'>
          </div>
        </div>
        <hr>
        <div class="row">
          <div class="col-md-12 col-xs-12 col-sm-12">
            <div>
              <b>Rating:</b> $rating<br>
              <b>Games Played:</b> $games_played<br>
              <b>Wins:</b> $wins ($win_percentage%)<br>
              <b>Losses: </b>$losses ($loss_percentage%)<br>
              <b>Draws:</b> $draws ($draw_percentage%)<br><br>
              <b>Average Score:</b> $average_for<br>
              <b>Average Against:</b> $average_against<br><br>
              <b>300- Games:</b> $under_300 ($under_300_percentage%)<br>
              <b>300  Games:</b> $over_300 ($over_300_percentage%)<br>
              <b>400  Games:</b> $over_400 ($over_400_percentage%)<br>
              <b>500  Games:</b> $over_500 ($over_500_percentage%)<br>
              <b>600+ Games:</b> $over_600 ($over_600_percentage%)<br><br>
              
              
              $special_games_html_string          
            </div>
            <div>
              $tabs
            </div>   
            <div id="$results_html_id" class="$player_tabclass">
              $player_tournament_history_html
            </div>
            <div id="$head_to_head_html_id" class="$player_tabclass">
              $player_head_to_head_history_html
            </div>        
          </div>
        </div>
      </div>
      $footer
    </div>
  </body>
</html>

STOP

  return $player_html_page;

}

sub get_rankings_html_string
{
  my $dbh     = shift;
  my $country = shift;
  
  my @players;

  if ($country)
  {
    @players = @{query_table($dbh, $PLAYERS_TABLE_NAME, 'country', $country)};
  }
  else 
  {
    @players = @{$dbh->selectall_arrayref("SELECT * FROM " . $PLAYERS_TABLE_NAME, {Slice => {}, "RaiseError" => 1})};
  }

  @players = grep { !$_->{'deceased'} && !$_->{'suspended'} && $_->{'current'}} @players;   

  @players = sort { $b->{'rating'} <=> $a->{'rating'} } @players;

  my $full_rankings_string = "      <table class='table'>\n";

  my $titles = ['Ranking', 'Name', 'Country', 'Rating', 'Total Games', 'Last Played'];

  $full_rankings_string .=
    Utils::make_row
    ({
      keys     => $titles,
      is_title => 1,
      class    => 'white'
    });

  for (my $i = 0; $i < scalar @players; $i++)
  {
    my $row_class = 'roweven';
    
    if ($i % 2 == 1)
    {    
      $row_class = 'rowodd';
    }

    my $item = $players[$i];
    $item->{'ranking'} = $i + 1; 
    $full_rankings_string .=
      Utils::make_row
      ({
        item     => $item, 
        keys     => ['ranking', 'name', 'country', 'rating', 'total_games', 'last_played'],
        class    => $row_class
      }); 
  }

  $full_rankings_string    .= "      </table>\n";
  return $full_rankings_string;
}

sub get_rankings_template_html_string
{
  my $rankings_string = shift;
  my $rankings_data   = shift;

  my $html_path = $HTML_PATH_TO_WORKING_DIR;
  my $doctype   = $TEMPLATE_DOCTYPE;
  my $meta      = $TEMPLATE_META;
  my $lang      = $TEMPLATE_LANG;
  my $wespa_img = $TEMPLATE_WESPA_IMAGE;
  my $sources   = $TEMPLATE_SOURCES;
  my $style     = $TEMPLATE_STYLE;
  my $scripts   = $TEMPLATE_SCRIPTS;
  my $nav       = $TEMPLATE_NAV;
  my $footer    = $TEMPLATE_FOOTER;

  my $title                  = $rankings_data->{'title'};
  my $tournament_link        = $rankings_data->{'tournament_link'};

  my $localtime = localtime();
 
  my $rankings_html_page = "";


  $rankings_html_page .= <<"STOP"
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
      
      <div class="container">
        <div class="row">
          <div class="col-xs-12" style="background-color:white;margin-top:10px;margin-bottom:0px">
            <h2><img style="float:right ; margin: 2px 2px 2px 20px;" height="60" width="60" src="$html_path/../wespafb.jpg" alt="WESPA" />$title</h2>	
          </div>
        </div>
      </div>
         
      <div class="container">

        <div class="row">
          <div class="col-xs-12" style="background-color:white;margin-top:0px;margin-bottom:0px">
            Most recent tournament: $tournament_link<br> Updated on $localtime
          </div>
        </div>
 
        <div class="row">
          <div class="table-responsive">
            $rankings_string
          </div>
        </div>
      </div>
      $footer
    </div>
  </body>
</html>

STOP
;
  return $rankings_html_page;

}

sub get_tournament_results_html_string
{
  my $dbh  = shift;
  my $id   = shift;
  my $type = shift;

  my $player_type       = $HTML_ID_PLAYER_TYPE;
  my $tournament_type   = $HTML_ID_TOURNAMENT_TYPE;
  my $head_to_head_type = $HTML_ID_HEAD_TO_HEAD_TYPE;

  my $tr_table_name = $TOURNAMENT_RESULTS_TABLE_NAME;
  my $g_table_name  = $GAMES_TABLE_NAME;
  my $pr_table_name = $PLAYER_RESULTS_TABLE_NAME;
  my $p_table_name  = $PLAYERS_TABLE_NAME;
  my $t_table_name  = $TOURNAMENTS_TABLE_NAME;
  my $d_table_name  = $DIVISIONS_TABLE_NAME;

  my $rounding = $ROUNDING_PLACE;

  my $query =
  "
  SELECT
    tr.player_name                  AS tr_player_name,
    tr.tournament_name              AS tr_tournament_name,
    tr.id                           AS tr_id,
    tr.division_id                  AS tr_division_id,
    tr.player_id                    AS tr_player_id,
    tr.player_name                  AS tr_player_name,
    tr.position                     AS tr_position,
    tr.wins                         AS tr_wins,
    tr.losses                       AS tr_losses,
    tr.byes                         AS tr_byes,
    tr.spread                       AS tr_spread,
    tr.start_rating                 AS tr_start_rating,
    tr.end_rating                   AS tr_end_rating,
    tr.end_rating - tr.start_rating AS tr_rating_change,
    tr.date                         AS tr_date,
    g.round                         AS g_round,
    g.gcg_filename                  AS g_gcg_filename,
    pr1.score                       AS pr1_score,
    pr2.score                       AS pr2_score,
    pr1.result                      AS pr1_result,
    opp.name                        AS opp_name, 
    opp.id                          AS opp_id,
    opp.rating                      AS opp_current_rating,
    tr_opp.start_rating             AS opp_rating,
    t.id                            AS t_id,
    tr.expected_wins                AS tr_expected_wins,
    tr.old_world_rank               AS tr_old_world_rank,
    tr.new_world_rank               AS tr_new_world_rank,
    tr.old_national_rank            AS tr_old_national_rank,
    tr.new_national_rank            AS tr_new_national_rank,
    player.country                  AS p_country
  FROM
    $tr_table_name AS tr, $tr_table_name AS tr_opp, $g_table_name AS g, $pr_table_name AS pr1, $pr_table_name AS pr2, $p_table_name AS opp, $t_table_name AS t, $d_table_name AS d, $p_table_name AS player
  WHERE
    t.id           = d.tournament_id     AND
    d.id           = tr.division_id      AND
    d.id           = tr_opp.division_id  AND
    opp.id         = tr_opp.player_id    AND
    tr.division_id = g.division_id       AND
    tr.player_id   = pr1.player_id       AND
    g.id           = pr1.game_id         AND
    g.id           = pr2.game_id         AND
    pr1.id        != pr2.id              AND
    opp.id         = pr2.player_id       AND
    pr1.player_id  = player.id           AND
  ";

  if ($type == $player_type || $type == $head_to_head_type)
  {
    $query .= " tr.player_id = $id";
  }
  elsif ($type == $tournament_type && $id)
  {
    $query .= " tr.division_id = $id";
  }

  my @raw_tournament_data = @{$dbh->selectall_arrayref($query, {Slice => {}, "RaiseError" => 1})};

  foreach my $data (@raw_tournament_data)
  {
    if ($data->{'tr_start_rating'} <= 0)
    {
      $data->{'tr_rating_change'} = "";
    }
    $data->{'tr_start_rating'}      = Utils::empty_string_if_nonpositive($data->{'tr_start_rating'});
    $data->{'tr_expected_wins'}     = Utils::empty_string_if_nonpositive($data->{'tr_expected_wins'});
    $data->{'tr_old_world_rank'}    = Utils::empty_string_if_nonpositive($data->{'tr_old_world_rank'});
    $data->{'tr_new_world_rank'}    = Utils::empty_string_if_nonpositive($data->{'tr_new_world_rank'});
    $data->{'tr_old_national_rank'} = Utils::empty_string_if_nonpositive($data->{'tr_old_national_rank'});
    $data->{'tr_new_national_rank'} = Utils::empty_string_if_nonpositive($data->{'tr_new_national_rank'});
  }

  # Prepare tournament stats datastructure

  my $tournament_stats;
  my $game_stats_rank_name = $GAME_STATS_RANK_NAME;
  my $stat_key_name        = $STAT_KEY_NAME;

  if ($type == $tournament_type)
  {
    $tournament_stats = Utils::stat_objects();
  }

  # Associate game results with a tournament result

  my $tournament_results_hashref = {};

  foreach my $data (@raw_tournament_data)
  {

    if ($type == $tournament_type)
    {
      foreach my $key (keys %{$tournament_stats})
      {
        my $statitem = $tournament_stats->{$key};
        if ($statitem->{'cond'}->($data))
        {
          my $stat = $statitem->{'eval'}->($data);
          my @value_list = @{$statitem->{'values'}};
          my $statdata = {};
          foreach my $val (@value_list)
          {
            my $dataitem = $data->{$val};
            if ($dataitem)
            {
              $statdata->{$val} = $dataitem;
            }
          }
          $statdata->{'tr_player_id'} = $data->{'tr_player_id'};
          $statdata->{'opp_id'}       = $data->{'opp_id'};
          $statdata->{$stat_key_name} = $stat;

          push @{$statitem->{'list'}}, $statdata;
        } 
      }
    }

    my $key;
    if ($type == $player_type)
    {
      $key = 'tr_division_id';
    }
    elsif ($type == $tournament_type)
    {
      $key = 'tr_player_id';
    }
    elsif ($type == $head_to_head_type)
    {
      $key = 'opp_id';
    }

    if ($type == $tournament_type)
    {
      
    }

    my $item = $tournament_results_hashref->{$data->{$key}};

    # Get the tournament stats

    if ($item)
    {
      push @{$item}, $data;
    }
    else
    {
      $tournament_results_hashref->{$data->{$key}} = [$data];
    }
  }

  # Sort everyting
  if ($type == $tournament_type)
  {
    foreach my $key (keys %{$tournament_stats})
    {
      my $statitem = $tournament_stats->{$key};
      my @statlist = @{$statitem->{'list'}};
      @statlist = sort {$statitem->{sort}->($a, $b)} @statlist;
      for (my $i = 0; $i < scalar @statlist; $i++)
      {
        $statlist[$i]->{$game_stats_rank_name} = $i + 1;
      }
      $statitem->{'list'} = \@statlist;
    }
  }

  my @tournament_results = values %{$tournament_results_hashref};


  if ($type == $player_type)
  {
    @tournament_results = sort {
                                 $b->[0]->{'tr_date'} cmp $a->[0]->{'tr_date'} ||
                                 $a->[0]->{'tr_tournament_name'} cmp $b->[0]->{'tr_tournament_name'}
                               } @tournament_results;
  }
  elsif ($type == $tournament_type)
  {
    # First sort to determine the seeding
    @tournament_results = sort {
                                 if (!$a->[0]->{'tr_start_rating'} && !$b->[0]->{'tr_start_rating'})
                                 {
                                   $a->[0]->{'tr_player_name'}         cmp $b->[0]->{'tr_player_name'};
                                 }
                                 elsif (!$a->[0]->{'tr_start_rating'})
                                 {
                                   return 1;
                                 }
                                 elsif (!$b->[0]->{'tr_start_rating'})
                                 {
                                   return -1;
                                 }
                                 else
                                 {
                                   return
                                   $b->[0]->{'tr_start_rating'} <=> $a->[0]->{'tr_start_rating'} ||
                                   $a->[0]->{'tr_player_name'}         cmp $b->[0]->{'tr_player_name'}
                                 }
                               }
                          @tournament_results;

    for (my $i = 0; $i < scalar @tournament_results; $i++)
    {
      my @games = @{$tournament_results[$i]};
      for (my $k = 0; $k < scalar @games; $k++)
      {
        $tournament_results[$i]->[$k]->{'tr_seed'} = $i + 1;
      }
    } 

    @tournament_results = sort {$a->[0]->{'tr_position'} <=> $b->[0]->{'tr_position'}} @tournament_results;
    my $num_players = scalar @tournament_results;
    foreach my $tr (@tournament_results)
    {
      my $l = scalar @{$tr};
      for (my $n = 0; $n < $l; $n++)
      {
        $tr->[$n]->{'tr_position'} = $tr->[$n]->{'tr_position'} . " of $num_players";
      }
    }
  }
  elsif ($type == $head_to_head_type)
  {
    @tournament_results = sort {scalar @{$b} <=> scalar @{$a}} @tournament_results;
  }


  foreach my $games (@tournament_results)
  {
    my @unsorted_games = @{$games};
    my @sorted_games;
    if ($type == $player_type || $type == $tournament_type)
    {
      @sorted_games = sort {$a->{'g_round'} <=> $b->{'g_round'}} @unsorted_games;
    }
    elsif ($type == $head_to_head_type)
    {
      @sorted_games = sort {$a->{'tr_date'} cmp $b->{'tr_date'} || $a->{'g_round'} <=> $b->{'g_round'}} @unsorted_games;
    }

    $games = \@sorted_games;
  }

  # Move to constants plz

  my $tournament_title_ref = ['Details', '#', 'Date', 'Tournament', 'Wins', 'Losses', 'Byes', 'Spread', 'Place', 'Start Rating', 'End Rating', 'Rating Change'];
  my $tournament_keys_ref  = ['details', '#', 'tr_date', 'tr_tournament_name', 'tr_wins', 'tr_losses', 'tr_byes', 'tr_spread', 'tr_position', 'tr_start_rating', 'tr_end_rating', 'tr_rating_change'];

  my $tournament_standings_title_ref = ['Details', 'Place'      ,    'Seed', 'Name',              'Wins',    'Losses',    'Byes',    'Spread',    'Start Rating', 'End Rating', 'Rating Change'];
  my $tournament_standings_keys_ref  = ['details', 'tr_position', 'tr_seed', 'tr_player_name', 'tr_wins', 'tr_losses', 'tr_byes', 'tr_spread', 'tr_start_rating', 'tr_end_rating', 'tr_rating_change'];

  my $games_title_ref = ['Round', 'Opponent', 'Opponent Rating', 'Result', 'Scores', ''];
  my $games_keys_ref  = ['g_round', 'opp_name', 'opp_rating',  'pr1_result', 'pr1_score', 'pr2_score'];

  my $head_to_head_title_ref = ['Details', '', 'Opponent', 'Rating', 'Games', 'Wins', 'Losses', 'Draws', 'Pct', 'Average For', 'Average Against'];
  my $head_to_head_keys_ref  = ['details', '#', 'opp_name', 'opp_current_rating', 'hh_games', 'hh_wins', 'hh_losses', 'hh_draws', 'hh_pct', 'hh_af', 'hh_aa'];

  my $head_to_head_games_title_ref = ['Date', 'Tournament', 'Round', 'Result', 'Rating', 'Opponent Rating', 'Score', ''];
  my $head_to_head_games_keys_ref  = ['tr_date', 'tr_tournament_name','g_round', 'pr1_result', 'tr_start_rating', 'opp_rating', 'pr1_score', 'pr2_score'];


  my $ratings_super_title_ref = ['Player', 'Wins', 'World rank', 'Nation rank', 'Rating points'];
  my $ratings_title_ref = ['Country', 'Name', 'Exp', 'Act', 'Old', 'New', 'Old', 'New', 'Old', '+/-', 'New'];
  my $ratings_keys_ref   = ['p_country', 'tr_player_name', 'tr_expected_wins', 'tr_wins', 'tr_old_world_rank', 'tr_new_world_rank', 'tr_old_national_rank', 'tr_new_national_rank', 'tr_start_rating', 'tr_rating_change', 'tr_end_rating'];


  my $tournament_results_list_html_string = "<table class='table'>\n";
  my $tournament_ratings_html_string      = "<table class='table'>\n";

  my $title_ref = $tournament_title_ref;
  my $sub_title_ref = $games_title_ref;
  my $keys_ref = $tournament_keys_ref;

  if ($type == $head_to_head_type)
  {
    $title_ref = $head_to_head_title_ref;
    $sub_title_ref = $head_to_head_games_title_ref;
    $keys_ref = $head_to_head_keys_ref;
    $games_keys_ref = $head_to_head_games_keys_ref;
  }
  elsif ($type == $tournament_type)
  {
    $title_ref = $tournament_standings_title_ref;
    $keys_ref = $tournament_standings_keys_ref;
    $tournament_ratings_html_string .=
      Utils::make_row
      ({
        keys     => $ratings_super_title_ref,
        is_title => 1,
        class    => 'white',
        colspan  => 2
      });
    

    $tournament_ratings_html_string .=
      Utils::make_row
      ({
        keys     => $ratings_super_title_ref,
        is_title => 1,
        class    => 'white'
      });
  }

  my $title_length = scalar @{$title_ref};

  $tournament_results_list_html_string .=
      Utils::make_row
      ({
        keys     => $ratings_super_title_ref,
        is_title => 1,
        class    => 'white'
      });

  my $games_title_row = 
      Utils::make_row
      ({
        keys     => $ratings_super_title_ref,
        is_title => 1
      });

  my $game_data =
  {
    'tournament_name' => $tournament_results[0]->[0]->{'tr_tournament_name'},
    'tournament_date' => $tournament_results[0]->[0]->{'tr_date'},
    'games_played'    => 0,
    'wins'            => 0,
    'losses'          => 0,
    'draws'           => 0,
    'total_score'     => 0,
    'total_against'   => 0,
    'over'            =>
    {
      '300-' => 0,
      '300'  => 0,
      '400'  => 0,
      '500'  => 0,
      '600'  => 0
    },
    'special_games' =>
    {
      'high_game'     =>
      {
        'value' => -1000000,
      },
      'low_game'      =>
      {
        'value' => 1000000,
      },
      'biggest_win'   =>
      {
        'value' => -1000000,
      },
      'biggest_loss'  =>
      {
        'value' => -1000000,
      },
      'high_loss'     =>
      {
        'value' => -1000000,
      },
      'low_win'       =>
      {
        'value' =>  1000000,
      }
    }
  };

  for (my $i = 0; $i < scalar @tournament_results; $i++)
  {
    my $new_entry = "";

    my $subentries = "";

    my $games_ref = $tournament_results[$i];
    my $button_id = Utils::create_html_id($HTML_ID_BUTTON_TAG, $type, $games_ref->[0]->{'tr_id'});
    my $entry_id  = Utils::create_html_id($HTML_ID_ENTRY_TAG,  $type, $games_ref->[0]->{'tr_id'});
    my $row_class = 'roweven';
    
    if ($i % 2 == 1)
    {
      $row_class = 'rowodd';
    }

    if ($type == $head_to_head_type)
    {
      $button_id = Utils::create_html_id($HTML_ID_BUTTON_TAG, $type, $games_ref->[0]->{'opp_id'});
      $entry_id = Utils::create_html_id($HTML_ID_ENTRY_TAG,   $type, $games_ref->[0]->{'opp_id'});
    }

    $games_ref->[0]->{'#'} = $i + 1;

    $games_ref->[0]->{'details'} = "<button type='button' id='$button_id'  class='btn btn-info' data-toggle='collapse' data-target='#" . $entry_id  . "'>+</button>";


    if ($type != $head_to_head_type)
    {
      $new_entry .= Utils::make_new_entry_head({games_ref       => $games_ref,
                                                keys_ref        => $keys_ref,
                                                row_class       => $row_class,
                                                entry_id        => $entry_id,
                                                title_length    => $title_length,
                                                games_title_row => $games_title_row});
    }

    if ($type == $tournament_type)
    {
      $tournament_ratings_html_string .=
        Utils::make_row
        ({
          item     => $games_ref->[0],
          keys     => $ratings_keys_ref,
          class    => 'white'
        });
    }


    my $num_games = scalar @{$games_ref};

    my $hh_wins   = 0;
    my $hh_losses = 0;
    my $hh_draws  = 0;
    my $hh_for    = 0;
    my $hh_ag     = 0;

    for (my $k = 0; $k < $num_games; $k++)
    {
      my $item = $games_ref->[$k];

      # Special games data includes:
      # High Game
      # Low Game
      # Biggest Win
      # Biggest Loss
      # High Loss
      # Low Win

      my $high_game_item    = $game_data->{'special_games'}->{'high_game'};
      my $low_game_item     = $game_data->{'special_games'}->{'low_game'};
      my $biggest_win_item  = $game_data->{'special_games'}->{'biggest_win'};
      my $biggest_loss_item = $game_data->{'special_games'}->{'biggest_loss'};
      my $high_loss_item    = $game_data->{'special_games'}->{'high_loss'};
      my $low_win_item      = $game_data->{'special_games'}->{'low_win'};
      my $over_item         = $game_data->{'over'};

      $game_data->{'games_played'}++;

      my $res  = $item->{'pr1_result'};

      if ($res == 1)
      {
        $res = 'W';
        $game_data->{'wins'}++;
        if ($type == $head_to_head_type)
        {
          $hh_wins++;
        }
      }
      elsif ($res == -1)
      {
        $res = 'L';
        $game_data->{'losses'}++;
        if ($type == $head_to_head_type)
        {
          $hh_losses++;
        }
      }
      else
      {
        $res = 'T';
        $game_data->{'draws'}++;
        if ($type == $head_to_head_type)
        {
          $hh_draws++;
        }
      }
      
      $item->{'pr1_result'} = $res;

      my $score     = $item->{'pr1_score'};
      my $opp_score = $item->{'pr2_score'};

      $game_data->{'total_score'}   += $score;      
      $game_data->{'total_against'} += $opp_score;

      $hh_for += $score;
      $hh_ag  += $opp_score;

      if ($score < 300)
      {
        $game_data->{'over'}->{'300-'}++;
      }
      elsif ($score >= 300 && $score < 400)
      {
        $game_data->{'over'}->{'300'}++;
      }
      elsif ($score >= 400 && $score < 500)
      {
        $game_data->{'over'}->{'400'}++;
      }
      elsif ($score >= 500 && $score < 600)
      {
        $game_data->{'over'}->{'500'}++;
      }
      elsif ($score >= 600)
      {
        $game_data->{'over'}->{'600'}++;
      }

      if ($score > $high_game_item->{'value'})
      {
        $high_game_item->{'value'} = $score;
        HTML::populate_special_game_item($high_game_item, $item);
      }
      if ($score < $low_game_item->{'value'})
      {
        $low_game_item->{'value'} = $score;
        HTML::populate_special_game_item($low_game_item, $item);
      }
      if ($score - $opp_score > $biggest_win_item->{'value'})
      {
        $biggest_win_item->{'value'} = $score - $opp_score;
        HTML::populate_special_game_item($biggest_win_item, $item);
      }
      if ($opp_score - $score > $biggest_loss_item->{'value'})
      {
        $biggest_loss_item->{'value'} = $opp_score - $score;
        HTML::populate_special_game_item($biggest_loss_item, $item);
      }
      if ($opp_score > $score && $score > $high_loss_item->{'value'})
      {
        $high_loss_item->{'value'} = $score;
        HTML::populate_special_game_item($high_loss_item, $item);
      }
      if ($score > $opp_score && $score < $low_win_item->{'value'})
      {
        $low_win_item->{'value'} = $score;
        HTML::populate_special_game_item($low_win_item, $item);
      }

      my $sub_row_class = 'roweven';
    
      if ($k % 2 == 1)
      {
        $sub_row_class = 'rowodd';
      }

      $subentries .=
        Utils::make_row
        ({
          item     => $item,
          keys     => $games_keys_ref,
          class    => $sub_row_class
        });

      if ($k == $num_games - 1)
      {
        my $colspan = (scalar @{$games_keys_ref}) - 3;
        my $af = sprintf ("%.".$rounding."f", $hh_for / $num_games);
        my $ag = sprintf ("%.".$rounding."f", $hh_ag  / $num_games);
        $subentries .=
        "<tr>
           <td colspan='$colspan'></td>
           <td><b>Average:</b></td>
           <td><b>$af</b></td>
           <td><b>$ag</b></td>
        </tr>";
      }
    }

    if ($type == $head_to_head_type)
    {
      $games_ref->[0]->{hh_games}  = $num_games;
      $games_ref->[0]->{hh_wins}   = $hh_wins;
      $games_ref->[0]->{hh_losses} = $hh_losses;
      $games_ref->[0]->{hh_draws}  = $hh_draws;
      $games_ref->[0]->{hh_pct}    = sprintf ("%.".$rounding."f", ($hh_wins + ($hh_draws / 2)) / $num_games);
      $games_ref->[0]->{hh_af}     = sprintf ("%.".$rounding."f", $hh_for / $num_games);
      $games_ref->[0]->{hh_aa}     = sprintf ("%.".$rounding."f", $hh_ag  / $num_games);

      $new_entry .= Utils::make_new_entry_head({games_ref       => $games_ref,
                                                keys_ref        => $keys_ref,
                                                row_class       => $row_class,
                                                entry_id        => $entry_id,
                                                title_length    => $title_length,
                                                games_title_row => $games_title_row});
    }

    $tournament_results_list_html_string .= $new_entry . $subentries . "</table></div></td></tr>\n";
  }

  $tournament_results_list_html_string .= "\n</table>\n";

  my $tournament_stats_html = {};

  if ($type == $tournament_type)
  {

    $tournament_ratings_html_string .= "\n</table>\n";

    foreach my $key (keys %{$tournament_stats})
    {
      my $dataitem = $tournament_stats->{$key};
      my $html_string = "       <table class='table'>\n";
      $html_string    .=
        Utils::make_row
        ({
          keys     => $dataitem->{'titles'},
          is_title => 1
        });

      my @statlist = @{$dataitem->{'list'}};
      for (my $i = 0; $i < scalar @statlist; $i++)
      {
        my $sub_row_class = 'roweven';
    
        if ($i % 2 == 1)
        {
          $sub_row_class = 'rowodd';
        }

        my $statitem = $statlist[$i];
        $html_string .=
          Utils::make_row
          ({
            item     => $statitem,
            keys     => $dataitem->{'values'},
            class    => $sub_row_class
          });
      }
      $html_string .= "        </table>";

      $tournament_stats_html->{$key} = $html_string;
    }
  }
  return [$tournament_results_list_html_string, $game_data, $tournament_stats_html, $tournament_ratings_html_string];
}

sub get_tournament_template_html_string
{
  my $division_data = shift;
 
  my $html_path = $HTML_PATH_TO_WORKING_DIR;
  my $doctype   = $TEMPLATE_DOCTYPE;
  my $meta      = $TEMPLATE_META;
  my $lang      = $TEMPLATE_LANG;
  my $wespa_img = $TEMPLATE_WESPA_IMAGE;
  my $sources   = $TEMPLATE_SOURCES;
  my $style     = $TEMPLATE_STYLE;
  my $scripts   = $TEMPLATE_SCRIPTS;
  my $nav       = $TEMPLATE_NAV;
  my $footer    = $TEMPLATE_FOOTER;

  my $tournament_name = $division_data->[0]->[1]->{'tournament_name'};
  my $tournament_date = $division_data->[0]->[1]->{'tournament_date'};
 
  my $division_html_class = "division";

  my $ddl = scalar @{$division_data};

  my $division_results   = "";

  my @ids_to_click = ();
  
  my $display_none_style = "style='display:none;'";

  my $tourney_tabclass  = "tournament_tab";
  my $tourney_tablink   = "tournament_tablink";


  my @tabdata = ();

  for (my $i = 0; $i < $ddl; $i++)
  {
    my $id   = "division_$i";
    my $text = "Division ". ($i+1);

    push @tabdata, [$text, $id];

    my $stats_tabclass    = "stats_tab_"        . $id ;
    my $stats_tablink     = "stats_tablink_"    . $id ;
    my $ratings_tabclass  = "ratings_tab_"      . $id ;
    my $ratings_tablink   = "ratings_tablink_"  . $id ;
    my $division_tabclass = "division_tab_"     . $id ;
    my $division_tablink  = "division_tablink_" . $id ;
 
    if ($i == 0)
    {
      push @ids_to_click, "button_$id";
    }
    my $div_html    = $division_data->[$i]->[0];
    my $div_data    = $division_data->[$i]->[1];
    my $div_stats   = $division_data->[$i]->[2];
    my $div_ratings = $division_data->[$i]->[3];

    my $stats_content = "";
    my @stats_tabdata = ();

    my $stats_order_ref = $TOURNAMENT_STATS_ORDER;

    for (my $k = 0; $k < scalar @{$stats_order_ref}; $k++)
    {
      my $cat = $stats_order_ref->[$k];
      my $stat_id = "division_$i" . "_stats_$cat";
      push @stats_tabdata, [$cat, $stat_id];

      my $stat_html = $div_stats->{$cat};
      $stats_content .= "<div id='$stat_id' class='$stats_tabclass' $display_none_style>$stat_html</div>\n";
      if ($k == 0)
      {
        push @ids_to_click, "button_$stat_id";
      }
    }

    $stats_content = Utils::make_tab_div(\@stats_tabdata, $stats_tabclass, $stats_tablink) . $stats_content;

    my $div_standings_id = "division_$i" . "_standings";
    my $div_stats_id     = "division_$i" . "_stats";
    my $div_ratings_id   = "division_$i" . "_ratings";

    push @ids_to_click, "button_$div_standings_id";

    my $div_tabs = Utils::make_tab_div([["Standings", $div_standings_id],["Statistics", $div_stats_id], ["Ratings", $div_ratings_id]], $division_tabclass, $division_tablink);

    my $div_standings_div = "<div id='$div_standings_id' class='$division_tabclass' $display_none_style>$div_html     </div>";
    my $div_stats_div     = "<div id='$div_stats_id'     class='$division_tabclass' $display_none_style>$stats_content</div>";
    my $div_ratings_div   = "<div id='$div_ratings_id'   class='$division_tabclass' $display_none_style>$div_ratings  </div>";


    my $div_content = $div_tabs . $div_standings_div . $div_stats_div . $div_ratings_div;

    $division_results .= "<div id='$id' class='$tourney_tabclass'>$div_content</div>\n";
  }

  my $tabs = Utils::make_tab_div(\@tabdata, $tourney_tabclass, $tourney_tablink);

  my $ids_to_click_javascript_array = "[";

  for (my $i = 0; $i < scalar @ids_to_click; $i++)
  {
    my $id = $ids_to_click[$i];
    $ids_to_click_javascript_array .= "'$id'";
    if ($i != (scalar @ids_to_click) - 1)
    {
      $ids_to_click_javascript_array .= ", ";
    }
  }

  $ids_to_click_javascript_array .= "]";

  my $tournament_html_page = "";

  $tournament_html_page .= <<"STOP";
$doctype
<html>
  <head>
  $meta
  <title>$tournament_name</title>
  
  $sources
  
  $style
  
  <script type="text/javascript">
 
    $scripts

   
    window.onload = function()
    { 
      var ids = $ids_to_click_javascript_array;
      for (var i = 0; i < ids.length; i++)
      {
        var id = ids[i];
        document.getElementById(id).click();
      }
    }
  </script>

  </head>
  
  <body id='override'>
    $wespa_img
    $nav
    <div style="background-color:#90D1EF">
      <div style="background-color:white;padding-top:10px;" class="container">
        <h2>$tournament_name ($tournament_date)</h2>
        <hr>
        <div class="row">
          <div class="col-md-12 col-xs-12 col-sm-12">
            <div>
              <br>
              $tabs
              <br>    
            </div>
            $division_results
          </div>
        </div>
      </div>
      $footer
    </div>
  </div>
  </body>
</html>

STOP

  return $tournament_html_page;

}

sub populate_special_game_item
{
  my $special_item = shift;
  my $item         = shift;

  $special_item->{'game_pointer'}     = $item->{'tr_id'};
  $special_item->{'player_pointer'}   = $item->{'opp_id'};
  $special_item->{'player_name'}      = $item->{'opp_name'};

  return 1;
}

sub special_game_to_html
{
  my $key  = shift;
  my $item = shift;

  if (!$item->{'player_name'} || !$item->{'player_pointer'} || !$item->{'game_pointer'})
  {
    return "";
  }

  my @words = split /_/, $key;

  my @cap_words = ();

  for (my $i = 0; $i < scalar @words; $i++)
  {
    my @letters = split //, $words[$i];
    $letters[0] = uc $letters[0];
    push @cap_words, (join "", @letters);
  }

  my $title = join " ", @cap_words;

  my $value          = $item->{'value'};
  my $player_name    = $item->{'player_name'};
  my $player_pointer = $item->{'player_pointer'};


  my $player_type       = $HTML_ID_PLAYER_TYPE;
  my $head_to_head_type = $HTML_ID_HEAD_TO_HEAD_TYPE;

  my $game_html_id   = Utils::create_html_id($HTML_ID_ENTRY_TAG, $player_type, $item->{'game_pointer'});
  my $player_html_id = Utils::create_html_id($HTML_ID_ENTRY_TAG, $head_to_head_type, $item->{'player_pointer'});

  my $working_dir = $DEFAULT_SHORT_NAME_WORKING_DIR;
  my $html_dir    = $HTML_DIR;
  my $players_dir = $PLAYER_HTML_DIR;

  if (
       ($title eq "Biggest Win"  && $value < 0) ||
       ($title eq "Biggest Loss" && $value > 0) 
     )
  {
    return "";
  } 

  return "<b>$title:</b> <a href=\"#$game_html_id\" onclick=\"show_tournament_entry('$game_html_id')\">$value</a> (<a href=\"#$player_html_id\" onclick=\"show_head_to_head_entry('$player_html_id')\">vs</a> <a href=\"/$working_dir/$html_dir/$players_dir/$player_pointer.html\">$player_name</a>)<br>";
  
}

1;