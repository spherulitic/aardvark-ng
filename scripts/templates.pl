#!/usr/bin/perl

# This script is based off of stats.cgi in /srv/dev/aardvark/cgi-bin/stats.cgi
#
use strict;
use warnings;
use lib './modules';
use Constants;

sub special_game_to_html
{
  my $key  = shift;
  my $item = shift;

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
  my $game_pointer   = $item->{'game_pointer'};
  my $player_pointer = $item->{'player_pointer'};
  my $player_name    = $item->{'player_name'};

  return "<b>$title:</b> <a href=\"#$game_pointer\" onclick=\"show_tourney('$game_pointer')\">$value</a> (<a href=\"$player_pointer\" onclick=\"show_head_to_head_entry('$player_pointer')\">vs</a> <a href=\"/html/players/$player_pointer.html\">$player_name</a>)<br>";
  
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


  my $player_html_page = "";

  $player_html_page .= <<STOP;
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">
<html>

<head>
<title>$player_name</title>

<script type="text/javascript" src="../../js/tabber.js"></script>
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="stylesheet" type="text/css" href="../../aardvark.css">
<link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/css/bootstrap.min.css">
<link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/font-awesome/4.7.0/css/font-awesome.min.css">
<script src="https://ajax.googleapis.com/ajax/libs/jquery/3.2.0/jquery.min.js"></script>
<script src="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/js/bootstrap.min.js"></script>

<style>
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

<script type="text/javascript">

/* Optional: Temporarily hide the "tabber" class so it does not "flash"
   on the page as plain HTML. After tabber runs, the class is changed
   to "tabberlive" and it will appear. */

document.write('<style type="text/css">.tabber{display:none;}<\/style>');
</script>

<script type="text/javascript">
var newwindow;
function poptastic(url)
{
	newwindow=window.open(url,'name','height=400,width=400,scrollbars=yes,resizable=no,location=no,directories=no,left=10,top=100');
	if (window.focus) {newwindow.focus()}
}

</script>
<script>
\$(document).ready(function () {

  \$('.collapse').on('shown.bs.collapse', function (e) {
  
    var id = e.target.id;

    id = id.replace('entry', 'button'); 
    document.getElementById(id).innerHTML = '-';
  
  });
  
  \$('.collapse').on('hidden.bs.collapse', function (e) {

    var id = e.target.id;
    id = id.replace('entry', 'button'); 
    document.getElementById(id).innerHTML = '+';
  
  });

});


</script>
</head>

<body id='override'>
   <div class="container-topper">
		<div style="margin: auto;width: 80px;">
					<img class="img-responsive" src="../../../wespafb.jpg" width="80" height="80" alt="WESPA" />
		</div>
	</div>

	<nav class="navbar navbar-default" style="background:#e8e6e6;">
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
	</nav>

<div style="background-color:#90D1EF">
<div style="background-color:white;padding-top:10px;" class="container">
	<div class="row">
			<div class="col-xs-8 col-md-8" style="margin-top:10px;margin-bottom:0px">
				<p><h2>$player_name</h2></p>
				<div>
					<IMG SRC="../../flags/$country_trigraph.png">
					<p>$country</p>
				</div>
					</div>
			<div class="col-xs-4 col-md-4" style="padding-top:20px;">
				 <img src='../../icons/$photo_filename' title='$player_name'>
			</div>
	</div>
<hr>
<div class="row">
<div class="col-md-12 col-xs-12 col-sm-12">

<b>Games Played:</b> $games_played<br>
<b>Wins:</b> $wins ($win_percentage%)<br>
<b>Losses: </b>$losses ($loss_percentage%)<br>
<b>Draws:</b> $draws</A> ($draw_percentage%)<br><br>
<b>Average Score:</b> $average_for<br>
<b>Average Against:</b> $average_against<br><br>
<b>300 Games:</b> $over_300 ($over_300_percentage%)<br>
<b>400 Games:</b> $over_400 ($over_400_percentage%)<br>
<b>500 Games:</b> $over_500 ($over_500_percentage%)<br>
<b>600 Games:</b> $over_600 ($over_600_percentage%)<br><br>


$special_games_html_string

$player_tournament_history_html



$player_head_to_head_history_html

</div></div>

<footer class="container-fluid" style="background-color:white;">
     
        <p class="small">&copy; WESPA <br/> <br/>SCRABBLE&reg; is a registered trademark. All intellectual property rights in and to the game are owned in the US by Hasbro Inc, in Canada by Hasbro Canada Inc and throughout the rest of the world by JW Spear &amp; Sons Ltd of Maidenhead, SL6 4UB, England, a subsidiary of Mattel Inc. Mattel and Spear are not affiliated with Hasbro or Hasbro Canada.</p>
     
</footer> 
</div></div>

</body>\n</html>\n

STOP

}



1;


