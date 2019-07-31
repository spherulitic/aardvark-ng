#!/usr/bin/perl

# This script is based off of stats.cgi in /srv/dev/aardvark/cgi-bin/stats.cgi
#
use strict;
use warnings;
use lib './modules';
use Constants;

require './scripts/utils.pl';

my $html_path = Constants::HTML_PATH_TO_WORKING_DIR;

my $doctype = <<DOCTYPE
<!DOCTYPE html>
DOCTYPE
;

my $meta = "";

my $lang = "lang=\"en\"";

my $wespa_img = <<WESPA_IMG
    <div class="container-topper">
      <div style="margin: auto;width: 80px;">
        <img class="img-responsive" src="$html_path/../wespafb.jpg" width="80" height="80" alt="WESPA">
      </div>
    </div>
WESPA_IMG
;

my $sources = <<SOURCES

<script  src="$html_path/js/tabber.js"></script>
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="stylesheet" type="text/css" href="$html_path/aardvark.css">
<link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/css/bootstrap.min.css">
<link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/font-awesome/4.7.0/css/font-awesome.min.css">
<script src="https://ajax.googleapis.com/ajax/libs/jquery/3.2.0/jquery.min.js"></script>
<script src="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/js/bootstrap.min.js"></script>


SOURCES
;

my $style = <<STYLE

<style >

	.navbar {margin-bottom: 0px;}
	.federation-row { padding-top:10px;
					  padding-bottom:10px;
					 
	}
	.navbar-nav>li>a {
		color: black ;
	}
	td
	{
		padding: 0px;
	}

</style>  
STYLE
;

my $scripts = <<SCRIPTS

      \$(document).ready(function () {
      
        \$('.collapse').on('shown.bs.collapse', function (e) {
        
          var id = e.target.id;
      
          id = id.replace('entry', 'button'); 
          var el = document.getElementById(id);
          el.innerHTML = '&#8722';
        
        });
        
        \$('.collapse').on('hidden.bs.collapse', function (e) {
      
          var id = e.target.id;
      
          id = id.replace('entry', 'button'); 
          var el = document.getElementById(id);
          el.innerHTML = '+';
         
        });
      });

      function showContent(evt, id, content_classname, links_classname)
      {
        var i, tabcontent, tablinks;
        tabcontent = document.getElementsByClassName(content_classname);
        for (i = 0; i < tabcontent.length; i++)
        {
          tabcontent[i].style.display = "none";
        }
        tablinks = document.getElementsByClassName(links_classname);
        for (i = 0; i < tablinks.length; i++)
        {
          tablinks[i].className = tablinks[i].className.replace(" active", "");
        }
        document.getElementById(id).style.display = "block";
        evt.currentTarget.className += " active";
      }


SCRIPTS
;

my $nav     = <<NAV
<div class="navbar navbar-default" style="background:#e8e6e6;">
  <div class="container-fluid">
    <div class="navbar-header">
      <button type="button" class="navbar-toggle" data-toggle="collapse" data-target="#myNavbar">
        <span class="icon-bar"></span>
        <span class="icon-bar"></span>
        <span class="icon-bar"></span>
        <span class="icon-bar"></span>
        <span class="icon-bar"></span>   
        <span class="icon-bar"></span>   
        <span class="icon-bar"></span>   		
      </button>
    </div>
    <div class="collapse navbar-collapse" id="myNavbar">
      <ul class="nav navbar-nav">
        <li><a href="http://www.wespa.org/index.shtml">Home</a></li>
        <li class="dropdown">
          <a class="dropdown-toggle" data-toggle="dropdown" href="#">About Us <span class="caret"></span></a>
          <ul class="dropdown-menu">
            <li><a href="http://www.wespa.org/associations.shtml">Associations</a></li>
            <li><a href="http://www.wespa.org/committees.shtml">Committees</a></li>
            <li><a href="http://www.wespa.org/joinwespa.shtml">Join Us</a></li>
            <li><a href="http://www.wespa.org/credits.shtml">Credits</a></li>
          </ul>
        </li>
        <li><a href="http://www.wespa.org/news.shtml">News</a></li>
        <li class="dropdown">
          <a class="dropdown-toggle" data-toggle="dropdown" href="#">Tournaments <span class="caret"></span></a>
          <ul class="dropdown-menu">
            <li><a href="http://www.wespa.org/tournaments/index.shtml">Calendar</a></li>
            <li><a href="http://www.wespa.org/ratings.shtml">Ratings</a></li>
          </ul>
        </li>
        <li><a href="http://www.wespa.org/resources.shtml">Resources</a></li>
        <li><a href="http://www.wespa.org/youth.shtml">Youth Scrabble</a></li>
        <li><a href="http://www.wespa.org/products.shtml">Products</a></li>
      </ul>
      <ul class="nav navbar-nav navbar-right">
        <li><a href="http://www.wespa.org/contactus.shtml"><span class="glyphicon glyphicon-envelope"></span></a></li>
      </ul>
    </div>
  </div>
</div>
NAV
;

my $footer  = <<FOOTER
<div class="container-fluid" style="background-color:white;">
     
        <p class="small">&copy; WESPA <br><br>SCRABBLE&reg; is a registered trademark. All intellectual property rights in and to the game are owned in the US by Hasbro Inc, in Canada by Hasbro Canada Inc and throughout the rest of the world by JW Spear &amp; Sons Ltd of Maidenhead, SL6 4UB, England, a subsidiary of Mattel Inc. Mattel and Spear are not affiliated with Hasbro or Hasbro Canada.</p>
     
</div>
FOOTER
;

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
        showContent(event, '$results_html_id');
        \$('#' + id).collapse('show');
      } 

      function show_head_to_head_entry(id)
      {
        showContent(event, '$head_to_head_html_id');
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
            <div>
              <IMG SRC="$html_path/flags/$country_trigraph.png" alt="$country">
              <p>$country</p>
            </div>
          </div>
          <div class="col-xs-4 col-md-4" style="padding-top:20px;">
            <img src='$html_path/icons/$photo_filename' title='$player_name' alt='$player_name'>
          </div>
        </div>
        <hr>
        <div class="row">
          <div class="col-md-12 col-xs-12 col-sm-12">
            <div>
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
 
  my $division_html_class = "division";

  my $ddl = scalar @{$division_data};

  my $division_results   = "";

  my $first_id;


  my $tourney_tabclass  = "tournament_tab";
  my $tourney_tablink   = "tournament_tablink";


  my @tabdata = ();

  for (my $i = 0; $i < $ddl; $i++)
  {
    my $id   = "division_$i";
    my $text = "Division ". ($i+1);

    push @tabdata, [$text, $id];

    my $stats_tabclass = "stats_tab_" . $id ;
    my $stats_tablink  = "stats_tablink_" . $id ;
    my $division_tabclass = "division_tab_" . $id ;
    my $division_tablink  = "division_tablink_" . $id ;
 
    if ($i == 0)
    {
      $first_id = $id;
    }
    my $div_html  = $division_data->[$i]->[0];
    my $div_data  = $division_data->[$i]->[1];
    my $div_stats = $division_data->[$i]->[2];
    my $stats_content = "";
    my @stats_tabdata = ();

    my $stats_order_ref = Constants::TOURNAMENT_STATS_ORDER;

    for (my $k = 0; $k < scalar @{$stats_order_ref}; $k++)
    {
      my $cat = $stats_order_ref->[$k];
      my $stat_id = "division_$i" . "_stats_$cat";
      push @stats_tabdata, [$cat, $stat_id];

      my $stat_html = $div_stats->{$cat};
      $stats_content .= "<div id='$stat_id' class='$stats_tabclass' style='display: none;'>$stat_html</div>\n";
 
    }

    $stats_content = make_tab_div(\@stats_tabdata, $stats_tabclass, $stats_tablink) . $stats_content;

    my $div_standings_id = "division_$i" . "_standings";
    my $div_stats_id     = "division_$i" . "_stats";

    my $div_tabs = make_tab_div([["Standings", $div_standings_id],["Statistics", $div_stats_id]], $division_tabclass, $division_tablink);

    my $div_standings_div = "<div id='$div_standings_id' class='$division_tabclass'>$div_html</div>";
    my $div_stats_div     = "<div id='$div_stats_id' class='$division_tabclass'>$stats_content</div>";


    my $div_content = $div_tabs . $div_standings_div . $div_stats_div;

    $division_results .= "<div id='$id' class='$tourney_tabclass'>$div_content</div>\n";
  }

  my $tabs = make_tab_div(\@tabdata, $tourney_tabclass, $tourney_tablink);

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

    window.onload = function() { document.getElementById('button_$first_id').click();}
  </script>

  </head>
  
  <body id='override'>
    $wespa_img
    $nav
    <div style="background-color:#90D1EF">
      <div style="background-color:white;padding-top:10px;" class="container">
        <h2>$tournament_name</h2>
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


