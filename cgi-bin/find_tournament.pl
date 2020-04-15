#!/usr/bin/perl

use warnings;
use strict;

use version; our $VERSION = qv('1');

use CGI;
use CGI::Carp qw(fatalsToBrowser);

use lib '/home/jcastellano/aardvark-ngdev/modules';
use Constants;
use Utils;

my $cgi = CGI->new();

my $startyear = Utils::cgi_sanitize( $cgi->param($CGI_START_YEAR_NAME) );
my $endyear   = Utils::cgi_sanitize( $cgi->param($CGI_END_YEAR_NAME) );
my $country   = Utils::cgi_sanitize( $cgi->param($CGI_COUNTRY_NAME) );
my $partname  = Utils::cgi_sanitize( $cgi->param($CGI_PARTNAME_NAME) );

#my $startyear = Utils::cgi_sanitize(2019);
#my $endyear   = Utils::cgi_sanitize(2020);
#my $country   = Utils::cgi_sanitize('USA');
#my $partname  = Utils::cgi_sanitize('');

my $dbh = Utils::connect_to_database($PRODUCTION_DATABASE_NAME);

my @tournaments = Utils::get_tournaments(
  { dbh       => $dbh,
    startyear => $startyear,
    endyear   => $endyear,
    country   => $country,
    partname  => $partname,
  }
);

if ( $country eq $CGI_ALL_COUNTRIES )
{
  $country = $CGI_ALL_COUNTRY_TITLE;
}

my $table_content = $EMPTY_STRING;

for my $i ( 0 .. scalar @tournaments - 1 )
{
  my $item = $tournaments[$i];
  my $name = $item->{name};
  my $date = $item->{start_date};
  my $id   = $item->{id};

  my $row_class = $HTML_ROWEVEN_CLASS;

  if ( $i % 2 == 1 )
  {
    $row_class = $HTML_ROWODD_CLASS;
  }

  my $num = $i + 1;

  my $url = "/$DEFAULT_SHORT_NAME_WORKING_DIR"
    . "/$HTML_DIR/$TOURNAMENT_HTML_DIR/$id.html";

  my $link = "<a href='$url'>$name</a>";
  $table_content
    .= "<tr class='$row_class'> "
    . "<td>$num</td>"
    . "<td>$date</td>"
    . "<td>$link</td>" . '</tr>';
}

my $results_html_page = <<"STOP"
$TEMPLATE_DOCTYPE
<html>
  <head>
  $TEMPLATE_META
  <title>Tournament Search</title>
  
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
                       Tournament Search
            </h2>   
          </div>
        </div>
      </div>
      <div  style="background-color:white;padding-top:10px;"
            class="container">
        <div class="row">
          <div class="table-responsive">
            <table class='searchparams'>
              <tbody>
                <tr>
                  <th $CGI_SEARCH_STYLE>Start Date</th>
                  <td $CGI_SEARCH_STYLE>$startyear</td>
                </tr>
                <tr>
                  <th $CGI_SEARCH_STYLE>End Date</th>
                  <td $CGI_SEARCH_STYLE>$endyear</td>
                </tr>
                <tr>
                  <th $CGI_SEARCH_STYLE>Country</th>
                  <td $CGI_SEARCH_STYLE>$country</td>
                </tr>
                <tr>
                  <th $CGI_SEARCH_STYLE>Partial Name</th>
                  <td $CGI_SEARCH_STYLE>$partname</td>
                </tr>
              </tbody>
            </table>
            <table class='table'>
              <tbody>
                <tr><th>#</th><th>Date</th><th>Tournament</th></tr>
                $table_content
              </tbody>
            </table>
          </div>
        </div>
      </div>
      $TEMPLATE_FOOTER
    </div>
  </body>
</html>
STOP
  ;

print    ## no critic (InputOutput::RequireCheckedSyscalls)
  $CGI_HEADER . $results_html_page;
