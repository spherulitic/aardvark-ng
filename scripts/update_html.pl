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

# require './scripts/templates.pl';

my $database_name = Constants::DATABASE_NAME;
my $host_name     = Constants::DATABASE_HOST_NAME;
my $user_name     = Constants::DATABASE_USER_NAME;
my $password      = Constants::DATABASE_PASSWORD;

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

  system "mkdir -p $html_dir";
  system "mkdir -p $html_dir/$player_html_dir";
  system "mkdir -p $html_dir/$tournament_html_dir";
  system "mkdir -p $html_dir/$rankings_html_dir";

  my @player_ids_to_create = ();

  # Create new tournament html pages

  foreach my $tournament_id (@{$tournament_ids_to_create_ref})
  {
    my @division_data = ();
    my @division_rows = @{query_table($dbh, Constants::DIVISIONS_TABLE_NAME, "tournament_id", $tournament_id)};

    foreach my $division_row (@division_rows)
    {
      push @division_data, get_tournament_results_html_string($dbh, $division_row->{'id'}, 1);
    }
    my $tournament_filename = Constants::HTML_DIR . '/' . Constants::TOURNAMENT_HTML_DIR . '/' . $tournament_id . ".html"
    write_string_to_file(get_tournament_template_html_string(\@division_data), $filename);

  }


  # Update the player html pages that have been changed
  foreach my $player_id (@player_ids_to_create)
  {
    my @player = @{query_table($dbh, Constants::PLAYERS_TABLE_NAME, "id", $player_id)};
  
    my $player_name    = $player[0]->{'name'};
    my $country        = $player[0]->{'country'};
    my $games_played   = $player[0]->{'total_games'};
    my $rating         = $player[0]->{'rating'};
    my $photo_filename = $player[0]->{'photo'};

    if (!$country)
    {
      $country = "";
    }  
    if (!$photo_filename)
    {
      $photo_filename = Constants::DEFAULT_WORKING_DIR . '/' . Constants::PHOTO_DIR . '/noimage.gif';
    }
    my $player_info =
    {
      'name'           => $player_name,
      'country'        => $country,
      'games_played'   => $player_name,
      'rating'         => $current_rating,
      'photo_filename' => $photo_filename,
    }

    my $player_tournament_history   = get_tournament_results_html_string($dbh, $player_id, 0);
    my $player_head_to_head_history = get_tournament_results_html_string($dbh, $player_id, 2);

    my $player_tournament_history_html = $player_tournament_history->[0];
    my $player_tournament_history_data = $player_tournament_history->[1];

    my $player_head_to_head_history_html = $player_head_to_head_history->[0];

    my $html_page = get_player_template_html_string
    (
      $player_info,
      $player_tournament_history_html,
      $player_head_to_head_history_html,
      $player_tournament_history_data
    );
  
    # print $html_page;
    my $filename =  Constants::HTML_DIR . '/' . Constants::PLAYER_HTML_DIR . '/' . $player_id . ".html";

    write_string_to_file($html_page, $filename);
  }

  # Update the full ranking list

  update_full_rankings_html($dbh);

  update_country_rankings_html($dbh);

  system "cp -r $html_dir $working_dir";
}

sub write_string_to_file
{
  my $string   = shift;
  my $filename = shift;

  open(my $fh, '>', $filename);
  print $fh $string;
  close $fh;
}

sub create_tournament_html_from_struct
{
  my $tournament_id = shift;
  my $struct        = shift;

  my $tournament_tables_string = "    <div>\n";

  foreach my $key (keys %{$struct})
  {
    my $div_table_string = "      <table>\n";

    $div_table_string .= "        <tr><th>Place</th><th>Name</th><th>Wins</th><th>Losses</th><th>Byes</th><th>Spread</th><th>Old Rating</th><th>New Rating</th></tr>\n";

    my @results = @{$struct->{$key}};
  
    for (my $i = 0; $i < scalar @results; $i++)
    {
      my $item = $results[$i];
      if (!(keys %{$item}))
      {
        die "Empty hash in id $tournament_id :\n" . Dumper($struct);
      }
      $div_table_string .= make_row($item, ['position', 'player_name', 'wins', 'losses', 'byes', 'spread', 'start_rating', 'end_rating']);
    }

    $div_table_string    .= "      </table>\n";

    $tournament_tables_string .= $div_table_string;

  }

  $tournament_tables_string   .= "    </div>";

  my $html_page =
"
<html>
  <head>
  </head>
  <body>
$tournament_tables_string
  </body>
</html>
";

  # print $html_page;
  
  open(my $fh, '>', Constants::HTML_DIR . '/' . Constants::TOURNAMENT_HTML_DIR . '/' . $tournament_id . ".html");
  print $fh $html_page;
  close $fh;
}

sub create_player_html_from_database
{
  my $dbh       = shift;
  my $player_id = shift;

  my @player = @{query_table($dbh, Constants::PLAYERS_TABLE_NAME, "id", $player_id)};

  my $player_name    = $player[0]->{'name'};
  my $country        = $player[0]->{'country'};
  my $games_played   = $player[0]->{'total_games'};
  my $current_rating = $player[0]->{'rating'};
  my $photo_filename = $player[0]->{'photo'};

  if (!$country)
  {
    $country = "";
  }

  if (!$photo_filename)
  {
    $photo_filename = Constants::DEFAULT_WORKING_DIR . '/' . Constants::PHOTO_DIR . '/noimage.gif';
  }


  my @result_rows = @{query_table($dbh, Constants::TOURNAMENT_RESULTS_TABLE_NAME, "player_id", $player_id)};

  @result_rows = sort { $b->{'date'} cmp $a->{'date'} } @result_rows;

  my $tournament_history_string = "      <table>\n";

  $tournament_history_string .= "        <tr><th>Date</th><th>Place</th><th>Name</th><th>Wins</th><th>Losses</th><th>Byes</th><th>Spread</th><th>Old Rating</th><th>New Rating</th></tr>\n"; 

  for (my $i = 0; $i < scalar @result_rows; $i++)
  {
    my $item = $result_rows[$i];
    if (!(keys %{$item}))
    {
      die "Empty players hash in id $player_id :\n" . Dumper(\@result_rows);
    }
    $tournament_history_string .= make_row($item, ['date', 'position', 'player_name', 'wins', 'losses', 'byes', 'spread', 'start_rating', 'end_rating'], 'tournament');

  }

  $tournament_history_string    .= "      </table>\n";

  # Get Head to Head record

  my $pr_name = Constants::PLAYER_RESULTS_TABLE_NAME;
  my $p_name  = Constants::PLAYERS_TABLE_NAME;

  my $head_to_head_query =
  "
    SELECT p.id AS id, p.name AS name, COUNT(*) AS total, SUM(pr1.result = 1) AS wins, SUM(pr1.result = 1) / COUNT(*) AS win_percentage
    FROM $pr_name AS pr1, $pr_name AS pr2, $p_name AS p
    WHERE pr1.game_id   = pr2.game_id  AND
          pr1.player_id = $player_id AND
          pr2.player_id = p.id       AND
          pr1.id       != pr2.id
    GROUP BY p.id
    ORDER BY COUNT(*) DESC;
  ";


  my @head_to_head_results = @{$dbh->selectall_arrayref($head_to_head_query, {Slice => {}, "RaiseError" => 1})};

  my $head_to_head_string = "      <table>\n";

  $head_to_head_string .= "        <tr><th>#</th><th>Opponent</th><th>Played</th><th>Wins</th><th>Win Percentage</th></tr>\n"; 

  for (my $i = 0; $i < scalar @head_to_head_results; $i++)
  {
    my $item = $head_to_head_results[$i];
    $item->{'ranking'} = $i + 1;
    $head_to_head_string .= make_row($item, ['ranking', 'name', 'total', 'wins', 'win_percentage'], 'head_to_head');
  }

  $head_to_head_string    .= "      </table>\n";

  # Get other player page info
  my $lifetime_wins   = 0;
  my $lifetime_losses = 0;
  my $lifetime_draws  = 0;

  my $average_score;
  my $average_score_opp;

  my $special_games =
  {
    'over' =>
    {
      '300' => 0,
      '400' => 0,
      '500' => 0,
      '600' => 0,
    },
    'high_game'    => {},
    'low_game'     => {},
    'biggest_win'  => {},
    'biggest_loss' => {},
    'high_loss'    => {},
    'low_win'      => {}
  };

  # Need:
  # tournament_result_id
  # opp_id
  # opp_name

  my $special_games_query =
  "
    SELECT p.id AS id, p.name AS name, COUNT(*) AS total, SUM(pr1.result = 1) AS wins, SUM(pr1.result = 1) / COUNT(*) AS win_percentage
    FROM $pr_name AS pr1, $pr_name AS pr2
    WHERE pr1.game_id   = pr2.game_id  AND
          pr1.player_id = $player_id AND
          pr1.id       != pr2.id
  ";

  my @special_games_results = @{$dbh->selectall_arrayref($special_games_query, {Slice => {}, "RaiseError" => 1})};

  my $special_games_initialized = 0;

  

  my $html_page = get_player_template_html_string
  (
    {
      'player_name'                    => $player_name,
      'player_country'                 => $country,
      'player_country_trigraph'        => $country,
      'photo_filename'                 => $photo_filename,
      'games_played'                   => $games_played,
      'lifetime_wins'                  => $lifetime_wins,
      'lifetime_losses'                => $lifetime_losses,
      'lifetime_draws'                 => $lifetime_draws,
      'average_score'                  => $average_score,
      'average_opp_score'              => $average_score_opp,
      'special_games'                  => $special_games,
      'tournament_history_string'      => $tournament_history_string,
      'head_to_head_string'            => $head_to_head_string,
    }
  );

  # print $html_page;
  
  open(my $fh, '>', Constants::HTML_DIR . '/' . Constants::PLAYER_HTML_DIR . '/' . $player_id . ".html");
  print $fh $html_page;
  close $fh;
}

sub get_tournament_results_html_string
{
  my $dbh  = shift;
  my $id   = shift;
  my $type = shift;

  my $player_type       = 0;
  my $tournament_type   = 1;
  my $head_to_head_type = 2;


  my $query =
  "
  SELECT
    tr.id           AS tr_id,
    tr.division_id  AS tr_division_id,
    tr.player_id    AS tr_player_id,
    tr.player_name  AS tr_player_name,
    tr.position     AS tr_position,
    tr.wins         AS tr_wins,
    tr.losses       AS tr_losses,
    tr.byes         AS tr_byes,
    tr.spread       AS tr_spread,
    tr.start_rating AS tr_start_rating,
    tr.end_rating   AS tr_end_rating,
    tr.date         AS tr_date,
    g.round         AS g_round,
    g.gcg_filename  AS g_gcg_filename,
    pr1.score       AS pr1_score,
    pr2.score       AS pr2_score,
    pr1.result      AS pr1_result,
    pr1.result      AS pr1_result,
    p.name          AS p_name, 
    p.id            AS p_id,
    p.rating        AS p_rating
  FROM
    tournament_results AS tr, games AS g, player_results AS pr1, player_results AS pr2, players AS p
  WHERE
    tr.division_id = g.division_id AND
    tr.player_id   = pr1.player_id AND
    g.id           = pr1.game_id   AND
    g.id           = pr2.game_id   AND
    pr1.id        != pr2.id        AND
    p.id           = pr2.player_id AND
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

  # Associate game results with a tournament result

  my $tournament_results_hashref = {};

  foreach my $data (@raw_tournament_data)
  {
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
      $key = 'p_id';
    }

    my $item = $tournament_results_hashref->{$data->{$key}};

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

  my @tournament_results = values %{$tournament_results_hashref};


  if ($type == $player_type)
  {
    @tournament_results = sort {$b->[0]->{'tr_date'} cmp $a->[0]->{'tr_date'}} @tournament_results;
  }
  elsif ($type == $tournament_type)
  {
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
      @sorted_games = sort {$a->{'date'} cmp $b->{'date'}} @unsorted_games;
    }

    $games = \@sorted_games;
  }

  my $tournament_title_ref = ['#', 'Location', 'Date', 'Wins', 'Losses', 'Byes', 'Spread', 'Place', 'Start Rating', 'End Rating'];
  my $tournament_keys_ref  = ['#', 'location', 'tr_date', 'tr_wins', 'tr_losses', 'tr_byes', 'tr_spread', 'tr_position', 'tr_start_rating', 'tr_end_rating'];

  my $games_title_ref = ['Round', 'Opponent', 'Result', 'Score', ''];
  my $games_keys_ref  = ['g_round', 'p_name', 'pr1_result', 'pr1_score', 'pr2_score'];

  my $head_to_head_title_ref = ['', 'Opponent', 'Rating', 'Games', 'Wins', 'Losses', 'Pct', 'Average For', 'Average Against'];
  my $head_to_head_keys_ref  = ['#', 'p_name', 'p_rating', 'hh_games', 'hh_wins', 'hh_losses', 'hh_pct', 'hh_af', 'hh_aa'];

  my $head_to_head_games_title_ref = ['Tournament', 'Date', 'Round', 'Result', 'Rating', 'Opponent Rating', 'Score', ''];
  my $head_to_head_games_keys_ref  = ['tr_id', 'tr_date', 'g_round', 'pr1_result', 'tr_start_rating', 'p_rating', 'pr1_score', 'pr2_score'];


  my $tournament_results_list_html_string = "<table>\n";

  my $title_ref = $tournament_title_ref;
  my $sub_title_ref = $games_title_ref;

  if ($type == $head_to_head_type)
  {
    $title_ref = $head_to_head_title_ref;
    $sub_title_ref = $head_to_head_games_title_ref;
  }

  my $title_length = scalar @{$title_ref};

  $tournament_results_list_html_string .=
    make_row
    (
      0,
      $title_ref,
      1
    );

  my $games_title_row = 
    make_row
    (
      0,
      $sub_title_ref,
      1
    );

  my $game_data =
  {
    'games_played'  => 0,
    'wins'          => 0,
    'losses'        => 0,
    'draws'         => 0,
    'total_score'   => 0,
    'total_against' => 0,
    'over'          =>
    {
      '300' => 0,
      '400' => 0,
      '500' => 0,
      '600' => 0
    },
    'high_game'     =>
    {
      'score' => -1000000,
    },
    'low_game'      =>
    {
      'score' => 1000000,
    },
    'biggest_win'   =>
    {
      'spread' => -1000000,
    },
    'biggest_loss'  =>
    {
      'spread' => -1000000,
    },
    'high_loss'     =>
    {
      'score' => -1000000,
    },
    'low_win'       =>
    {
      'score' =>  1000000,
    }
  };

  for (my $i = 0; $i < scalar @tournament_results; $i++)
  {
    my $games_ref = $tournament_results[$i];
    $games_ref->[0]->{'#'} = $i + 1;

    # Change later
    $games_ref->[0]->{'location'} = "Your mom's house";

    my $keys_ref = $tournament_keys_ref;
    my $id_type  = 'tournament';

    if ($type == $head_to_head_type)
    {
      $keys_ref = $head_to_head_keys_ref;
      $id_type  = 'opponent';
    }

    $tournament_results_list_html_string .=
        make_row
        (
          $games_ref->[0], 
          $keys_ref,
          0
        );

    my $html_entry_id = $games_ref->[0]->{'tr_id'};

    if ($type == $head_to_head_type)
    {
      $html_entry_id = $games_ref->[0]->{'p_id'};
    }

    $tournament_results_list_html_string .= "<tr id='entry_$html_entry_id'><td colspan='$title_length'><table>\n";

    $tournament_results_list_html_string .= $games_title_row;

    for (my $k = 0; $k < scalar @{$games_ref}; $k++)
    {
      my $item = $games_ref->[$k];

      # Special games data includes:
      # High Game
      # Low Game
      # Biggest Win
      # Biggest Loss
      # High Loss
      # Low Win

      my $high_game_item    = $game_data->{'high_game'};
      my $low_game_item     = $game_data->{'low_game'};
      my $biggest_win_item  = $game_data->{'biggest_win'};
      my $biggest_loss_item = $game_data->{'biggest_loss'};
      my $high_loss_item    = $game_data->{'high_loss'};
      my $low_win_item      = $game_data->{'low_win'};
      my $over_item         = $game_data->{'over'};

      $game_data->{'games_played'}++;

      my $res  = $item->{'pr1_result'};

      if ($res == 1)
      {
        $res = 'W';
        $game_data->{'wins'}++;
      }
      elsif ($res == -1)
      {
        $res = 'L';
        $game_data->{'losses'}++;
      }
      else
      {
        $res = 'T';
        $game_data->{'draws'}++;
      }
      
      $item->{'pr1_result'} = $res;

      my $score     = $item->{'pr1_score'};
      my $opp_score = $item->{'pr2_score'};

      $game_data->{'total_score'}   += $score;      
      $game_data->{'total_against'} += $opp_score;

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

      if ($score > $high_game_item->{'score'})
      {
        $high_game_item->{'score'} = $score;
        populate_special_game_item($high_game_item, $item);
      }
      if ($score < $low_game_item->{'score'})
      {
        $low_game_item->{'score'} = $score;
        populate_special_game_item($low_game_item, $item);
      }
      if ($score - $opp_score > $biggest_win_item->{'spread'})
      {
        $biggest_win_item->{'spread'} = $score - $opp_score;
        populate_special_game_item($biggest_win_item, $item);
      }
      if ($opp_score - $score > $biggest_loss_item->{'spread'})
      {
        $biggest_loss_item->{'spread'} = $opp_score - $score;
        populate_special_game_item($biggest_loss_item, $item);
      }
      if ($opp_score > $score && $score > $high_loss_item->{'score'})
      {
        $high_loss_item->{'score'} = $score;
        populate_special_game_item($high_loss_item, $item);
      }
      if ($score > $opp_score && $score < $low_win_item->{'score'})
      {
        $low_win_item->{'score'} = $score;
        populate_special_game_item($low_win_item, $item);
      }


      if ($type == $head_to_head_type)
      {
        $games_keys_ref = $head_to_head_games_keys_ref;
      }

      $tournament_results_list_html_string .=
        make_row
        (
          $item,
          $games_keys_ref,
          0
        );    
    }
    $tournament_results_list_html_string .= "</table></td></tr>\n";
  }

  return [$tournament_results_list_html_string, $game_data];
}

sub populate_special_game_item
{
  my $special_item = shift;
  my $item         = shift;

  $special_item->{'game_pointer'}     = $item->{'tr_id'};
  $special_item->{'player_pointer'}   = $item->{'p_id'};
  $special_item->{'player_name'}      = $item->{'p_name'};
}

sub update_full_rankings_html
{
  my $dbh = shift;

  my $full_ranking_html_string = get_rankings_html_string($dbh);

  my $full_rankings_html_page = 
 "
<html>
  <head>
  </head>
  <body>
    <div>
$full_ranking_html_string
    </div>
  </body>
</html>
"; 

  # print $html_page;
  
  open(my $fh, '>', Constants::HTML_DIR . '/' . Constants::RANKINGS_HTML_DIR . '/' . Constants::FULL_RANKINGS_NAME . ".html");
  print $fh $full_rankings_html_page;
  close $fh;
}

sub update_country_rankings_html
{
  my $dbh = shift;

  my @countries = @{$dbh->selectall_arrayref("SELECT country FROM " . Constants::PLAYERS_TABLE_NAME . " group by country", {Slice => {}, "RaiseError" => 1})};

  foreach my $item (@countries)
  {
    my $country = $item->{'country'};
    if (!$country){next;}
    my $country_ranking_html_string = get_rankings_html_string($dbh, $country);
    my $country_ranking_html_page = 
"
<html>
  <head>
  </head>
  <body>
    <div>
$country_ranking_html_string
    </div>
  </body>
</html>
"; 

  
    open(my $fh, '>', Constants::HTML_DIR . '/' . Constants::RANKINGS_HTML_DIR . "/$country.html");
    print $fh $country_ranking_html_page;
    close $fh; 
  }
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

  my $full_rankings_string = "      <table>\n";

  $full_rankings_string .= "        <tr><th>Ranking</th><th>Name</th><th>Country</th><th>Rating</th><th>Total Games</th><th>Last Played</th></tr>\n"; 


  for (my $i = 0; $i < scalar @players; $i++)
  {
    my $item = $players[$i];
    $item->{'ranking'} = $i + 1;
    $full_rankings_string .= make_row($item, ['ranking', 'name', 'country', 'rating', 'total_games', 'last_played']);
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

  my $row_string = "        <tr $id_string>";
  for (my $i = 0; $i < scalar @key_array; $i++)
  {
    my $key = $key_array[$i];
    my $val = $key;
    if (!$is_title)
    {
      $val = $item->{$key};
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

sub connect_to_database
{
  my $database_name = Constants::DATABASE_NAME;
  my $host_name     = Constants::DATABASE_HOST_NAME;
  my $user_name     = Constants::DATABASE_USER_NAME;
  my $password      = Constants::DATABASE_PASSWORD;

  my $dbh = DBI->connect("DBI:mysql:database=$database_name;host=$host_name",
                         $user_name, $password,
                         {'RaiseError' => 1}); 
  return $dbh;
}

1;











