#!/usr/bin/perl

use warnings;
use strict;
use Data::Dumper;

use constant PATH => "/home/jcastellano/aardvark-ng";

use lib PATH . "/modules";
use Constants;

my $path = PATH;

# require "cgi-lib.pl";
require "$path/scripts/utils.pl";

# use CGI; 
# use CGI::Carp qw(warningsToBrowser fatalsToBrowser); 

main();

sub main
{

  # Read in all the variables set by the form
  my $testing = 1;
  my %input = ();

  #if (!$testing)
  #{
  #  &ReadParse(*input);
  #}
  #else
  #{
    $input{'partname'}  = "";
    $input{'state'}     = "USA";
    $input{'startyear'} = "1993";
    $input{'endyear'}   = "2019";
  #}

  my $partname  = lc($input{'partname'});
  my $startyear = $input{'startyear'};
  my $endyear   = $input{'endyear'};
  my $state     = $input{'state'};

  $startyear .= "-00-00";
  $endyear   .= "-12-31";

  my $tournaments_tn        = Constants::TOURNAMENTS_TABLE_NAME;
  my $divisions_tn          = Constants::DIVISIONS_TABLE_NAME;
  my $tournament_results_tn = Constants::TOURNAMENT_RESULTS_TABLE_NAME;
  my $players_tn            = Constants::PLAYERS_TABLE_NAME;

  my $query =
    "    
      SELECT *
      FROM $tournaments_tn AS t
      WHERE
            t.start_date >= '$startyear'  AND
            t.start_date <= '$endyear' 
    ";

  my $el = "h4";

  my $state_postquery    = "";
  my $partname_postquery = "";
  my $startdate_postquery = "<$el>Start Date: $startyear</$el>";
  my $enddate_postquery   = "<$el>End Date: $endyear</$el>";

  if ($state)
  {
    $query .= " AND t.country = '$state' ";
    $state_postquery = "<$el>Country: $state</$el>"
  }

  if ($partname)
  {
    $query .= " AND t.name LIKE \"%$partname%\"";
    $state_postquery = "<$el>Partial Name: $partname</$el>"
  }

  $query .= " ORDER BY t.start_date ASC";

  my $dbh = connect_to_database();

  my @tournaments = @{$dbh->selectall_arrayref($query, {Slice => {}, "RaiseError" => 1})};

  print "the query: $query\n";
  print Dumper(\@tournaments);

  my $title_ref = ['Date', 'Tournament', 'Country'];
  my $keys_ref  = ['start_date', 'name', 'country'];

  my $tournament_table = "<table class='table'>\n";

  $tournament_table .=
      make_row
      (    
        0,
        $title_ref,
        1,
        0,
        'white',
      );  

  for (my $i = 0; $i < scalar @tournaments; $i++)
  {
    my $row_class = 'roweven';

    if ($i % 2 == 1)
    {
      $row_class = 'rowodd';
    }
    my $item = $tournaments[$i];

    $tournament_table .=

    make_row
    (
      $item,
      $keys_ref,
      0,
      0,
      $row_class
    );


  }

  $tournament_table .=  "\n</table>\n";


  my $doctype   = Constants::TEMPLATE_DOCTYPE;
  my $meta      = Constants::TEMPLATE_META;
  my $wespa_img = Constants::TEMPLATE_WESPA_IMAGE;
  my $sources   = Constants::TEMPLATE_SOURCES;
  my $style     = Constants::TEMPLATE_STYLE;
  my $nav       = Constants::TEMPLATE_NAV;
  my $footer    = Constants::TEMPLATE_FOOTER;



  my $tournament_results_html_page .= <<STOP;
$doctype
<html>
  <head>
  $meta
  <title>Tournament Query</title>
  
  $sources
  
  $style
 
  </head>
  <body id='override'>
    $wespa_img
    $nav
    <div style="background-color:#90D1EF">
      <div style="background-color:white;padding-top:10px;" class="container">
        <h2>Tournament Query</h2>
        $startdate_postquery
        $enddate_postquery
        $state_postquery
        $partname_postquery
        <hr>
        <div class="row">
          <div class="col-md-12 col-xs-12 col-sm-12">
            $tournament_table
          </div>
        </div>
      </div>
      $footer
    </div>
  </div>
  </body>
</html>

STOP

  # Print the header
  # print &PrintHeader;
  print $tournament_results_html_page;
}

sub make_row
{
  my $item      = shift;
  my $keys      = shift;
  my $is_title  = shift;
  my $id        = shift;
  my $class     = shift;
  my $colspan   = shift;

  my $el = "td";

  if ($is_title)
  {
    $el = "th";
  }

  my $colspan_attr = "";

  if ($colspan)
  {
    $colspan_attr = " colspan='$colspan' ";
  }

  my @key_array = @{$keys};

  my $id_string = "";

  if ($id)
  {
    $id_string = " id='$id'"; 
  }

  my $class_string = "";

  if ($class)
  {
    $class_string = " class='$class' ";
  }

 my $row_string = "        <tr $class_string $id_string>";
  for (my $i = 0; $i < scalar @key_array; $i++)
  {
    my $key = $key_array[$i];
    my $val = $key;

    if (!$is_title)
    {    
      $val = $item->{$key};
    }

    my $base_dir = Constants::DEFAULT_SHORT_NAME_WORKING_DIR . '/' . Constants::HTML_DIR;
    my $tournament_dir = Constants::TOURNAMENT_HTML_DIR;
    my $player_dir     = Constants::PLAYER_HTML_DIR;
    my $rankings_dir   = Constants::RANKINGS_HTML_DIR;
    my $trigraph_hashref = Constants::COUNTRY_TRIGRAPH_TO_COUNTRY_NAME_HASHREF;

    if ($key eq 'tr_tournament_name')
    {
      $val = make_link($base_dir, $tournament_dir, $item->{'t_id'} . ".html", $val);
    }
    elsif ($key eq 'opp_name')
    {
      $val = make_link($base_dir, $player_dir, $item->{'opp_id'} . ".html", $val);
    }
    elsif ($key eq 'tr_player_name')
    {
      $val = make_link($base_dir, $player_dir, $item->{'tr_player_id'} . ".html", $val);
    }
    elsif ($key eq 'name')
    {
      $val = make_link($base_dir, $player_dir, $item->{'id'} . ".html", $val);
    }
    elsif ($key eq 'p_country' || $key eq 'country')
    {
      my $trig = $item->{'p_country'};

      if (!$trig)
      {
        $trig = $item->{'country'};
      }
      if ($trig)
      {
        my $country_fullname = $trigraph_hashref->{$trig};
        if ($country_fullname)
        {
          $val = make_link($base_dir, $rankings_dir, "$trig.html", $country_fullname);
        }
      }
    }
    if (!(defined $val))
    {
      $val = "";
    }

    $row_string .= sprintf "<$el $colspan_attr  >%s</$el>", $val;
  }
  $row_string .= "</tr>\n";

  return $row_string;
}



1;

