#!/usr/bin/perl

# This script is based off of stats.cgi in /srv/dev/aardvark/cgi-bin/stats.cgi
#
use strict;
use warnings;
use lib './modules';
use Constants;

require './scripts/utils.pl';

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


  my $player_type       = Constants::HTML_ID_PLAYER_TYPE;
  my $head_to_head_type = Constants::HTML_ID_HEAD_TO_HEAD_TYPE;

  my $game_html_id   = create_html_id(Constants::HTML_ID_ENTRY_TAG, $player_type, $item->{'game_pointer'});
  my $player_html_id = create_html_id(Constants::HTML_ID_ENTRY_TAG, $head_to_head_type, $item->{'player_pointer'});

  my $working_dir = Constants::DEFAULT_SHORT_NAME_WORKING_DIR;
  my $html_dir    = Constants::HTML_DIR;
  my $players_dir = Constants::PLAYER_HTML_DIR;

  return "<b>$title:</b> <a href=\"#$game_html_id\" onclick=\"show_tournament_entry('$game_html_id')\">$value</a> (<a href=\"#$player_html_id\" onclick=\"show_head_to_head_entry('$player_html_id')\">vs</a> <a href=\"/$working_dir/$html_dir/$players_dir/$player_pointer.html\">$player_name</a>)<br>";
  
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

sub get_player_template_html_string
{
  my $player_info = shift;
  my $player_tournament_history_html = shift;
  my $player_head_to_head_history_html = shift;
  my $player_tournament_history_data = shift;

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

  my $rounding = Constants::ROUNDING_PLACE;

  my $average_for     = sprintf("%.$rounding"."f",  ($total_score / $games_played));
  my $average_against = sprintf("%.$rounding"."f",  ($total_against / $games_played));

  my $over_300 = $player_tournament_history_data->{'over'}->{'300'};
  my $over_400 = $player_tournament_history_data->{'over'}->{'400'};
  my $over_500 = $player_tournament_history_data->{'over'}->{'500'};
  my $over_600 = $player_tournament_history_data->{'over'}->{'600'};

  my $win_percentage  = sprintf("%.$rounding"."f",  100 *   ($wins / $games_played));
  my $loss_percentage = sprintf("%.$rounding"."f",  100 *   ($losses / $games_played));
  my $draw_percentage = sprintf("%.$rounding"."f",  100 *    ($draws / $games_played));

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
    $special_games_html_string .= special_game_to_html($key, $special_games_data->{$key});
  }

  my $player_tabclass = "player_tab";
  my $player_tablink  = "player_tablink";

  my $results_html_id      = 'results';
  my $head_to_head_html_id = 'head_to_head';

  my $no_country_filename = Constants::NO_COUNTRY_FILENAME;

  my $country_rankings = "";

  my $country_png      = "$html_path/flags/$no_country_filename";

  my $trigraph_hashref = Constants::COUNTRY_TRIGRAPH_TO_COUNTRY_NAME_HASHREF;
  my $country_fullname = $trigraph_hashref->{$country};

  my $valid_country_html      = "";

  if ($country_fullname)
  {
    $country_rankings = $country_fullname;

    $country_png = "$html_path/flags/$country.png";
    if ($valid_ranking)
    {
      my $country_rankings_link = Constants::DEFAULT_SHORT_NAME_WORKING_DIR . '/' . Constants::HTML_DIR . '/' . Constants::RANKINGS_HTML_DIR . '/' . "$country.html";
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

  my $tabs = make_tab_div([['Results', $results_html_id], ['Head to Head', $head_to_head_html_id]], $player_tabclass, $player_tablink);

  my $player_html_page = "";

  $player_html_page .= <<STOP;
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
              <b>300 Games:</b> $over_300 ($over_300_percentage%)<br>
              <b>400 Games:</b> $over_400 ($over_400_percentage%)<br>
              <b>500 Games:</b> $over_500 ($over_500_percentage%)<br>
              <b>600 Games:</b> $over_600 ($over_600_percentage%)<br><br>
              
              
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


sub get_tournament_template_html_string
{
  my $division_data = shift;
 
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

    my $stats_order_ref = Constants::TOURNAMENT_STATS_ORDER;

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

    $stats_content = make_tab_div(\@stats_tabdata, $stats_tabclass, $stats_tablink) . $stats_content;

    my $div_standings_id = "division_$i" . "_standings";
    my $div_stats_id     = "division_$i" . "_stats";
    my $div_ratings_id   = "division_$i" . "_ratings";

    push @ids_to_click, "button_$div_standings_id";

    my $div_tabs = make_tab_div([["Standings", $div_standings_id],["Statistics", $div_stats_id], ["Ratings", $div_ratings_id]], $division_tabclass, $division_tablink);

    my $div_standings_div = "<div id='$div_standings_id' class='$division_tabclass' $display_none_style>$div_html     </div>";
    my $div_stats_div     = "<div id='$div_stats_id'     class='$division_tabclass' $display_none_style>$stats_content</div>";
    my $div_ratings_div   = "<div id='$div_ratings_id'   class='$division_tabclass' $display_none_style>$div_ratings  </div>";


    my $div_content = $div_tabs . $div_standings_div . $div_stats_div . $div_ratings_div;

    $division_results .= "<div id='$id' class='$tourney_tabclass'>$div_content</div>\n";
  }

  my $tabs = make_tab_div(\@tabdata, $tourney_tabclass, $tourney_tablink);

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

  $tournament_html_page .= <<STOP;
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

sub get_rankings_template_html_string
{
  my $rankings_string = shift;
  my $rankings_data   = shift;

  my $title                  = $rankings_data->{'title'};
  my $tournament_link        = $rankings_data->{'tournament_link'};

  my $localtime = localtime();
 
  my $rankings_html_page = "";


  $rankings_html_page .= <<STOP;
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

  return $rankings_html_page;

}


1;


