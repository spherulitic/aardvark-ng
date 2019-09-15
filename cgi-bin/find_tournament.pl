#!/usr/bin/perl

use warnings;
use strict;
use CGI;
use DBI;

my $cgi = CGI->new();

my $startyear = sanitize($cgi->param('startyear'));
my $endyear   = sanitize($cgi->param('endyear'));
my $state     = sanitize($cgi->param('state'));
my $partname  = sanitize($cgi->param('partname'));

$startyear .= '-00-00';
$endyear   .= '-12-31';

my $dbh = DBI->connect("DBI:mysql:database=wespa;host=localhost",
                         'wespa', 'nigeltheking',
                         {'RaiseError' => 1}); 

my $query =
"
  SELECT *
  FROM tournaments AS t
  WHERE
    t.end_date >= '$startyear' AND t.start_date <= '$endyear'    
";

if ($state ne 'all')
{
  $query .= " AND t.country = '$state' ";
}
else
{
  $state = 'All Countries';
}

if ($partname)
{
  $query .= " AND t.name LIKE '%$partname%' ";
}

$query .= " ORDER BY t.start_date ";

my @tournaments = @{$dbh->selectall_arrayref($query, {Slice => {}, "RaiseError" => 1})};

my $title_row = "<tr><th>#</th><th>Tournament</th><th>Date</th></tr>";

my $search_style = 'style="padding: 10px; border-bottom: 1px solid black;"';

my $search_content =
"
<table class='searchparams'>
<tbody>
<tr><th $search_style>Start Date            </th><td $search_style>$startyear</td></tr>
<tr><th $search_style>End Date              </th><td $search_style>$endyear</td></tr>
<tr><th $search_style>Country               </th><td $search_style>$state</td></tr>
<tr><th $search_style>Partial Name          </th><td $search_style>$partname</td></tr>
</tbody>
</table>
";

my $table_content = "";

for (my $i = 0; $i < scalar @tournaments; $i++)
{
  my $item = $tournaments[$i];
  my $name = $item->{'name'};
  my $date = $item->{'start_date'};
  my $id   = $item->{'id'};

  my $row_class = 'roweven';
    
  if ($i % 2 == 1)
  {
    $row_class = 'rowodd';
  }
  my $num = $i + 1;

  my $url = '/' . 'aardvark/html' . '/' . 'tournaments' . '/' . $id . '.html';
  my $link = "<a href='$url'>$name</a>";
  $table_content .= "<tr class='$row_class'><td>$num</td><td>$link</td><td>$date</td></tr>";
}

my $content =
"
$search_content
<table class='table'>
<tbody>
$title_row
$table_content
</tbody>
</table>
";

my $results_html_page .= <<STOP
<!DOCTYPE html>

<html>
  <head>
  

  <title>Tournament Results</title>
  
  
<script  src="/aardvark/js/tabber.js"></script>
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="stylesheet" type="text/css" href="/aardvark/aardvark.css">
<link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/css/bootstrap.min.css">
<link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/font-awesome/4.7.0/css/font-awesome.min.css">
<script src="https://ajax.googleapis.com/ajax/libs/jquery/3.2.0/jquery.min.js"></script>
<script src="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/js/bootstrap.min.js"></script>



  
  
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

  
  </head>
  
  <body id='override'>
        <div class="container-topper">
      <div style="margin: auto;width: 80px;">
        <img class="img-responsive" src="/wespafb.jpg" width="80" height="80" alt="WESPA">
      </div>
    </div>

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
        <li><a href="/index.shtml">Home</a></li>
        <li class="dropdown">
          <a class="dropdown-toggle" data-toggle="dropdown" href="#">About Us <span class="caret"></span></a>
          <ul class="dropdown-menu">
            <li><a href="/associations.shtml">Associations</a></li>
            <li><a href="/committees.shtml">Committees</a></li>
            <li><a href="/joinwespa.shtml">Join Us</a></li>
            <li><a href="/credits.shtml">Credits</a></li>
          </ul>
        </li>
        <li><a href="/news.shtml">News</a></li>
        <li class="dropdown">
          <a class="dropdown-toggle" data-toggle="dropdown" href="#">Tournaments <span class="caret"></span></a>
          <ul class="dropdown-menu">
            <li><a href="/tournaments/index.shtml">Calendar</a></li>
            <li><a href="/ratings.shtml">Ratings</a></li>
          </ul>
        </li>
        <li><a href="/resources.shtml">Resources</a></li>
        <li><a href="/youth.shtml">Youth Scrabble</a></li>
        <li><a href="/products.shtml">Products</a></li>
      </ul>
      <ul class="nav navbar-nav navbar-right">
        <li><a href="/contactus.shtml"><span class="glyphicon glyphicon-envelope"></span></a></li>
      </ul>
    </div>
  </div>
</div>

    <div style="background-color:#90D1EF">
      
      <div  class="container">
        <div class="row">
          <div class="col-xs-12" style="background-color:white;margin-top:10px;margin-bottom:0px">
            <h2><img style="float:right ; margin: 2px 2px 2px 20px;" height="60" width="60" src="../../../wespafb.jpg" alt="WESPA" />Tournament Results</h2>   
          </div>
        </div>
      </div>
      <div  style="background-color:white;padding-top:10px;"  class="container">
        <div class="row">
          <div class="table-responsive">
            $content
          </div>
        </div>
      </div>
      <div class="container-fluid" style="background-color:white;">
     
        <p class="small">&copy; WESPA <br><br>SCRABBLE&reg; is a registered trademark. All intellectual property rights in and to the game are owned in the US by Hasbro Inc, in Canada by Hasbro Canada Inc and throughout the rest of the world by JW Spear &amp; Sons Ltd of Maidenhead, SL6 4UB, England, a subsidiary of Mattel Inc. Mattel and Spear are not affiliated with Hasbro or Hasbro Canada.</p>
     
</div>

    </div>
  </body>
</html>

STOP
;

print "Content-Type: text/html

";
print $results_html_page;

sub sanitize
{
  my $s = shift;

  $s = substr($s, 0, 255);
  $s =~ s/ /_/g;
  $s =~ s/\W//g;
  $s =~ s/_/ /g;
  return $s;
}

1;

