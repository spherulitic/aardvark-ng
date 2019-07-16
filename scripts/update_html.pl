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

  update_player_and_tournament_html(\@query_result); 
}

sub update_player_and_tournament_html
{
  my $tournament_ids_to_create_ref = shift;

  my $dbh = connect_to_database();


  my $html_dir            = Constants::HTML_DIR;
  my $player_html_dir     = Constants::PLAYER_HTML_DIR;
  my $tournament_html_dir = Constants::TOURNAMENT_HTML_DIR;

  system "mkdir -p $html_dir";
  system "mkdir -p $html_dir/$player_html_dir";
  system "mkdir -p $html_dir/$tournament_html_dir";

  my @player_ids_to_create = ();

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
  system "cp -r html /srv/dev";
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

  my @result_rows = @{query_table($dbh, Constants::TOURNAMENT_RESULTS_TABLE_NAME, "player_id", $player_id)};

  @result_rows = sort { $a->{'date'} cmp $b->{'date'} } @result_rows;

  my $current_rating = $result_rows[0]->{'end_rating'};
  my $player_name    = $result_rows[0]->{'player_name'};

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

  my $html_page =
"
<html>
  <head>
  </head>
  <body>
    <div>
      <table>
        <tr><th>Name        </th><th>Rating         </th><th>Lifetime Record</th></tr>
        <tr><td>$player_name</td><td>$current_rating</td><td>$lifetime_wins - $lifetime_losses</td></tr>
      </table>
    </div>
    <div>
$tournament_history_string
    </div>
  </body>
</html>
";

  # print $html_page;
  
  open(my $fh, '>', Constants::HTML_DIR . '/' . Constants::PLAYER_HTML_DIR . '/' . $player_id . ".html");
  print $fh $html_page;
  close $fh;
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
    if (defined $val)
    {
      $row_string .= sprintf "<td>%s</td>", $val;
    }
    else
    {
      die "Value $key undefined for " . Dumper(\$item);
    }
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











