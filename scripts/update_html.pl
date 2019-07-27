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
#
#  foreach my $tournament_id (@{$tournament_ids_to_create_ref})
#  {
#    my @division_data = ();
#    my @division_rows = @{query_table($dbh, Constants::DIVISIONS_TABLE_NAME, "tournament_id", $tournament_id)};
#
#    foreach my $division_row (@division_rows)
#    {
#      push @division_data, get_tournament_results_html_string($dbh, $division_row->{'id'}, 1);
#    }
#    my $tournament_filename = Constants::HTML_DIR . '/' . Constants::TOURNAMENT_HTML_DIR . '/' . $tournament_id . ".html"
#    write_string_to_file(get_tournament_template_html_string(\@division_data), $filename);
#  }

  push @player_ids_to_create, 93;
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
    };

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

  # update_full_rankings_html($dbh);

  # update_country_rankings_html($dbh);

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
      @sorted_games = sort {$a->{'tr_date'} cmp $b->{'tr_date'}} @unsorted_games;
    }

    $games = \@sorted_games;
  }

  my $tournament_title_ref = ['Details', '#', 'Location', 'Date', 'Wins', 'Losses', 'Byes', 'Spread', 'Place', 'Start Rating', 'End Rating'];
  my $tournament_keys_ref  = ['details', '#', 'location', 'tr_date', 'tr_wins', 'tr_losses', 'tr_byes', 'tr_spread', 'tr_position', 'tr_start_rating', 'tr_end_rating'];

  my $games_title_ref = ['Round', 'Opponent', 'Result', 'Scores', ''];
  my $games_keys_ref  = ['g_round', 'p_name', 'pr1_result', 'pr1_score', 'pr2_score'];

  my $head_to_head_title_ref = ['', 'Opponent', 'Rating', 'Games', 'Wins', 'Losses', 'Draws', 'Pct', 'Average For', 'Average Against'];
  my $head_to_head_keys_ref  = ['#', 'p_name', 'p_rating', 'hh_games', 'hh_wins', 'hh_losses', 'hh_draws', 'hh_pct', 'hh_af', 'hh_aa'];

  my $head_to_head_games_title_ref = ['Tournament', 'Date', 'Round', 'Result', 'Rating', 'Opponent Rating', 'Score', ''];
  my $head_to_head_games_keys_ref  = ['tr_id', 'tr_date', 'g_round', 'pr1_result', 'tr_start_rating', 'p_rating', 'pr1_score', 'pr2_score'];


  my $tournament_results_list_html_string = "<table class='table'>\n";

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
    my $html_entry_id = $games_ref->[0]->{'tr_id'};
    $games_ref->[0]->{'#'} = $i + 1;

    # Change later
    $games_ref->[0]->{'location'} = "Your mom's house";

    $games_ref->[0]->{'details'} = "<button type='button' id='button_$html_entry_id'  class='btn btn-info' data-toggle='collapse' data-target='#entry_" . $html_entry_id  . "'>+</button>";

    my $keys_ref = $tournament_keys_ref;
    my $id_type  = 'tournament';

    if ($type == $head_to_head_type)
    {
      $keys_ref = $head_to_head_keys_ref;
      $id_type  = 'opponent';
    }

    my $row_class = 'roweven';
    
    if ($i % 2 == 1)
    {
      $row_class = 'rowodd';
    }

    if ($type == $head_to_head_type)
    {
      $html_entry_id = $games_ref->[0]->{'p_id'};
    }
    else
    {
      $new_entry .= make_new_entry_head($games_ref, $keys_ref, $row_class, $html_entry_id, $title_length, $games_title_row);
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


      if ($type == $head_to_head_type)
      {
        $games_keys_ref = $head_to_head_games_keys_ref;
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

      $new_entry .= make_new_entry_head($games_ref, $keys_ref, $row_class, $html_entry_id, $title_length, $games_title_row);
    }

    $tournament_results_list_html_string .= $new_entry . $subentries . "</table></td></tr>\n";
  }

  $tournament_results_list_html_string .= "\n</table>\n";

  return [$tournament_results_list_html_string, $game_data];
}

sub make_new_entry_head
{
  my $games_ref = shift;
  my $keys_ref  = shift;
  my $row_class = shift;
  my $html_entry_id = shift;
  my $title_length = shift;
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

      $new_entry .= "<tr id='entry_$html_entry_id' class='collapse' ><td></td><td colspan='" . ( $title_length - 1) . "'><table class='table'>\n";

      $new_entry .= $games_title_row;

  return $new_entry;
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
    $full_rankings_string .= make_row($item, ['ranking', 'name', 'country', 'rating', 'total_games', 'last_played'], 0, 0, 0);
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











