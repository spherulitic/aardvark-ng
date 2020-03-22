#!/usr/bin/perl

package HTML;

use strict;
use warnings;
use version; our $VERSION = qv('1');
use Data::Dumper;

use lib './modules';
use Constants;
use Utils;

sub add_statdata
{
  my $data     = shift;
  my $statitem = shift;
  if ( $statitem->{cond}->($data) )
  {
    my $stat       = $statitem->{eval}->($data);
    my @value_list = @{ $statitem->{values} };
    my $statdata   = {};
    foreach my $val (@value_list)
    {
      my $dataitem = $data->{$val};
      if ($dataitem)
      {
        $statdata->{$val} = $dataitem;
      }
    }
    $statdata->{tr_player_id}   = $data->{tr_player_id};
    $statdata->{opp_id}         = $data->{opp_id};
    $statdata->{$STAT_KEY_NAME} = $stat;

    push @{ $statitem->{list} }, $statdata;
  }
  return 1;
}

sub add_to_statitem_list
{
  my $data       = shift;
  my $statitem   = shift;
  my $stat       = $statitem->{eval}->($data);
  my @value_list = @{ $statitem->{values} };
  my $statdata   = {};
  foreach my $val (@value_list)
  {
    my $dataitem = $data->{$val};
    if ($dataitem)
    {
      $statdata->{$val} = $dataitem;
    }
  }
  $statdata->{tr_player_id} = $data->{tr_player_id};
  $statdata->{opp_id}       = $data->{opp_id};
  $statdata->{t_id}         = $data->{t_id};

  $statdata->{$STAT_KEY_NAME} = $stat;

  push @{ $statitem->{list} }, $statdata;
  my @statlist = @{ $statitem->{list} };
  @statlist = sort { $statitem->{sort}->( $a, $b ) } @statlist;
  while ( scalar @statlist > $ALLTIME_CUTOFF )
  {
    pop @statlist;
  }
  $statitem->{list} = \@statlist;
  return 1;
}

sub build_ratings_table
{
  my $tournament_stats      = shift;
  my $tournament_stats_html = shift;
  foreach my $key ( keys %{$tournament_stats} )
  {
    my $dataitem    = $tournament_stats->{$key};
    my $html_string = "       <table class='table'>$NEWLINE";
    $html_string .= Utils::make_row(
      { keys     => $dataitem->{titles},
        is_title => 1
      }
    );

    my @statlist = @{ $dataitem->{list} };
    for my $i ( 0 .. scalar @statlist - 1 )
    {
      my $sub_row_class = $i % 2 == 1 ? 'rowodd' : 'roweven';

      my $statitem = $statlist[$i];
      $html_string .= Utils::make_row(
        { item  => $statitem,
          keys  => $dataitem->{values},
          class => $sub_row_class
        }
      );
    }
    $html_string .= '        </table>';

    $tournament_stats_html->{$key} = $html_string;
  }
  return 1;
}

sub convert_result_to_letter
{
  my $result           = shift;
  my %result_to_letter = (
    1             => q{W},
    0             => q{T},
    $NEGATIVE_ONE => q{L},
  );
  return $result_to_letter{$result};
}

sub correlate_tournament_data
{
  my $arg_ref = shift;

  my $tournament_results_hashref = $arg_ref->{results};
  my $tournament_data_ref        = $arg_ref->{data};
  my $tournament_stats           = $arg_ref->{stats};
  my $type                       = $arg_ref->{type};

  foreach my $data ( @{$tournament_data_ref} )
  {
    if ( $type == $HTML_ID_TOURNAMENT_TYPE )
    {
      foreach my $key ( keys %{$tournament_stats} )
      {
        my $statitem = $tournament_stats->{$key};
        HTML::add_statdata( $data, $statitem );
      }
    }

    my $key;
    if ( $type == $HTML_ID_PLAYER_TYPE )
    {
      $key = 'tr_division_id';
    }
    elsif ( $type == $HTML_ID_TOURNAMENT_TYPE )
    {
      $key = 'tr_player_id';
    }
    elsif ( $type == $HTML_ID_HEAD_TO_HEAD_TYPE )
    {
      $key = 'opp_id';
    }

    my $item = $tournament_results_hashref->{ $data->{$key} };

    # Get the tournament stats

    if ($item)
    {
      push @{$item}, $data;
    }
    else
    {
      $tournament_results_hashref->{ $data->{$key} } = [$data];
    }
  }
  return 1;
}

sub get_alltime_stats_results_html_string
{
  my $dbh = shift;

  my $sth
    = $dbh->prepare( 'SELECT '
      . 'tr1.start_rating    AS tr_start_rating, '
      . 'p1.name             AS tr_player_name, '
      . 'p1.id               AS tr_player_id, '
      . 'pr1.score           AS pr1_score, '
      . 'tr2.start_rating    AS opp_rating, '
      . 'p2.name             AS opp_name, '
      . 'p2.id               AS opp_id, '
      . 'pr2.score           AS pr2_score, '
      . 'g.round             AS g_round, '
      . 'tr1.tournament_name AS tr_tournament_name, '
      . 't.id                AS t_id ' . 'FROM '
      . "$GAMES_TABLE_NAME AS g, "
      . "$PLAYER_RESULTS_TABLE_NAME AS pr1, "
      . "$PLAYER_RESULTS_TABLE_NAME AS pr2, "
      . "$PLAYERS_TABLE_NAME AS p1, "
      . "$PLAYERS_TABLE_NAME AS p2, "
      . "$TOURNAMENT_RESULTS_TABLE_NAME AS tr1, "
      . "$TOURNAMENT_RESULTS_TABLE_NAME AS tr2, "
      . "$DIVISIONS_TABLE_NAME AS d, "
      . "$TOURNAMENTS_TABLE_NAME AS t "
      . 'WHERE '
      . 'g.id = pr1.game_id AND g.id = pr2.game_id       AND '
      . 'pr1.player_id = p1.id AND pr2.player_id = p2.id AND '
      . 'p1.id = tr1.player_id AND p2.id = tr2.player_id AND '
      . 'p1.id > p2.id                       AND '
      . 'g.division_id   = tr1.division_id AND '
      . 'g.division_id   = tr2.division_id AND '
      . 'g.division_id   = d.id            AND '
      . 'd.tournament_id = t.id ' );

  $sth->execute();

  my $all_stats = Utils::stat_objects();

  my $tournament_results_hashref = {};

  foreach my $key ( keys %{$all_stats} )
  {
    my $statitem = $all_stats->{$key};

    my @value_list = @{ $statitem->{values} };
    push @value_list, 'tr_tournament_name';
    $statitem->{values} = \@value_list;

    my @titles = @{ $statitem->{titles} };
    push @titles, 'Tournament';
    $statitem->{titles} = \@titles;
  }

  while ( my $data = $sth->fetchrow_hashref )
  {
    for my $y ( 0 .. 1 )
    {
      if ( $y == 1 )
      {
        Utils::swap( $data, 'tr_start_rating', 'opp_rating' );
        Utils::swap( $data, 'tr_player_name',  'opp_name' );
        Utils::swap( $data, 'tr_player_id',    'opp_id' );
        Utils::swap( $data, 'pr1_score',       'pr2_score' );
      }
      foreach my $key ( keys %{$all_stats} )
      {
        my $statitem = $all_stats->{$key};
        if ( $statitem->{cond}->($data) )
        {
          HTML::add_to_statitem_list( $data, $statitem );
        }
      }
    }
  }
  foreach my $key ( keys %{$all_stats} )
  {
    my $statitem = $all_stats->{$key};
    my @statlist = @{ $statitem->{list} };
    for my $i ( 0 .. scalar @statlist - 1 )
    {
      $statlist[$i]->{$GAME_STATS_RANK_NAME} = $i + 1;
    }
  }

  my $all_stats_html = {};

  foreach my $key ( keys %{$all_stats} )
  {
    my $dataitem = $all_stats->{$key};

    my $html_string = "       <table class='table'>$NEWLINE";
    $html_string .= Utils::make_row(
      { keys     => $dataitem->{titles},
        is_title => 1
      }
    );

    my @statlist = @{ $dataitem->{list} };
    for my $i ( 0 .. scalar @statlist - 1 )
    {
      my $sub_row_class = 'roweven';

      if ( $i % 2 == 1 )
      {
        $sub_row_class = 'rowodd';
      }

      my $statitem = $statlist[$i];

      $html_string .= Utils::make_row(
        { item  => $statitem,
          keys  => $dataitem->{values},
          class => $sub_row_class
        }
      );
    }
    $html_string .= '        </table>';

    $all_stats_html->{$key} = $html_string;
  }
  return $all_stats_html;
}

sub get_alltime_template_html_string
{
  my $stats = shift;

  my @ids_to_click       = ();
  my $display_none_style = q{style='display:none;'};

  my $stats_tabclass = 'stats_tab';
  my $stats_tablink  = 'stats_tablink';

  my $stats_content = $EMPTY_STRING;
  my @stats_tabdata = ();

  my $stats_order_ref = $TOURNAMENT_STATS_ORDER;
  my $ids_to_click_javascript_array;

  for my $k ( 0 .. scalar @{$stats_order_ref} - 1 )
  {
    my $cat     = $stats_order_ref->[$k];
    my $stat_id = "stats_$cat";
    push @stats_tabdata, [ $cat, $stat_id ];

    my $stat_html = $stats->{$cat};
    $stats_content
      .= "<div id='$stat_id' "
      . "class='$stats_tabclass' "
      . "$display_none_style> "
      . $stat_html
      . "</div>$NEWLINE";
    if ( $k == 0 )
    {
      $ids_to_click_javascript_array .= "[button_$stat_id]";
    }
  }

  $stats_content
    = Utils::make_tab_div( \@stats_tabdata, $stats_tabclass, $stats_tablink )
    . $stats_content;

  my $tournament_html_page = $EMPTY_STRING;

  $tournament_html_page .= <<"STOP";
$TEMPLATE_DOCTYPE
<html>
  <head>
  $TEMPLATE_META
  <title>All Time Stats</title>
  
  $TEMPLATE_SOURCES
  
  $TEMPLATE_STYLE
  
  <script type="text/javascript">
 
    $TEMPLATE_SCRIPTS

   
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
    $TEMPLATE_WESPA_IMAGE
    $TEMPLATE_NAV
    <div style="background-color:#90D1EF">
      <div style="background-color:white;padding-top:10px;"
           class="container">
        <h2>All Time Stats</h2>
        <hr>
        <div class="row">
          <div class="col-md-12 col-xs-12 col-sm-12">
            $stats_content
          </div>
        </div>
      </div>
      $TEMPLATE_FOOTER
    </div>
  </div>
  </body>
</html>

STOP

  return $tournament_html_page;
}

sub get_datalist_html
{
  my $arg_ref = shift;

  my $data           = $arg_ref->{data};
  my $title          = $arg_ref->{title};
  my $href           = $arg_ref->{href};
  my $html_id        = $arg_ref->{html_id};
  my $input_id       = $arg_ref->{input_id};
  my $button_id      = $arg_ref->{button_id};
  my $data_value_key = $arg_ref->{data_value_key};
  my $value_key      = $arg_ref->{value_key};

  my $function = <<"FUNCTION"

  var input = document.getElementById('$input_id');
  var options = Array.from(
                  document.getElementById('$html_id'
                  ).options).map(function(el)
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
    var selection = '#$html_id option[value=$ESCAPED_QUOTE' + 
                     pname +
                     '$ESCAPED_QUOTE]';
    var pid   = document.querySelector(selection).dataset.value;

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
    alert('Choose an option by typing in the box' + 
          ' and selecting an option from the pop-up menu.');
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

  my $html
    = "$title "
    . "<input list='$html_id' id='$input_id' $input_function>"
    . "<datalist id='$html_id'>";

  my @data_array = @{$data};

  foreach my $item (@data_array)
  {
    my $name = $item->{$value_key};
    my $id   = $item->{$data_value_key};
    $html .= "<option data-value='$id' value=\"$name\"></option>$NEWLINE";
  }

  $html .= "    </datalist>$NEWLINE";

  $html
    .= '<input '
    . q{type='button' }
    . q{value='Submit' }
    . "id='$button_id' "
    . "$submit_function>";
  return $html;
}

sub get_player_template_html_string
{
  my $player_info                      = shift;
  my $player_tournament_history_html   = shift;
  my $player_head_to_head_history_html = shift;
  my $player_tournament_history_data   = shift;

  my $player_name      = $player_info->{player_name};
  my $country_trigraph = $player_info->{country_trigraph};
  my $games_played     = $player_info->{games_played};
  my $rating           = $player_info->{rating};
  my $photo_filename   = $player_info->{photo_filename};
  my $valid_ranking    = $player_info->{valid_ranking};

  my $country = $country_trigraph;

  my $wins          = $player_tournament_history_data->{wins};
  my $losses        = $player_tournament_history_data->{losses};
  my $draws         = $player_tournament_history_data->{draws};
  my $total_score   = $player_tournament_history_data->{total_score};
  my $total_against = $player_tournament_history_data->{total_against};

  my $average_for = sprintf "%.$ROUNDING_PLACE" . q{f},
    $total_score / $games_played;
  my $average_against = sprintf "%.$ROUNDING_PLACE" . q{f},
    $total_against / $games_played;

  my $under_300
    = $player_tournament_history_data->{over}->{$ZEROTH_SCORE_THRESHOLD};
  my $over_300
    = $player_tournament_history_data->{over}->{$FIRST_SCORE_THRESHOLD};
  my $over_400
    = $player_tournament_history_data->{over}->{$SECOND_SCORE_THRESHOLD};
  my $over_500
    = $player_tournament_history_data->{over}->{$THIRD_SCORE_THRESHOLD};
  my $over_600
    = $player_tournament_history_data->{over}->{$FOURTH_SCORE_THRESHOLD};

  my $win_percentage = sprintf "%.$ROUNDING_PLACE" . q{f},
    $ONE_HUNDRED_PERCENT * ( $wins / $games_played );
  my $loss_percentage = sprintf "%.$ROUNDING_PLACE" . q{f},
    $ONE_HUNDRED_PERCENT * ( $losses / $games_played );
  my $draw_percentage = sprintf "%.$ROUNDING_PLACE" . q{f},
    $ONE_HUNDRED_PERCENT * ( $draws / $games_played );

  my $under_300_percentage = sprintf "%.$ROUNDING_PLACE" . q{f},
    $ONE_HUNDRED_PERCENT * ( $under_300 / $games_played );
  my $over_300_percentage = sprintf "%.$ROUNDING_PLACE" . q{f},
    $ONE_HUNDRED_PERCENT * ( $over_300 / $games_played );
  my $over_400_percentage = sprintf "%.$ROUNDING_PLACE" . q{f},
    $ONE_HUNDRED_PERCENT * ( $over_400 / $games_played );
  my $over_500_percentage = sprintf "%.$ROUNDING_PLACE" . q{f},
    $ONE_HUNDRED_PERCENT * ( $over_500 / $games_played );
  my $over_600_percentage = sprintf "%.$ROUNDING_PLACE" . q{f},
    $ONE_HUNDRED_PERCENT * ( $over_600 / $games_played );

  my $special_games_data = $player_tournament_history_data->{special_games};

  my @special_games_keys = qw(
    high_game low_game biggest_win biggest_loss high_loss low_win
  );

  my $special_games_html_string = $EMPTY_STRING;

  for my $i ( 0 .. scalar @special_games_keys - 1 )
  {
    my $key = $special_games_keys[$i];
    $special_games_html_string
      .= HTML::special_game_to_html( $key, $special_games_data->{$key} );
  }

  my $player_tabclass = 'player_tab';
  my $player_tablink  = 'player_tablink';

  my $results_html_id      = 'results';
  my $head_to_head_html_id = 'head_to_head';

  my $country_rankings = $EMPTY_STRING;

  my $trigraph_hashref = $COUNTRY_TRIGRAPH_TO_COUNTRY_NAME_HASHREF;
  my $country_fullname = $trigraph_hashref->{$country};

  my $valid_country_html = $EMPTY_STRING;

  if ($country_fullname)
  {
    $country_rankings = $country_fullname;

    my $country_png = "$HTML_PATH_TO_WORKING_DIR/flags/$country.png";
    if ($valid_ranking)
    {
      my $country_rankings_link
        = $DEFAULT_SHORT_NAME_WORKING_DIR . q{/}
        . $HTML_DIR . q{/}
        . $RANKINGS_HTML_DIR
        . "/$country.html";
      $country_rankings
        = "<a href='/$country_rankings_link'>$country_fullname</a>";
    }

    $valid_country_html
      = '<div> '
      . "<IMG SRC='$country_png' alt='$country'> "
      . "<p>$country_rankings</p> "
      . '</div>';
  }

  my $tabs = Utils::make_tab_div(
    [ [ 'Results',      $results_html_id ],
      [ 'Head to Head', $head_to_head_html_id ]
    ],
    $player_tabclass,
    $player_tablink
  );

  my $player_html_page = $EMPTY_STRING;

  $player_html_page .= <<"STOP";
$TEMPLATE_DOCTYPE
<html $TEMPLATE_LANG>
  <head>
    $TEMPLATE_META
    <title>$player_name</title>
    
    $TEMPLATE_SOURCES
    
    $TEMPLATE_STYLE
      
    <script >

      $TEMPLATE_SCRIPTS
    
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

      window.onload =
        function()
        {
          document.getElementById('button_$results_html_id').click();
        }
    </script>
  </head>
  
  <body id='override'>
    $TEMPLATE_WESPA_IMAGE
    $TEMPLATE_NAV
    <div style="background-color:#90D1EF">
      <div style="background-color:white;padding-top:10px;" class="container">
        <div class="row">
          <div class="col-xs-8 col-md-8"
               style="margin-top:10px;margin-bottom:0px">
            <h2>$player_name</h2>
            $valid_country_html
          </div>
          <div class="col-xs-4 col-md-4" style="padding-top:20px;">
            <img src='$HTML_PATH_TO_WORKING_DIR/icons/$photo_filename'
                 title='$player_name' alt='$player_name'>
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
      $TEMPLATE_FOOTER
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
    @players
      = @{ Utils::query_table( $dbh, $PLAYERS_TABLE_NAME, 'country',
        $country ) };
  }
  else
  {
    @players = @{
      $dbh->selectall_arrayref(
        "SELECT * FROM $PLAYERS_TABLE_NAME",
        { Slice => {}, RaiseError => 1 }
      )
    };
  }

  @players
    = grep { !$_->{deceased} && !$_->{suspended} && $_->{current} } @players;

  @players = reverse sort { $a->{rating} <=> $b->{rating} } @players;

  my $full_rankings_string = "      <table class='table'>$NEWLINE";

  my $titles = [ 'Ranking', 'Name', 'Country', 'Rating', 'Total Games',
    'Last Played' ];

  $full_rankings_string .= Utils::make_row(
    { keys     => $titles,
      is_title => 1,
      class    => $HTML_WHITE_CLASS
    }
  );

  for my $i ( 0 .. scalar @players - 1 )
  {
    my $row_class = 'roweven';

    if ( $i % 2 == 1 )
    {
      $row_class = 'rowodd';
    }

    my $item = $players[$i];
    $item->{ranking} = $i + 1;
    $full_rankings_string .= Utils::make_row(
      { item => $item,
        keys => [
          'ranking',     'name', 'country', 'rating',
          'total_games', 'last_played'
        ],
        class => $row_class
      }
    );
  }

  $full_rankings_string .= "      </table>$NEWLINE";
  return $full_rankings_string;
}

sub get_rankings_template_html_string
{
  my $rankings_string = shift;
  my $rankings_data   = shift;

  my $title           = $rankings_data->{title};
  my $tournament_link = $rankings_data->{tournament_link};

  my $localtime = localtime;

  my $rankings_html_page = $EMPTY_STRING;

  $rankings_html_page .= <<"STOP"
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
      
      <div class="container">
        <div class="row">
          <div class="col-xs-12"
               style="background-color:white;
                      margin-top:10px;
                      margin-bottom:0px">

            <h2><img style="float:right; margin: 2px 2px 2px 20px;"
                     height="60"
                     width="60"
                     src="$HTML_PATH_TO_WORKING_DIR/../wespafb.jpg"
                     alt="WESPA" />
                       $title
            </h2>	
          </div>
        </div>
      </div>
         
      <div class="container">

        <div class="row">
          <div class="col-xs-12"
               style="background-color:white;
                      margin-top:0px;margin-bottom:0px">
            Most recent tournament: $tournament_link<br>
            Updated on $localtime
          </div>
        </div>
 
        <div class="row">
          <div class="table-responsive">
            $rankings_string
          </div>
        </div>
      </div>
      $TEMPLATE_FOOTER
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

  my $query
    = 'SELECT '
    . 'tr.player_name                  AS tr_player_name, '
    . 'tr.tournament_name              AS tr_tournament_name, '
    . 'tr.id                           AS tr_id, '
    . 'tr.division_id                  AS tr_division_id, '
    . 'tr.player_id                    AS tr_player_id, '
    . 'tr.player_name                  AS tr_player_name, '
    . 'tr.position                     AS tr_position, '
    . 'tr.wins                         AS tr_wins, '
    . 'tr.losses                       AS tr_losses, '
    . 'tr.byes                         AS tr_byes, '
    . 'tr.spread                       AS tr_spread, '
    . 'tr.start_rating                 AS tr_start_rating, '
    . 'tr.end_rating                   AS tr_end_rating, '
    . 'tr.end_rating - tr.start_rating AS tr_rating_change, '
    . 'tr.date                         AS tr_date, '
    . 'g.round                         AS g_round, '
    . 'g.gcg_filename                  AS g_gcg_filename, '
    . 'pr1.score                       AS pr1_score, '
    . 'pr2.score                       AS pr2_score, '
    . 'pr1.result                      AS pr1_result, '
    . 'opp.name                        AS opp_name,  '
    . 'opp.id                          AS opp_id, '
    . 'opp.rating                      AS opp_current_rating, '
    . 'tr_opp.start_rating             AS opp_rating, '
    . 't.id                            AS t_id, '
    . 'tr.expected_wins                AS tr_expected_wins, '
    . 'tr.old_world_rank               AS tr_old_world_rank, '
    . 'tr.new_world_rank               AS tr_new_world_rank, '
    . 'tr.old_national_rank            AS tr_old_national_rank, '
    . 'tr.new_national_rank            AS tr_new_national_rank, '
    . 'player.country                  AS p_country ' . 'FROM '
    . "$TOURNAMENT_RESULTS_TABLE_NAME AS tr, "
    . "$TOURNAMENT_RESULTS_TABLE_NAME AS tr_opp, "
    . "$GAMES_TABLE_NAME AS g, "
    . "$PLAYER_RESULTS_TABLE_NAME AS pr1, "
    . "$PLAYER_RESULTS_TABLE_NAME AS pr2, "
    . "$PLAYERS_TABLE_NAME AS opp, "
    . "$TOURNAMENTS_TABLE_NAME AS t, "
    . "$DIVISIONS_TABLE_NAME AS d, "
    . "$PLAYERS_TABLE_NAME AS player "
    . 'WHERE '
    . 't.id           = d.tournament_id     AND '
    . 'd.id           = tr.division_id      AND '
    . 'd.id           = tr_opp.division_id  AND '
    . 'opp.id         = tr_opp.player_id    AND '
    . 'tr.division_id = g.division_id       AND '
    . 'tr.player_id   = pr1.player_id       AND '
    . 'g.id           = pr1.game_id         AND '
    . 'g.id           = pr2.game_id         AND '
    . 'pr1.id        != pr2.id              AND '
    . 'opp.id         = pr2.player_id       AND '
    . 'pr1.player_id  = player.id           AND ';

  if ( $type == $HTML_ID_PLAYER_TYPE || $type == $HTML_ID_HEAD_TO_HEAD_TYPE )
  {
    $query .= " tr.player_id = $id";
  }
  elsif ( $type == $HTML_ID_TOURNAMENT_TYPE && $id )
  {
    $query .= " tr.division_id = $id";
  }

  my @raw_tournament_data
    = @{ $dbh->selectall_arrayref( $query, { Slice => {}, RaiseError => 1 } )
    };

  HTML::sanitize_tournament_data( \@raw_tournament_data );

  # Prepare tournament stats datastructure

  my $tournament_stats;

  if ( $type == $HTML_ID_TOURNAMENT_TYPE )
  {
    $tournament_stats = Utils::stat_objects();
  }

  my $tournament_results_hashref = {};

  # Correlate game results with a tournament result

  HTML::correlate_tournament_data(
    { results => $tournament_results_hashref,
      data    => \@raw_tournament_data,
      stats   => $tournament_stats,
      type    => $type,
    }
  );

  # Sort the games, stats, and results

  my @tournament_results = HTML::sort_tournament_data(
    { results => $tournament_results_hashref,
      stats   => $tournament_stats,
      type    => $type,
    }
  );

  my $tournament_results_list_html_string = "<table class='table'>$NEWLINE";
  my $tournament_ratings_html_string      = "<table class='table'>$NEWLINE";

  my $title_ref        = $TOURNAMENT_TITLE_REF;
  my $sub_title_ref    = $GAMES_TITLE_REF;
  my $keys_ref         = $TOURNAMENT_KEYS_REF;
  my $games_keys_ref   = $GAMES_KEYS_REF;
  my $ratings_keys_ref = $RATINGS_KEYS_REF;

  if ( $type == $HTML_ID_HEAD_TO_HEAD_TYPE )
  {
    $title_ref      = $HEAD_TO_HEAD_TITLE_REF;
    $sub_title_ref  = $HEAD_TO_HEAD_GAMES_TITLE_REF;
    $keys_ref       = $HEAD_TO_HEAD_KEYS_REF;
    $games_keys_ref = $HEAD_TO_HEAD_GAMES_KEYS_REF;
  }
  elsif ( $type == $HTML_ID_TOURNAMENT_TYPE )
  {
    $title_ref = $TOURNAMENT_STANDINGS_TITLE_REF;
    $keys_ref  = $TOURNAMENT_STANDINGS_KEYS_REF;
    $tournament_ratings_html_string .= Utils::make_row(
      { keys     => $RATINGS_SUPER_TITLE_REF,
        is_title => 1,
        class    => $HTML_WHITE_CLASS,
        colspan  => 2
      }
    );

    $tournament_ratings_html_string .= Utils::make_row(
      { keys     => $RATINGS_SUPER_TITLE_REF,
        is_title => 1,
        class    => $HTML_WHITE_CLASS
      }
    );
  }

  my $title_length = scalar @{$title_ref};

  $tournament_results_list_html_string .= Utils::make_row(
    { keys     => $RATINGS_SUPER_TITLE_REF,
      is_title => 1,
      class    => $HTML_WHITE_CLASS
    }
  );

  my $games_title_row = Utils::make_row(
    { keys     => $RATINGS_SUPER_TITLE_REF,
      is_title => 1
    }
  );

  my $game_data = {
    tournament_name => $tournament_results[0]->[0]->{tr_tournament_name},
    tournament_date => $tournament_results[0]->[0]->{tr_date},
    games_played    => 0,
    wins            => 0,
    losses          => 0,
    draws           => 0,
    total_score     => 0,
    total_against   => 0,
    over            => {
      $ZEROTH_SCORE_THRESHOLD => 0,
      $FIRST_SCORE_THRESHOLD  => 0,
      $SECOND_SCORE_THRESHOLD => 0,
      $THIRD_SCORE_THRESHOLD  => 0,
      $FOURTH_SCORE_THRESHOLD => 0
    },
    special_games => {
      high_game    => { value => $HIGH_SCORE_INITIAL_VALUE },
      low_game     => { value => $LOW_SCORE_INITIAL_VALUE },
      biggest_win  => { value => $HIGH_SCORE_INITIAL_VALUE },
      biggest_loss => { value => $HIGH_SCORE_INITIAL_VALUE },
      high_loss    => { value => $HIGH_SCORE_INITIAL_VALUE },
      low_win      => { value => $LOW_SCORE_INITIAL_VALUE }
    }
  };

  for my $i ( 0 .. scalar @tournament_results - 1 )
  {
    my $new_entry = $EMPTY_STRING;

    my $subentries = $EMPTY_STRING;

    my $games_ref = $tournament_results[$i];

    my $button_id = Utils::create_html_id( $HTML_ID_BUTTON_TAG, $type,
      $games_ref->[0]->{tr_id} );
    my $entry_id = Utils::create_html_id( $HTML_ID_ENTRY_TAG, $type,
      $games_ref->[0]->{tr_id} );
    my $row_class = 'roweven';

    if ( $i % 2 == 1 )
    {
      $row_class = 'rowodd';
    }

    if ( $type == $HTML_ID_HEAD_TO_HEAD_TYPE )
    {
      $button_id = Utils::create_html_id( $HTML_ID_BUTTON_TAG, $type,
        $games_ref->[0]->{opp_id} );
      $entry_id = Utils::create_html_id( $HTML_ID_ENTRY_TAG, $type,
        $games_ref->[0]->{opp_id} );
    }

    $games_ref->[0]->{q{#}} = $i + 1;

    $games_ref->[0]->{details}
      = '<button '
      . "type='button' id='$button_id'  class='btn btn-info' "
      . q{data-toggle='collapse' data-target='#}
      . "$entry_id'>"
      . '+</button>';

    if ( $type != $HTML_ID_HEAD_TO_HEAD_TYPE )
    {
      $new_entry .= Utils::make_new_entry_head(
        { games_ref       => $games_ref,
          keys_ref        => $keys_ref,
          row_class       => $row_class,
          entry_id        => $entry_id,
          title_length    => $title_length,
          games_title_row => $games_title_row
        }
      );
    }

    if ( $type == $HTML_ID_TOURNAMENT_TYPE )
    {
      $tournament_ratings_html_string .= Utils::make_row(
        { item  => $games_ref->[0],
          keys  => $ratings_keys_ref,
          class => $HTML_WHITE_CLASS
        }
      );
    }

    my $num_games = scalar @{$games_ref};

    my $hh_wins   = 0;
    my $hh_losses = 0;
    my $hh_draws  = 0;
    my $hh_for    = 0;
    my $hh_ag     = 0;

    for my $k ( 0 .. $num_games - 1 )
    {
      my $item = $games_ref->[$k];

      $game_data->{games_played}++;

      my $res = $item->{pr1_result};

      my $res_letter = HTML::convert_result_to_letter($res);

      my $res_to_win  = ( ( $res + 1 ) * ( $res + 0 ) ) / 2;
      my $res_to_loss = ( ( $res + 1 ) * ( $res + 0 ) / 2 ) * $NEGATIVE_ONE;
      my $res_to_draw
        = ( $res + 1 ) * ( $res + $NEGATIVE_ONE ) * $NEGATIVE_ONE;

      $game_data->{wins}   += $res_to_win;
      $game_data->{losses} += $res_to_loss;
      $game_data->{draws}  += $res_to_draw;

      if ( $type == $HTML_ID_HEAD_TO_HEAD_TYPE )
      {
        $hh_wins   += $res_to_win;
        $hh_losses += $res_to_loss;
        $hh_draws  += $res_to_draw;
      }

      $item->{pr1_result} = $res_letter;

      my $score     = $item->{pr1_score};
      my $opp_score = $item->{pr2_score};

      $game_data->{total_score}   += $score;
      $game_data->{total_against} += $opp_score;

      $hh_for += $score;
      $hh_ag  += $opp_score;

      HTML::populate_score_thresholds( $game_data, $score );

      HTML::populate_special_items(
        { score     => $score,
          opp_score => $opp_score,
          game_data => $game_data,
          item      => $item
        }
      );

      my $sub_row_class = $k % 2 == 1 ? 'rowodd' : 'roweven';

      $subentries .= Utils::make_row(
        { item  => $item,
          keys  => $games_keys_ref,
          class => $sub_row_class
        }
      );

      if ( $k == $num_games - 1 )
      {
        my $colspan
          = ( scalar @{$games_keys_ref} ) - $TOURNAMENT_AVERAGE_COLSPAN;
        my $af = sprintf "%.$ROUNDING_PLACE" . q{f}, $hh_for / $num_games;
        my $ag = sprintf "%.$ROUNDING_PLACE" . q{f}, $hh_ag / $num_games;
        $subentries
          .= '<tr> '
          . "<td colspan='$colspan'></td> "
          . '<td><b>Average:</b></td> '
          . "<td><b>$af</b></td> "
          . "<td><b>$ag</b></td> " . '</tr>';
      }
    }

    if ( $type == $HTML_ID_HEAD_TO_HEAD_TYPE )
    {
      $games_ref->[0]->{hh_games}  = $num_games;
      $games_ref->[0]->{hh_wins}   = $hh_wins;
      $games_ref->[0]->{hh_losses} = $hh_losses;
      $games_ref->[0]->{hh_draws}  = $hh_draws;
      $games_ref->[0]->{hh_pct}    = sprintf
        "%.$ROUNDING_PLACE" . q{f},
        ( $hh_wins + ( $hh_draws / 2 ) ) / $num_games;
      $games_ref->[0]->{hh_af} = sprintf "%.$ROUNDING_PLACE" . q{f},
        $hh_for / $num_games;
      $games_ref->[0]->{hh_aa} = sprintf "%.$ROUNDING_PLACE" . q{f},
        $hh_ag / $num_games;

      $new_entry .= Utils::make_new_entry_head(
        { games_ref       => $games_ref,
          keys_ref        => $keys_ref,
          row_class       => $row_class,
          entry_id        => $entry_id,
          title_length    => $title_length,
          games_title_row => $games_title_row
        }
      );
    }

    $tournament_results_list_html_string
      .= $new_entry . $subentries . "</table></div></td></tr>$NEWLINE";
  }

  $tournament_results_list_html_string .= "$NEWLINE</table>$NEWLINE";

  my $tournament_stats_html = {};

  if ( $type == $HTML_ID_TOURNAMENT_TYPE )
  {
    $tournament_ratings_html_string .= "$NEWLINE</table>$NEWLINE";
    HTML::build_ratings_table( $tournament_stats, $tournament_stats_html );
  }

  return {
    html    => $tournament_results_list_html_string,
    data    => $game_data,
    stats   => $tournament_stats_html,
    ratings => $tournament_ratings_html_string
  };
}

sub get_tournament_template_html_string
{
  my $division_data = shift;

  my $tournament_name = $division_data->[0]->{data}->{tournament_name};
  my $tournament_date = $division_data->[0]->{data}->{tournament_date};

  my $division_html_class = 'division';

  my $ddl = scalar @{$division_data};

  my $division_results = $EMPTY_STRING;

  my @ids_to_click = ();

  my $display_none_style = q{style='display:none;'};

  my $tourney_tabclass = 'tournament_tab';
  my $tourney_tablink  = 'tournament_tablink';

  my @tabdata = ();

  for my $i ( 0 .. $ddl - 1 )
  {
    my $id   = "division_$i";
    my $text = 'Division ' . ( $i + 1 );

    push @tabdata, [ $text, $id ];

    my $stats_tabclass    = "stats_tab_$id";
    my $stats_tablink     = "stats_tablink_$id";
    my $ratings_tabclass  = "ratings_tab_$id";
    my $ratings_tablink   = "ratings_tablink_$id";
    my $division_tabclass = "division_tab_$id";
    my $division_tablink  = "division_tablink_$id";

    if ( $i == 0 )
    {
      push @ids_to_click, "button_$id";
    }

    my $div_html    = $division_data->[$i]->{html};
    my $div_data    = $division_data->[$i]->{data};
    my $div_stats   = $division_data->[$i]->{stats};
    my $div_ratings = $division_data->[$i]->{ratings};

    my $stats_content = $EMPTY_STRING;
    my @stats_tabdata = ();

    my $stats_order_ref = $TOURNAMENT_STATS_ORDER;

    for my $k ( 0 .. scalar @{$stats_order_ref} - 1 )
    {
      my $cat     = $stats_order_ref->[$k];
      my $stat_id = "division_$i" . "_stats_$cat";
      push @stats_tabdata, [ $cat, $stat_id ];

      my $stat_html = $div_stats->{$cat};
      $stats_content
        .= "<div id='$stat_id' "
        . "class='$stats_tabclass' "
        . "$display_none_style> "
        . $stat_html
        . "</div>$NEWLINE";

      if ( $k == 0 )
      {
        push @ids_to_click, "button_$stat_id";
      }
    }

    $stats_content
      = Utils::make_tab_div( \@stats_tabdata, $stats_tabclass,
      $stats_tablink )
      . $stats_content;

    my $div_standings_id = "division_$i" . '_standings';
    my $div_stats_id     = "division_$i" . '_stats';
    my $div_ratings_id   = "division_$i" . '_ratings';

    push @ids_to_click, "button_$div_standings_id";

    my $div_tabs = Utils::make_tab_div(
      [ [ 'Standings',  $div_standings_id ],
        [ 'Statistics', $div_stats_id ],
        [ 'Ratings',    $div_ratings_id ]
      ],
      $division_tabclass,
      $division_tablink
    );

    my $div_standings_div
      = "<div id='$div_standings_id' "
      . "class='$division_tabclass' "
      . "$display_none_style>"
      . $div_html
      . '</div>';

    my $div_stats_div
      = "<div id='$div_stats_id' "
      . "class='$division_tabclass' "
      . "$display_none_style>"
      . $stats_content
      . '</div>';

    my $div_ratings_div
      = "<div id='$div_ratings_id' "
      . "class='$division_tabclass' "
      . "$display_none_style>"
      . $div_ratings
      . '</div>';

    my $div_content
      = $div_tabs . $div_standings_div . $div_stats_div . $div_ratings_div;

    $division_results
      .= "<div id='$id' "
      . "class='$tourney_tabclass'>"
      . $div_content
      . "</div>$NEWLINE";
  }

  my $tabs
    = Utils::make_tab_div( \@tabdata, $tourney_tabclass, $tourney_tablink );

  my $ids_to_click_javascript_array = q{[};

  for my $i ( 0 .. scalar @ids_to_click - 1 )
  {
    my $id = $ids_to_click[$i];
    $ids_to_click_javascript_array .= "'$id'";
    if ( $i != ( scalar @ids_to_click ) - 1 )
    {
      $ids_to_click_javascript_array .= ', ';
    }
  }

  $ids_to_click_javascript_array .= q{]};

  my $tournament_html_page = $EMPTY_STRING;

  $tournament_html_page .= <<"STOP";
$TEMPLATE_DOCTYPE
<html>
  <head>
  $TEMPLATE_META
  <title>$tournament_name</title>
  
  $TEMPLATE_SOURCES
  
  $TEMPLATE_STYLE
  
  <script type="text/javascript">
 
    $TEMPLATE_SCRIPTS

   
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
    $TEMPLATE_WESPA_IMAGE
    $TEMPLATE_NAV
    <div style="background-color:#90D1EF">
      <div style="background-color:white;padding-top:10px;"
           class="container">
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
      $TEMPLATE_FOOTER
    </div>
  </div>
  </body>
</html>

STOP

  return $tournament_html_page;

}

sub populate_score_thresholds
{
  my $game_data = shift;
  my $score     = shift;

  my @score_thresholds = (
    $ZEROTH_SCORE_THRESHOLD, $FIRST_SCORE_THRESHOLD,
    $SECOND_SCORE_THRESHOLD, $THIRD_SCORE_THRESHOLD,
    $FOURTH_SCORE_THRESHOLD,
  );

  for my $i ( 0 .. scalar @score_thresholds - 1 )
  {
    my $threshold      = $score_thresholds[$i];
    my $next_threshold = $score_thresholds[ $i + 1 ];

    my $numeric_threshold = $threshold;

    if ( $threshold eq $ZEROTH_SCORE_THRESHOLD )
    {
      $numeric_threshold = 0;
    }

    if ( $score >= $numeric_threshold
      && ( !$next_threshold || $score < $next_threshold ) )
    {
      $game_data->{over}->{$threshold}++;
      last;
    }
  }
  return 1;
}

sub populate_special_game_item
{
  my $special_item = shift;
  my $item         = shift;

  $special_item->{game_pointer}   = $item->{tr_id};
  $special_item->{player_pointer} = $item->{opp_id};
  $special_item->{player_name}    = $item->{opp_name};

  return 1;
}

sub populate_special_items
{
  my $arg_ref = shift;

  my $score     = $arg_ref->{score};
  my $opp_score = $arg_ref->{opp_score};
  my $game_data = $arg_ref->{game_data};
  my $item      = $arg_ref->{item};

  my $high_game_item    = $game_data->{special_games}->{high_game};
  my $low_game_item     = $game_data->{special_games}->{low_game};
  my $biggest_win_item  = $game_data->{special_games}->{biggest_win};
  my $biggest_loss_item = $game_data->{special_games}->{biggest_loss};
  my $high_loss_item    = $game_data->{special_games}->{high_loss};
  my $low_win_item      = $game_data->{special_games}->{low_win};

  if ( $score > $high_game_item->{value} )
  {
    $high_game_item->{value} = $score;
    HTML::populate_special_game_item( $high_game_item, $item );
  }
  if ( $score < $low_game_item->{value} )
  {
    $low_game_item->{value} = $score;
    HTML::populate_special_game_item( $low_game_item, $item );
  }
  if ( $score - $opp_score > $biggest_win_item->{value} )
  {
    $biggest_win_item->{value} = $score - $opp_score;
    HTML::populate_special_game_item( $biggest_win_item, $item );
  }
  if ( $opp_score - $score > $biggest_loss_item->{value} )
  {
    $biggest_loss_item->{value} = $opp_score - $score;
    HTML::populate_special_game_item( $biggest_loss_item, $item );
  }
  if ( $opp_score > $score && $score > $high_loss_item->{value} )
  {
    $high_loss_item->{value} = $score;
    HTML::populate_special_game_item( $high_loss_item, $item );
  }
  if ( $score > $opp_score && $score < $low_win_item->{value} )
  {
    $low_win_item->{value} = $score;
    HTML::populate_special_game_item( $low_win_item, $item );
  }
  return 1;
}

sub sanitize_tournament_data
{
  my $tournament_data_ref = shift;
  foreach my $data ( @{$tournament_data_ref} )
  {
    if ( !$data->{tr_start_ratings} || $data->{tr_start_rating} <= 0 )
    {
      $data->{tr_rating_change} = $EMPTY_STRING;
    }
    $data->{tr_start_rating}
      = Utils::empty_string_if_nonpositive( $data->{tr_start_rating} );
    $data->{tr_expected_wins}
      = Utils::empty_string_if_nonpositive( $data->{tr_expected_wins} );
    $data->{tr_old_world_rank}
      = Utils::empty_string_if_nonpositive( $data->{tr_old_world_rank} );
    $data->{tr_new_world_rank}
      = Utils::empty_string_if_nonpositive( $data->{tr_new_world_rank} );
    $data->{tr_old_national_rank}
      = Utils::empty_string_if_nonpositive( $data->{tr_old_national_rank} );
    $data->{tr_new_national_rank}
      = Utils::empty_string_if_nonpositive( $data->{tr_new_national_rank} );
  }
  return 1;
}

sub sort_tournament_data
{
  my $arg_ref = shift;

  my $tournament_results_hashref = $arg_ref->{results};
  my $tournament_stats           = $arg_ref->{stats};
  my $type                       = $arg_ref->{type};

  HTML::sort_tournament_stats( $tournament_stats, $type );

  my @tournament_results = values %{$tournament_results_hashref};

  @tournament_results
    = HTML::sort_tournament_results( \@tournament_results, $type );

  HTML::sort_tournament_games( \@tournament_results, $type );

  return @tournament_results;
}

sub sort_tournament_games
{
  my $tournament_results_ref = shift;
  my $type                   = shift;
  my @tournament_results     = @{$tournament_results_ref};

  foreach my $games (@tournament_results)
  {
    my @unsorted_games = @{$games};
    my @sorted_games;
    if ( $type == $HTML_ID_PLAYER_TYPE || $type == $HTML_ID_TOURNAMENT_TYPE )
    {
      @sorted_games
        = sort { $a->{g_round} <=> $b->{g_round} } @unsorted_games;
    }
    elsif ( $type == $HTML_ID_HEAD_TO_HEAD_TYPE )
    {
      @sorted_games = sort {
             $a->{tr_date} cmp $b->{tr_date}
          || $a->{g_round} <=> $b->{g_round}
      } @unsorted_games;
    }

    $games = \@sorted_games;
  }
  return 1;
}

sub sort_tournament_results
{
  my $tournament_results_ref = shift;
  my $type                   = shift;

  my @tournament_results = @{$tournament_results_ref};

  if ( $type == $HTML_ID_PLAYER_TYPE )
  {
    @tournament_results = sort {    ## no critic (ProhibitReverseSortBlock)
      $b->[0]->{tr_date} cmp $a->[0]->{tr_date}
        || $a->[0]->{tr_tournament_name} cmp $b->[0]->{tr_tournament_name}
    } @tournament_results;
  }
  elsif ( $type == $HTML_ID_TOURNAMENT_TYPE )
  {
    # First sort to determine the seeding
    @tournament_results
      = reverse sort {              ## no critic (ProhibitReverseSortBlock)
      if ( !$a->[0]->{tr_start_rating} && !$b->[0]->{tr_start_rating} )
      {
        $a->[0]->{tr_player_name} cmp $b->[0]->{tr_player_name};
      }
      elsif ( !$b->[0]->{tr_start_rating} )
      {
        return 1;
      }
      elsif ( !$a->[0]->{tr_start_rating} )
      {
        return $NEGATIVE_ONE;
      }
      else
      {
        return $a->[0]->{tr_start_rating} <=> $b->[0]->{tr_start_rating}
          || $a->[0]->{tr_player_name} cmp $b->[0]->{tr_player_name};
      }
      } @tournament_results;

    for my $i ( 0 .. scalar @tournament_results - 1 )
    {
      my @games = @{ $tournament_results[$i] };
      for my $k ( 0 .. scalar @games - 1 )
      {
        $tournament_results[$i]->[$k]->{tr_seed} = $i + 1;
      }
    }

    @tournament_results
      = sort { $a->[0]->{tr_position} <=> $b->[0]->{tr_position} }
      @tournament_results;
    my $num_players = scalar @tournament_results;
    foreach my $tr (@tournament_results)
    {
      my $l = scalar @{$tr};
      for my $n ( 0 .. $l - 1 )
      {
        $tr->[$n]->{tr_position}
          = $tr->[$n]->{tr_position} . " of $num_players";
      }
    }
  }
  elsif ( $type == $HTML_ID_HEAD_TO_HEAD_TYPE )
  {
    @tournament_results
      = reverse sort { scalar @{$a} <=> scalar @{$b} } @tournament_results;
  }

  return @tournament_results;
}

sub sort_tournament_stats
{
  my $tournament_stats = shift;
  my $type             = shift;

  if ( $type == $HTML_ID_TOURNAMENT_TYPE )
  {
    foreach my $key ( keys %{$tournament_stats} )
    {
      my $statitem = $tournament_stats->{$key};
      my @statlist = @{ $statitem->{list} };
      @statlist = sort { $statitem->{sort}->( $a, $b ) } @statlist;
      for my $i ( 0 .. scalar @statlist - 1 )
      {
        $statlist[$i]->{$GAME_STATS_RANK_NAME} = $i + 1;
      }
      $statitem->{list} = \@statlist;
    }
  }

  return 1;
}

sub special_game_to_html
{
  my $key  = shift;
  my $item = shift;

  if ( !$item->{player_name}
    || !$item->{player_pointer}
    || !$item->{game_pointer} )
  {
    return $EMPTY_STRING;
  }

  my @words = split /_/ms, $key;

  my @cap_words = ();

  for my $i ( 0 .. scalar @words - 1 )
  {
    my @letters = split //ms, $words[$i];
    $letters[0] = uc $letters[0];
    push @cap_words, ( join $EMPTY_STRING, @letters );
  }

  my $title = join q{ }, @cap_words;

  my $value          = $item->{value};
  my $player_name    = $item->{player_name};
  my $player_pointer = $item->{player_pointer};

  my $player_type       = $HTML_ID_PLAYER_TYPE;
  my $head_to_head_type = $HTML_ID_HEAD_TO_HEAD_TYPE;

  my $game_html_id = Utils::create_html_id( $HTML_ID_ENTRY_TAG, $player_type,
    $item->{game_pointer} );
  my $player_html_id
    = Utils::create_html_id( $HTML_ID_ENTRY_TAG, $head_to_head_type,
    $item->{player_pointer} );

  my $working_dir = $DEFAULT_SHORT_NAME_WORKING_DIR;
  my $html_dir    = $HTML_DIR;
  my $players_dir = $PLAYER_HTML_DIR;

  if ( ( $title eq 'Biggest Win' && $value < 0 )
    || ( $title eq 'Biggest Loss' && $value > 0 ) )
  {
    return $EMPTY_STRING;
  }

  my $special_game_line = <<"CONTENT"
  <b>$title:</b>
  <a href=\"#$game_html_id\"
     onclick=\"show_tournament_entry('$game_html_id')\">
       $value
  </a>
  (
   <a href=\"#$player_html_id\"
      onclick=\"show_head_to_head_entry('$player_html_id')\">
      vs
   </a>
   <a href=\"/$working_dir/$html_dir/$players_dir/$player_pointer.html\">
   $player_name
   </a>
  )
  <br>
CONTENT
    ;
  return $special_game_line;
}

1;
