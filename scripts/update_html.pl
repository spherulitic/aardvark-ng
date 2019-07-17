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
    my $tournament_html_struct = {};
    my @division_rows = @{query_table($dbh, Constants::DIVISIONS_TABLE_NAME, "tournament_id", $tournament_id)};

    foreach my $division_row (@division_rows)
    {
      my @results = @{query_table($dbh, Constants::TOURNAMENT_RESULTS_TABLE_NAME, "division_id", $division_row->{'id'})};
      push @player_ids_to_create, (map { $_->{'player_id'} } @results);

      @results = sort
                 {
                   $b->{'wins'} <=> $a->{'wins'} ||
                   $b->{'byes'} <=> $a->{'byes'} ||
                   $b->{'spread'} <=> $a->{'spread'}
                 }
                 @results;

      $tournament_html_struct->{$division_row->{'name'}} = \@results;
    }
    create_tournament_html_from_struct($tournament_id, $tournament_html_struct);
  }


  # Update the player html pages that have been changed
  foreach my $id (@player_ids_to_create)
  {
    create_player_html_from_database($dbh, $id);
  }

  # Update the full ranking list

  update_full_rankings_html($dbh);

  update_country_rankings_html($dbh);

  system "cp -r $html_dir /srv/dev";
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

  if (!$country)
  {
    $country = "";
  }

  my $current_rating = $player[0]->{'rating'};

  my @result_rows = @{query_table($dbh, Constants::TOURNAMENT_RESULTS_TABLE_NAME, "player_id", $player_id)};

  @result_rows = sort { $b->{'date'} cmp $a->{'date'} } @result_rows;

  my $tournament_history_string = "      <table>\n";

  $tournament_history_string .= "        <tr><th>Date</th><th>Place</th><th>Name</th><th>Wins</th><th>Losses</th><th>Byes</th><th>Spread</th><th>Old Rating</th><th>New Rating</th></tr>\n"; 

  my $lifetime_wins   = 0;
  my $lifetime_losses = 0;

  for (my $i = 0; $i < scalar @result_rows; $i++)
  {
    my $item = $result_rows[$i];
    if (!(keys %{$item}))
    {
      die "Empty players hash in id $player_id :\n" . Dumper(\@result_rows);
    }
    $tournament_history_string .= make_row($item, ['date', 'position', 'player_name', 'wins', 'losses', 'byes', 'spread', 'start_rating', 'end_rating']);


    $lifetime_wins   += $item->{'wins'};
    $lifetime_losses += $item->{'losses'};
  }

  $tournament_history_string    .= "      </table>\n";

  # Get Head to Head record

  my $pr_name = Constants::PLAYER_RESULTS_TABLE_NAME;
  my $p_name  = Constants::PLAYERS_TABLE_NAME;

  my $head_to_head_query =
  "
    SELECT p.name AS name, COUNT(*) AS total, SUM(pr1.result = 1) AS wins, SUM(pr1.result = 1) / COUNT(*) AS win_percentage
    FROM $pr_name AS pr1, $pr_name AS pr2, $p_name AS p
    WHERE pr1.game_id = pr2.game_id  AND
          pr1.player_id = $player_id AND
          pr2.player_id = p.id       AND
          pr1.id != pr2.id
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
    $head_to_head_string .= make_row($item, ['ranking', 'name', 'total', 'wins', 'win_percentage']);
  }

  $head_to_head_string    .= "      </table>\n";

  my $html_page =
"
<html>
  <head>
  </head>
  <body>
    <div>
      <table>
        <tr><th>Name        </th><th>Country</th> <th>Rating         </th><th>Lifetime Record</th></tr>
        <tr><td>$player_name</td><td>$country</td><td>$current_rating</td><td>$lifetime_wins - $lifetime_losses</td></tr>
      </table>
    </div>
    <div>
$tournament_history_string
$head_to_head_string
    </div>
  </body>
</html>
";

  # print $html_page;
  
  open(my $fh, '>', Constants::HTML_DIR . '/' . Constants::PLAYER_HTML_DIR . '/' . $player_id . ".html");
  print $fh $html_page;
  close $fh;
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
  my $item = shift;
  my $keys = shift;

  my @key_array = @{$keys};
  my $row_string = "        <tr>";
  for (my $i = 0; $i < scalar @key_array; $i++)
  {
    my $key = $key_array[$i];
    my $val = $item->{$key};
    if (!(defined $val))
    {
      $val = "";
    }
    $row_string .= sprintf "<td>%s</td>", $val;
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











