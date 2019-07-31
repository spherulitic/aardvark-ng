#!/usr/bin/perl

# This script updates the WESPA html pages

use strict;
use warnings;
use Getopt::Long;
use Pod::Usage qw(pod2usage);
use DBI;
use Data::Dumper;
use List::Util qw(max);

use lib './modules';
use Constants;

require './scripts/templates.pl';
require './scripts/utils.pl';

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
  my $html_files_dir      = Constants::HTML_FILES_DIR;
  my $player_html_dir     = Constants::PLAYER_HTML_DIR;
  my $tournament_html_dir = Constants::TOURNAMENT_HTML_DIR;
  my $rankings_html_dir   = Constants::RANKINGS_HTML_DIR;

  system "mkdir -p $html_dir";
  system "mkdir -p $html_dir/$player_html_dir";
  system "mkdir -p $html_dir/$tournament_html_dir";
  system "mkdir -p $html_dir/$rankings_html_dir";

  my @player_ids_to_create = ();

  # Create new tournament html pages

  foreach my $tournament_id (@{$tournament_ids_to_create_ref})
  {
    if ($tournament_id != 301){next;}
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

  @player_ids_to_create = @{uniq(\@player_ids_to_create)};
  @player_ids_to_create = sort {$a <=> $b} @player_ids_to_create;

  my @country_rankings_to_create = ();

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
    else
    {
      push @country_rankings_to_create, $country_trigraph;
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

  @country_rankings_to_create = @{uniq(\@country_rankings_to_create)};

  update_rankings_html($dbh, \@country_rankings_to_create);

  update_player_search_data($dbh);

  my $cmd = "rm -rf $working_dir/$html_dir && cp -r $html_dir $working_dir";
  system $cmd;

  system "cp $html_files_dir/* /srv/dev/";
}

sub update_player_search_data
{
  my $dbh = shift;
  my $players_table = Constants::PLAYERS_TABLE_NAME;
  my @player_data = @{$dbh->selectall_arrayref("SELECT name, id FROM $players_table"  , {"RaiseError" => 1})};

  my $filename = Constants::HTML_FILES_DIR . '/' . Constants::PLAYER_SEARCH_DATA_FILENAME;

  my $working_dir = Constants::DEFAULT_SHORT_NAME_WORKING_DIR;
  my $html_dir = Constants::HTML_DIR;
  my $player_dir = Constants::PLAYER_HTML_DIR;

  my $html_id = "search_input_players";

  my $input_id = "datalist_input_element";
  my $escaped_char = "&quot;";

  my $html =
  "
  Player Name:
  <input list='$html_id' id='$input_id'>
    <datalist id='$html_id'>
  ";

  foreach my $item (@player_data)
  {
    my $name = $item->[0];
    my $id   = $item->[1];
    $html .= "<option data-value='$id' value=\"$name\"></option>\n";
  }
  
  $html .= "    </datalist>\n";


  my $function = <<FUNCTION
    onclick=
      "
        (function ()
        {
          var pname = document.getElementById('$input_id').value;
          console.log(pname);
          var pid   = document.querySelector('#$html_id option[value=$escaped_char'+pname+'$escaped_char]').dataset.value;
          console.log(pid);
          if (pid)
          {
            window.location.href = '/$working_dir/$html_dir/$player_dir/' + pid + '.html';
          }
        })()
      " 
FUNCTION
;

  $html .= "<input type='button' value='Submit' $function>";

  write_string_to_file($html, $filename);

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
    p.name                          AS opp_name, 
    p.id                            AS opp_id,
    p.rating                        AS opp_current_rating,
    tr_opp.start_rating             AS opp_rating,
    t.id                            AS t_id
  FROM
    $tr_table_name AS tr, $tr_table_name AS tr_opp, $g_table_name AS g, $pr_table_name AS pr1, $pr_table_name AS pr2, $p_table_name AS p, $t_table_name AS t, $d_table_name AS d
  WHERE
    t.id           = d.tournament_id     AND
    d.id           = tr.division_id      AND
    d.id           = tr_opp.division_id  AND
    p.id           = tr_opp.player_id    AND
    tr.division_id = g.division_id       AND
    tr.player_id   = pr1.player_id       AND
    g.id           = pr1.game_id         AND
    g.id           = pr2.game_id         AND
    pr1.id        != pr2.id              AND
    p.id           = pr2.player_id       AND
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
        'titles' => ['Rank', 'Player', 'Spread', 'Opponent', 'Round'],
        'values' => [$game_stats_rank_name, 'tr_player_name', $stat_key_name, 'opp_name', 'g_round'],
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
          return $data->{'opp_rating'} > $data->{'tr_start_rating'};
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
        'titles' => ['Rank', 'Player', 'Opponent', 'Rating Difference', 'Round'],
        'values' => [$game_stats_rank_name, 'tr_player_name', 'opp_name', $stat_key_name, 'g_round'],
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
                                 $b->[0]->{'tr_start_rating'} <=> $a->[0]->{'tr_start_rating'} ||
                                 $a->[0]->{'tr_player_name'}         cmp $b->[0]->{'tr_player_name'}
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


  my $tournament_results_list_html_string = "<table class='table'>\n";

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


  return [$tournament_results_list_html_string, $game_data, $tournament_stats_html];
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
            d.tournament_id = t.id AND
            tr.division_id  = d.id AND
            tr.player_id    = p.id AND
            p.country       = '$trigraph'
            
      ORDER BY t.end_date DESC
    "
  }
  else
  {
    $query =
    "
      SELECT id, name
      FROM $tournaments_tn
      GROUP BY end_date DESC
    "
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

  # @players = grep { !$_->{'deceased'} && !$_->{'suspended'} && $_->{'current'}} @players;   

  @players = sort { $b->{'rating'} <=> $a->{'rating'} } @players;

  my $full_rankings_string = "      <table class='table'>\n";

  my $titles = ['Ranking', 'Name', 'Country', 'Rating', 'Total Games', 'Last Played'];

  $full_rankings_string .= make_row(0, $titles, 1, 0, 0);

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


  my $el = "td";

  if ($is_title)
  {
    $el = "th";
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
    if (!(defined $val))
    {
      $val = "";
    }

    $row_string .= sprintf "<$el>%s</$el>", $val;
  }
  $row_string .= "</tr>\n";

  return $row_string;
}

sub make_link
{
  my $base_dir = shift;
  my $dir      = shift;
  my $filename = shift;
  my $content  = shift;

  return "<a href='/$base_dir/$dir/$filename'>$content</a>";
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


1;











