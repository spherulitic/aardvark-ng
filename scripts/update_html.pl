#!/usr/bin/perl

# This script updates the WESPA html pages

use strict;
use warnings;
use Getopt::Long;
use Pod::Usage qw(pod2usage);
use DBI;
use Data::Dumper;
use List::Util qw(max min);

use lib './modules';
use Constants;

require './scripts/templates.pl';
require './scripts/utils.pl';
require './scripts/deploy.pl';

unless (caller)
{
  my $dbh = connect_to_database();

  my $query = "SELECT id FROM " . Constants::TOURNAMENTS_TABLE_NAME;

  my @query_result = map { $_->[0]  }  @{$dbh->selectall_arrayref($query, {"RaiseError" => 1})};

  update_html(\@query_result); 
}

sub update_html
{
  my $tournament_ids_to_create_ref = shift;

  my $dbh = connect_to_database();

  my $working_dir         = Constants::DEFAULT_WORKING_DIR;
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


  # Create new tournament html pages

  foreach my $tournament_id (@{$tournament_ids_to_create_ref})
  {
    # if ($tournament_id != 38){next;}
    my @division_data = ();
    my @division_rows = @{query_table($dbh, Constants::DIVISIONS_TABLE_NAME, "tournament_id", $tournament_id)};

    foreach my $division_row (@division_rows)
    {
      my @players_in_division = @{query_table($dbh, Constants::TOURNAMENT_RESULTS_TABLE_NAME, "division_id", $division_row->{'id'})};
      push @player_ids_to_create, (map { $_->{'player_id'} } @players_in_division);
      push @division_data, get_tournament_results_html_string($dbh, $division_row->{'id'}, Constants::HTML_ID_TOURNAMENT_TYPE);
    }
    my $tournament_filename = "$html_dir/$tournament_html_dir/$tournament_id.html";

    my $tournament_html_page = get_tournament_template_html_string
    (
      \@division_data
    );

    write_string_to_file($tournament_html_page, $tournament_filename);
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

  @all_countries = @{uniq(\@all_countries)};

  my @country_rankings_to_create = map { $_->{'country'}  } (grep { !$_->{'deceased'} && !$_->{'suspended'} && $_->{'current'}   } @all_players);
  @country_rankings_to_create = @{uniq(\@country_rankings_to_create)};

  my %valid_link_countries = map { $_ => 1 } @country_rankings_to_create;

  @player_ids_to_create = @{uniq(\@player_ids_to_create)};
  @player_ids_to_create = sort {$a <=> $b} @player_ids_to_create;

  # Update the player html pages that have been changed
  foreach my $player_id (@player_ids_to_create)
  {
    my @player = @{query_table($dbh, Constants::PLAYERS_TABLE_NAME, "id", $player_id)};
  
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

    my $player_tournament_history   = get_tournament_results_html_string($dbh, $player_id, Constants::HTML_ID_PLAYER_TYPE);
    my $player_head_to_head_history = get_tournament_results_html_string($dbh, $player_id, Constants::HTML_ID_HEAD_TO_HEAD_TYPE);

    my $player_tournament_history_html = $player_tournament_history->[0];
    my $player_tournament_history_data = $player_tournament_history->[1];

    my $player_head_to_head_history_html = $player_head_to_head_history->[0];

    my $player_html_page = get_player_template_html_string
    (
      $player_info,
      $player_tournament_history_html,
      $player_head_to_head_history_html,
      $player_tournament_history_data
    );
  
    # print $html_page;
    my $filename =  Constants::HTML_DIR . '/' . Constants::PLAYER_HTML_DIR . '/' . $player_id . ".html";

    write_string_to_file($player_html_page, $filename);
  }

  # Update the full ranking list

  check_country_flag_icons(\@country_rankings_to_create);

  update_rankings_html($dbh, \@country_rankings_to_create);

  update_dynamically_loaded_content($dbh, \@all_countries);

  deploy();
}

sub check_country_flag_icons
{
  my $country_ref = shift;

  my @countries = @{$country_ref};

  my $filename_prefix = Constants::COUNTRY_FLAGS_DIR;
  my $trigraph_hashref = Constants::COUNTRY_TRIGRAPH_TO_COUNTRY_NAME_HASHREF;

  opendir my $flag_dir_handle, $filename_prefix or die "Cannot open $filename_prefix: $!\n";
  my @existing_flags = grep (/[A-Z]{3}/, readdir($flag_dir_handle));

  foreach my $ef (@existing_flags)
  {
    $ef =~ /(([A-Z]{3}))/;
    if (!$trigraph_hashref->{$1})
    {
      print "\nInvalid flag image name: $1\n\n";
    }
  }

  my $extension = ".png";

  foreach my $country (@countries)
  {
    my $flag = $filename_prefix . '/' . $country . $extension;
    if (!(-e $flag))
    {
      print "\nCountry does not have a flag image: $country\nMissing file:$flag\n\n";
    }
  }
}

sub update_dynamically_loaded_content
{
  my $dbh               = shift;
  my $all_countries_ref = shift;

  my $players_table = Constants::PLAYERS_TABLE_NAME;
  my @player_data = @{$dbh->selectall_arrayref("SELECT * FROM $players_table"  , {Slice => {}, "RaiseError" => 1})};

  @player_data = sort {$b->{'rating'} <=> $a->{'rating'}} @player_data;

  my @valid_player_data = grep { !$_->{'deceased'} && !$_->{'suspended'} && $_->{'current'}} @player_data;   

  my $cutoff = Constants::FRONT_PAGE_RATINGS_CUTOFF;

  $cutoff = min($cutoff, scalar @valid_player_data);

  my $peek_html = "<table class='table'>\n";
  $peek_html .=
    make_row
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
    $peek_html .= make_row($player, ['rank', 'name', 'rating'], 0, 0, $row_class);
  }
  $peek_html .= "</table>\n";

  my $peek_filename = Constants::HTML_DATA_DIR . '/' . Constants::FRONT_PAGE_RATINGS_DATA_FILENAME;

  write_string_to_file($peek_html, $peek_filename);

  my $player_search_filename = Constants::HTML_DATA_DIR . '/' . Constants::PLAYER_SEARCH_DATA_FILENAME;

  my $working_dir = Constants::DEFAULT_SHORT_NAME_WORKING_DIR;
  my $html_dir = Constants::HTML_DIR;
  my $player_dir = Constants::PLAYER_HTML_DIR;

  my $player_search_html =
    get_datalist_html
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

  write_string_to_file($player_search_html, $player_search_filename);

  my $country_search_filename = Constants::HTML_DATA_DIR . '/' . Constants::COUNTRY_SEARCH_DATA_FILENAME;

  my $rankings_dir = Constants::RANKINGS_HTML_DIR;

  my @country_data = map { $_->{'country'}  } @valid_player_data;

  @country_data = @{uniq(\@country_data)};


  my $trigraph_hashref = Constants::COUNTRY_TRIGRAPH_TO_COUNTRY_NAME_HASHREF;

  @country_data = grep {$trigraph_hashref->{$_}} @country_data;

  @country_data = map { {'trigraph' => $_, 'country' => $trigraph_hashref->{$_}}   } @country_data;

  my $country_search_html =
    get_datalist_html
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

  write_string_to_file($country_search_html, $country_search_filename);

  my @all_countries = @{$all_countries_ref};

  my @localtime = localtime();
  my $current_year = $localtime[5] + 1900;
  my $year_options = "";
  my $country_options = "";
  

  for (my $i = 2000; $i <= $current_year; $i++)
  {
    $year_options .= "<option value='$i'>$i</option>\n";
  }

  @all_countries = sort @all_countries;

  for (my $i = 0; $i < scalar @all_countries; $i++)
  {
    my $trigraph = $all_countries[$i];
    my $fullname = $trigraph_hashref->{$trigraph};
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

  write_string_to_file($tournament_form, $tournament_form_name); 

}

sub get_datalist_html
{
  my $data           = shift;
  my $title          = shift;
  my $href           = shift;
  my $html_id        = shift;
  my $input_id       = shift;
  my $button_id      = shift;
  my $data_value_key = shift;
  my $value_key      = shift;

  my $escaped_char = "&quot;";

  my $function = <<FUNCTION

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
  my $input_function = <<FUNCTION

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

  my $submit_function = <<FUNCTION
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

sub write_string_to_file
{
  my $string   = shift;
  my $filename = shift;

  open(my $fh, '>', $filename);
  print $fh $string;
  close $fh;

  print "Created $filename\n";

}

sub get_tournament_results_html_string
{
  my $dbh  = shift;
  my $id   = shift;
  my $type = shift;

  my $player_type       = Constants::HTML_ID_PLAYER_TYPE;
  my $tournament_type   = Constants::HTML_ID_TOURNAMENT_TYPE;
  my $head_to_head_type = Constants::HTML_ID_HEAD_TO_HEAD_TYPE;

  my $tr_table_name = Constants::TOURNAMENT_RESULTS_TABLE_NAME;
  my $g_table_name  = Constants::GAMES_TABLE_NAME;
  my $pr_table_name = Constants::PLAYER_RESULTS_TABLE_NAME;
  my $p_table_name  = Constants::PLAYERS_TABLE_NAME;
  my $t_table_name  = Constants::TOURNAMENTS_TABLE_NAME;
  my $d_table_name  = Constants::DIVISIONS_TABLE_NAME;

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
  elsif ($type == $tournament_type)
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
    $data->{'tr_start_rating'}      = empty_string_if_nonpositive($data->{'tr_start_rating'});
    $data->{'tr_expected_wins'}     = empty_string_if_nonpositive($data->{'tr_expected_wins'});
    $data->{'tr_old_world_rank'}    = empty_string_if_nonpositive($data->{'tr_old_world_rank'});
    $data->{'tr_new_world_rank'}    = empty_string_if_nonpositive($data->{'tr_new_world_rank'});
    $data->{'tr_old_national_rank'} = empty_string_if_nonpositive($data->{'tr_old_national_rank'});
    $data->{'tr_new_national_rank'} = empty_string_if_nonpositive($data->{'tr_new_national_rank'});
  }

  # Prepare tournament stats datastructure

  my $tournament_stats;
  my $game_stats_rank_name = Constants::GAME_STATS_RANK_NAME;
  my $stat_key_name        = Constants::STAT_KEY_NAME;

  if ($type == $tournament_type)
  {
    $tournament_stats =
    {

      'High Win' =>
      {
        'cond' =>
        sub
        {
          my $data = shift;
          return $data->{'pr1_score'} > $data->{'pr2_score'};
        },
        'eval' =>
        sub
        {
          my $data = shift;
          return $data->{'pr1_score'};
        },
        'sort' =>
        sub
        {
          $b->{$stat_key_name} <=> $a->{$stat_key_name}
        },
        'titles' => ['Rank', 'Player', 'Score', 'Opponent', 'Round'],
        'values' => [$game_stats_rank_name, 'tr_player_name', $stat_key_name, 'opp_name', 'g_round'],
        'list'   => []
      },

      'High Loss' =>
      {
        'cond' =>
        sub
        {
          my $data = shift;
          return $data->{'pr1_score'} < $data->{'pr2_score'};
        },
        'eval' =>
        sub
        {
          my $data = shift;
          return $data->{'pr1_score'};
        },
        'sort' =>
        sub
        {
          $b->{$stat_key_name} <=> $a->{$stat_key_name}
        },
        'titles' => ['Rank', 'Player', 'Score', 'Opponent', 'Round'],
        'values' => [$game_stats_rank_name, 'tr_player_name', $stat_key_name, 'opp_name', 'g_round'],
        'list'   => []
      },


      'High Spread' =>
      {
        'cond' =>
        sub
        {
          my $data = shift;
          return $data->{'pr1_score'} > $data->{'pr2_score'}
        },
        'eval' =>
        sub
        {
          my $data = shift;
          return $data->{'pr1_score'} - $data->{'pr2_score'};
        },
        'sort' =>
        sub
        {
          $b->{$stat_key_name} <=> $a->{$stat_key_name}
        },
        'titles' => ['Rank', 'Player', 'Opponent', 'Player Score', 'Opponent Score', 'Spread', 'Round'],
        'values' => [$game_stats_rank_name, 'tr_player_name', 'opp_name', 'pr1_score', 'pr2_score', $stat_key_name, 'g_round'],
        'list'   => []
      },


      'High Combined' =>
      {
        'cond' =>
        sub
        {
          my $data = shift;
          # Ensure only one instance gets reported 
          return $data->{'tr_player_id'} > $data->{'opp_id'};
        },
        'eval' =>
        sub
        {
          my $data = shift;
          return $data->{'pr1_score'} + $data->{'pr2_score'};
        },
        'sort' =>
        sub
        {
          $b->{$stat_key_name} <=> $a->{$stat_key_name}
        },
        'titles' => ['Rank', 'Players', '', 'Combined Score', 'Round'],
        'values' => [$game_stats_rank_name, 'tr_player_name', 'opp_name', $stat_key_name, 'g_round'],
        'list'   => []
      },


      'Low Combined' =>
      {
        'cond' =>
        sub
        {
          my $data = shift;
          # Ensure only one instance gets reported 
          return $data->{'tr_player_id'} > $data->{'opp_id'};
        },
        'eval' =>
        sub
        {
          my $data = shift;
          return $data->{'pr1_score'} + $data->{'pr2_score'};
        },
        'sort' =>
        sub
        {
          $a->{$stat_key_name} <=> $b->{$stat_key_name}
        },
        'titles' => ['Rank', 'Players', '', 'Combined Score', 'Round'],
        'values' => [$game_stats_rank_name, 'tr_player_name', 'opp_name', $stat_key_name, 'g_round'],
        'list'   => []
      },


      'Upsets' =>
      {
        'cond' =>
        sub
        {
          my $data = shift;
          return $data->{'tr_start_rating'} && $data->{'opp_rating'} > $data->{'tr_start_rating'};
        },
        'eval' =>
        sub
        {
          my $data = shift;
          return $data->{'opp_rating'} - $data->{'tr_start_rating'};
        },
        'sort' =>
        sub
        {
          $b->{$stat_key_name} <=> $a->{$stat_key_name}
        },
        'titles' => ['Rank', 'Player', 'Player Rating', 'Opponent', 'Opponent Rating', 'Rating Difference', 'Round'],
        'values' => [$game_stats_rank_name, 'tr_player_name', 'tr_start_rating', 'opp_name', 'opp_rating', $stat_key_name, 'g_round'],
        'list'   => []
      }
    };
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
 
      my $func = $statitem->{'sort'};

      @statlist = sort {&$func} @statlist;
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
    @tournament_results = sort {$b->[0]->{'tr_date'} cmp $a->[0]->{'tr_date'}} @tournament_results;
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

  my $tournament_title_ref = ['Details', '#', 'Tournament', 'Date', 'Wins', 'Losses', 'Byes', 'Spread', 'Place', 'Start Rating', 'End Rating', 'Rating Change'];
  my $tournament_keys_ref  = ['details', '#', 'tr_tournament_name', 'tr_date', 'tr_wins', 'tr_losses', 'tr_byes', 'tr_spread', 'tr_position', 'tr_start_rating', 'tr_end_rating', 'tr_rating_change'];

  my $tournament_standings_title_ref = ['Details', 'Place'      ,    'Seed', 'Name',              'Wins',    'Losses',    'Byes',    'Spread',    'Start Rating', 'End Rating', 'Rating Change'];
  my $tournament_standings_keys_ref  = ['details', 'tr_position', 'tr_seed', 'tr_player_name', 'tr_wins', 'tr_losses', 'tr_byes', 'tr_spread', 'tr_start_rating', 'tr_end_rating', 'tr_rating_change'];

  my $games_title_ref = ['Round', 'Opponent', 'Opponent Rating', 'Result', 'Scores', ''];
  my $games_keys_ref  = ['g_round', 'opp_name', 'opp_rating',  'pr1_result', 'pr1_score', 'pr2_score'];

  my $head_to_head_title_ref = ['Details', '', 'Opponent', 'Rating', 'Games', 'Wins', 'Losses', 'Draws', 'Pct', 'Average For', 'Average Against'];
  my $head_to_head_keys_ref  = ['details', '#', 'opp_name', 'opp_current_rating', 'hh_games', 'hh_wins', 'hh_losses', 'hh_draws', 'hh_pct', 'hh_af', 'hh_aa'];

  my $head_to_head_games_title_ref = ['Tournament', 'Date', 'Round', 'Result', 'Rating', 'Opponent Rating', 'Score', ''];
  my $head_to_head_games_keys_ref  = ['tr_tournament_name', 'tr_date', 'g_round', 'pr1_result', 'tr_start_rating', 'opp_rating', 'pr1_score', 'pr2_score'];


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
      make_row
      (
        0,
        $ratings_super_title_ref,
        1,
        0,
        'white',
        2
      );
    $tournament_ratings_html_string .=
      make_row
      (
        0,
        $ratings_title_ref,
        1,
        0,
        'white',
      );
  }

  my $title_length = scalar @{$title_ref};

  $tournament_results_list_html_string .=
    make_row
    (
      0,
      $title_ref,
      1,
      0,
      'white'
    );

  my $games_title_row = 
    make_row
    (
      0,
      $sub_title_ref,
      1,
      0,
      0
    );

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
      '300' => 0,
      '400' => 0,
      '500' => 0,
      '600' => 0
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
    my $button_id = create_html_id(Constants::HTML_ID_BUTTON_TAG, $type, $games_ref->[0]->{'tr_id'});
    my $entry_id  = create_html_id(Constants::HTML_ID_ENTRY_TAG,  $type, $games_ref->[0]->{'tr_id'});
    my $row_class = 'roweven';
    
    if ($i % 2 == 1)
    {
      $row_class = 'rowodd';
    }

    if ($type == $head_to_head_type)
    {
      $button_id = create_html_id(Constants::HTML_ID_BUTTON_TAG, $type, $games_ref->[0]->{'opp_id'});
      $entry_id = create_html_id(Constants::HTML_ID_ENTRY_TAG,   $type, $games_ref->[0]->{'opp_id'});
    }

    $games_ref->[0]->{'#'} = $i + 1;

    $games_ref->[0]->{'details'} = "<button type='button' id='$button_id'  class='btn btn-info' data-toggle='collapse' data-target='#" . $entry_id  . "'>+</button>";


    if ($type != $head_to_head_type)
    {
      $new_entry .= make_new_entry_head($games_ref, $keys_ref, $row_class, $entry_id, $title_length, $games_title_row);
    }

    if ($type == $tournament_type)
    {
      $tournament_ratings_html_string .=
        make_row
        (
          $games_ref->[0],
          $ratings_keys_ref,
          0,
          0,
          $row_class
        );
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

      if ($type == $head_to_head_type)
      {
        $hh_for += $score;
        $hh_ag  += $opp_score;
      }

      if ($score >= 300)
      {
        $game_data->{'over'}->{'300'}++;
      }
      if ($score >= 400)
      {
        $game_data->{'over'}->{'400'}++;
      }
      if ($score >= 500)
      {
        $game_data->{'over'}->{'500'}++;
      }
      if ($score >= 600)
      {
        $game_data->{'over'}->{'600'}++;
      }

      if ($score > $high_game_item->{'value'})
      {
        $high_game_item->{'value'} = $score;
        populate_special_game_item($high_game_item, $item);
      }
      if ($score < $low_game_item->{'value'})
      {
        $low_game_item->{'value'} = $score;
        populate_special_game_item($low_game_item, $item);
      }
      if ($score - $opp_score > $biggest_win_item->{'value'})
      {
        $biggest_win_item->{'value'} = $score - $opp_score;
        populate_special_game_item($biggest_win_item, $item);
      }
      if ($opp_score - $score > $biggest_loss_item->{'value'})
      {
        $biggest_loss_item->{'value'} = $opp_score - $score;
        populate_special_game_item($biggest_loss_item, $item);
      }
      if ($opp_score > $score && $score > $high_loss_item->{'value'})
      {
        $high_loss_item->{'value'} = $score;
        populate_special_game_item($high_loss_item, $item);
      }
      if ($score > $opp_score && $score < $low_win_item->{'value'})
      {
        $low_win_item->{'value'} = $score;
        populate_special_game_item($low_win_item, $item);
      }

      my $sub_row_class = 'roweven';
    
      if ($k % 2 == 1)
      {
        $sub_row_class = 'rowodd';
      }


      $subentries .=
        make_row
        (
          $item,
          $games_keys_ref,
          0,
          0,
          $sub_row_class
        );    
    }

    if ($type == $head_to_head_type)
    {
      my $rounding = Constants::ROUNDING_PLACE;

      $games_ref->[0]->{'hh_games'}  = $num_games;
      $games_ref->[0]->{'hh_wins'}   = $hh_wins;
      $games_ref->[0]->{'hh_losses'} = $hh_losses;
      $games_ref->[0]->{'hh_draws'}  = $hh_draws;
      $games_ref->[0]->{'hh_pct'}    = sprintf ("%.".$rounding."f", ($hh_wins + ($hh_draws / 2)) / $num_games);
      $games_ref->[0]->{'hh_af'}     = sprintf ("%.".$rounding."f", $hh_for / $num_games);
      $games_ref->[0]->{'hh_aa'}     = sprintf ("%.".$rounding."f", $hh_ag  / $num_games);

      $new_entry .= make_new_entry_head($games_ref, $keys_ref, $row_class, $entry_id, $title_length, $games_title_row);
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
        make_row
        (
          0,
          $dataitem->{'titles'},
          1,
          0,
          0   
        );
      my @statlist = @{$dataitem->{'list'}};
      for (my $i = 0; $i < scalar @statlist; $i++)
      {
        my $sub_row_class = 'roweven';
    
        if ($i % 2 == 1)
        {
          $sub_row_class = 'rowodd';
        }

        my $statitem = $statlist[$i];
        $html_string .= make_row($statitem, $dataitem->{'values'}, 0, 0, $sub_row_class);
      }
      $html_string .= "        </table>";

      $tournament_stats_html->{$key} = $html_string;
    }
  }


  return [$tournament_results_list_html_string, $game_data, $tournament_stats_html, $tournament_ratings_html_string];
}

sub make_new_entry_head
{
  my $games_ref       = shift;
  my $keys_ref        = shift;
  my $row_class       = shift;
  my $entry_id        = shift;
  my $title_length    = shift;
  my $games_title_row = shift;

  my $new_entry = "";

      $new_entry .=
          make_row
          (
            $games_ref->[0], 
            $keys_ref,
            0,
            0,
            $row_class
          );

      $new_entry .= "<tr style='border: none'><td style='padding: 0px; border: 0px'></td><td style='padding: 0px; border: 0px'  colspan='" . ( $title_length - 1) . "'><div class='collapse' id='$entry_id'><table class='table'>\n";

      $new_entry .= $games_title_row;

  return $new_entry;
}

sub populate_special_game_item
{
  my $special_item = shift;
  my $item         = shift;

  $special_item->{'game_pointer'}     = $item->{'tr_id'};
  $special_item->{'player_pointer'}   = $item->{'opp_id'};
  $special_item->{'player_name'}      = $item->{'opp_name'};
}

sub update_rankings_html
{
  my $dbh = shift;
  my $countries_ref = shift;

  my $trigraph_hashref = Constants::COUNTRY_TRIGRAPH_TO_COUNTRY_NAME_HASHREF;
  my $base_dir = Constants::DEFAULT_SHORT_NAME_WORKING_DIR . '/' . Constants::HTML_DIR;
  my $tournament_dir = Constants::TOURNAMENT_HTML_DIR;

  my $most_recent_tournament = get_most_recent_tournament($dbh);
  my $full_rankings_data = 
    {
      'title' => "WESPA RATINGS",
      'tournament_link'        => make_link
                                  (
                                    $base_dir,
                                    $tournament_dir,
                                    $most_recent_tournament->[0] . ".html",
                                    $most_recent_tournament->[1],
                                  )
    };

  my $full_ranking_html_string = get_rankings_html_string($dbh);
  my $full_ranking_html_page =
    get_rankings_template_html_string
    (
      $full_ranking_html_string,
      $full_rankings_data
    );
  my $full_ranking_filename = Constants::HTML_DIR . '/' . Constants::RANKINGS_HTML_DIR . "/full_rankings.html";
  write_string_to_file($full_ranking_html_page, $full_ranking_filename);

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
    my $most_recent_tournament = get_most_recent_tournament($dbh, $country);


    my $rankings_data = 
    {
      'title' => $country_fullname . " RATINGS",
      'tournament_link'        => make_link
                                  (
                                    $base_dir,
                                    $tournament_dir,
                                    $most_recent_tournament->[0] . ".html",
                                    $most_recent_tournament->[1],
                                  )
    };

    my $country_ranking_html_string = get_rankings_html_string($dbh, $country);
    my $country_ranking_html_page =
       get_rankings_template_html_string
       (
         $country_ranking_html_string,
         $rankings_data
       );
    my $country_ranking_filename = Constants::HTML_DIR . '/' . Constants::RANKINGS_HTML_DIR . "/$country.html";
    write_string_to_file($country_ranking_html_page, $country_ranking_filename); 
  }
}

sub get_most_recent_tournament
{
  my $dbh      = shift;
  my $trigraph = shift;

  my $tournaments_tn        = Constants::TOURNAMENTS_TABLE_NAME;
  my $divisions_tn          = Constants::DIVISIONS_TABLE_NAME;
  my $tournament_results_tn = Constants::TOURNAMENT_RESULTS_TABLE_NAME;
  my $players_tn            = Constants::PLAYERS_TABLE_NAME;
  
  my $query;
  
  if ($trigraph)
  {
    $query =
    "
      SELECT t.id AS id, t.name AS name
      FROM $tournament_results_tn AS tr, $players_tn AS p, $divisions_tn AS d, $tournaments_tn AS t
      WHERE
            d.tournament_id = t.id        AND
            tr.division_id  = d.id        AND
            tr.player_id    = p.id        AND
            p.country       = '$trigraph' AND
            p.deceased      = 0           AND
            p.suspended     = 0           AND
            p.current       = 1
            
      ORDER BY t.end_date DESC
    ";
  }
  else
  {
    $query =
    "
      SELECT id, name
      FROM $tournaments_tn
      GROUP BY end_date DESC
    ";
  }
  my @tournament_name = @{$dbh->selectall_arrayref($query, {"RaiseError" => 1})};
  return [$tournament_name[0]->[0],  $tournament_name[0]->[1]];

}

sub get_rankings_html_string
{
  my $dbh     = shift;
  my $country = shift;
  
  my @players;

  if ($country)
  {
    @players = @{query_table($dbh, Constants::PLAYERS_TABLE_NAME, 'country', $country)};
  }
  else
  {
    @players = @{$dbh->selectall_arrayref("SELECT * FROM " . Constants::PLAYERS_TABLE_NAME, {Slice => {}, "RaiseError" => 1})};
  }

  @players = grep { !$_->{'deceased'} && !$_->{'suspended'} && $_->{'current'}} @players;   

  @players = sort { $b->{'rating'} <=> $a->{'rating'} } @players;

  my $full_rankings_string = "      <table class='table'>\n";

  my $titles = ['Ranking', 'Name', 'Country', 'Rating', 'Total Games', 'Last Played'];

  $full_rankings_string .= make_row(0, $titles, 1, 0, 'white');

  for (my $i = 0; $i < scalar @players; $i++)
  {
    my $row_class = 'roweven';
    
    if ($i % 2 == 1)
    {
      $row_class = 'rowodd';
    }

    my $item = $players[$i];
    $item->{'ranking'} = $i + 1;
    $full_rankings_string .= make_row($item, ['ranking', 'name', 'country', 'rating', 'total_games', 'last_played'], 0, 0, $row_class);
  }

  $full_rankings_string    .= "      </table>\n";
  return $full_rankings_string;
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

sub query_table
{
  my $dbh         = shift;
  my $table       = shift;
  my $table_field = shift;
  my $query_field = shift;

  my $query = "SELECT * FROM $table WHERE $table_field='$query_field'";

  my $query_result = $dbh->selectall_arrayref($query, {Slice => {}, "RaiseError" => 1});

  return $query_result;
}

sub empty_string_if_nonpositive
{
  my $num = shift;
  if (!$num || $num <= 0)
  {
    return "";
  }
  return $num;
}

1;











