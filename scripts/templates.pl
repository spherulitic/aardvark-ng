#!/usr/bin/perl

# This script is based off of stats.cgi in /srv/dev/aardvark/cgi-bin/stats.cgi
#
use strict;
use warnings;
use lib './modules';
use Constants;


sub get_player_template_html_string
{
  # Arguments needed
  # $player_name

  my $player_html_page = "";


  $player_html_page .= Constants::HTML_HEADER;

  $player_html_page .= <<STOP;
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">
<html>
<script>

function show_tournament(scorecard_id)
{

}

</script>
<head>
<title>$player_name</title>

<script type="text/javascript" src="../js/tabber.js"></script>
<meta name="viewport" content="width=device-width, initial-scale=1">
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

</head>
<body>
   <div class="container-topper">
		<div style="margin: auto;width: 80px;">
					<img class="img-responsive" src="../../wespafb.jpg" width="80" height="80" alt="WESPA" />
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
					<IMG SRC="../flags/$player_country_trigraph.png">
					<p>$player_country</p>
				</div>
				<div>
					<a style="pull-left;padding-right:20px;" href='randomracer.com'>Head to Head</a>
				</div>
			</div>
			<div class="col-xs-4 col-md-4" style="padding-top:20px;">
				 <img src='$photo_filename' title='$player_name'>
			</div>
	</div>
<hr>
<div class="row">
<div class="col-md-12 col-xs-12 col-sm-12">

<B>Games played:</B> $games_played<BR>
<B>Wins:</B> $wins ($win_percentage%)<BR>
<B>Losses: </B>$losses ($loss_percentage%)<BR>
<B>Draws:</B> $draws</A> ($draw_percentage%)<BR><BR>
<B>Average Score:</B> $average_score<BR>
<B>Average Against:</B> $average_score_opp<BR><BR>
<B>300 Games:</B> $over_three_hundred ($over_three_hundred_percentage%)<BR>
<B>400 Games:</B> $over_four_hundred ($over_four_hundred_percentage%)<BR>
<B>500 Games:</B> $over_five_hundred ($over_five_hundred_percentage%)<BR>
<B>600 Games:</B> $over_six_hundred ($over_six_hundred_percentage%)<BR><BR>



<B>High Game:</B> <a href="#$high_game_tournament_id" onclick="show_tourney('$high_game_tournament_id')">$high_game_score</a> (<a href="$high_game_head_to_head_id" onclick="show_head_to_head_entry('$high_game_head_to_head_id')">vs</a> <a href="/html/players/$high_game_opp_id.html">$high_game_opp</a>)<BR>

$tournament_history_string
$head_to_head_string

</div></div>

<footer class="container-fluid" style="background-color:white;">
     
        <p class="small">&copy; WESPA <br/> <br/>SCRABBLE&reg; is a registered trademark. All intellectual property rights in and to the game are owned in the US by Hasbro Inc, in Canada by Hasbro Canada Inc and throughout the rest of the world by JW Spear &amp; Sons Ltd of Maidenhead, SL6 4UB, England, a subsidiary of Mattel Inc. Mattel and Spear are not affiliated with Hasbro or Hasbro Canada.</p>
     
</footer> 
</div></div>

</body>\n</html>\n

STOP

}



1;


