#!/usr/bin/perl

package TOU;

use strict;
use warnings;
use Getopt::Long;
use Pod::Usage qw(pod2usage);
use DBI;
use Data::Dumper;
use Term::ANSIColor;
use List::Util qw(max);

use lib './modules';
use lib './objects';

use Constants;
use Division;
use HTML;
use Result;
use Utils;

sub initialize
{
  my $this            = shift;
  my $dbh             = shift;
  my $filename        = shift;
  my $player_data     = shift;
  my $conversion_hash = shift;

  my $tou = {};

  $tou->{Constants::TOU_DBH}               = $dbh;
  $tou->{Constants::TOU_FILENAME}          = $filename;
  $tou->{Constants::TOU_REWRITE_FILENAME}  = $filename . '.rewrite';
  $tou->{Constants::TOU_PLAYER_DATA}       = $player_data;
  $tou->{Constants::TOU_CONVERSION_HASH}   = $conversion_hash;

  $tou->{Constants::TOU_PLAYER_NAMES}      = {};
  $tou->{Constants::TOU_STS_PLAYER_NAMES}  = {};
  $tou->{Constants::TOU_DIVISION_DATA}     = {};
  $tou->{Constants::TOU_ERROR_REPORT}      = '';
  $tou->{Constants::TOU_LOADED}            = 0;
  $tou->{Constants::TOU_PROCESSED}         = 0;
  $tou->{Constants::TOU_REWRITE_NEEDED}    = 0;
  $tou->{Constants::TOU_VALID}             = 1;
  $tou->{Constants::TOU_WARNING_REPORT}    = '';

  my $self = bless $tou, $this;
  return $self;
}

sub get_filename
{
  my $this = shift;
  return $this->{Constants::TOU_FILENAME}; 
}

sub set_error_report
{
  my $this = shift;
  my $error_report = shift;
  $this->{Constants::TOU_ERROR_REPORT} = $error_report;
  $this->{Constants::TOU_VALID} = 0;
}

sub new 
{
  my $tou_type              = shift;
  my $dbh                   = shift;
  my $filename              = shift;
  my $alt_names_hash        = shift;
  my $deceased_players_hash = shift;
  my $player_data           = shift;

  my $this = $tou_type->initialize($dbh, $filename, $player_data, $alt_names_hash);

  my $tou_file_extension     = Constants::TOU_FILE_EXTENSION;
  my $sts_file_extension     = Constants::STS_FILE_EXTENSION;
  my $sta_file_extension     = Constants::STA_FILE_EXTENSION;
  
  my $provisional_games_max  = Constants::PROVISIONAL_GAMES_MAX;
  
  my $tables                 = Constants::TABLES;
  my $creation_order         = Constants::TABLE_CREATION_ORDER;
  
  my $lexicons               = Constants::LEXICONS;
  my $players_tn             = Constants::PLAYERS_TABLE_NAME;  
  my $lexicons_tn            = Constants::LEXICONS_TABLE_NAME;
  my $loaded_tournaments_tn = Constants::LOADED_TOURNAMENTS_TABLE_NAME;
  
  my $tou_data_directory     = Utils::get_environment_name(Constants::TOURNAMENT_DATA_DIR);
  my $working_directory      = Utils::get_environment_name(Constants::DEFAULT_WORKING_DIR);
  my $year_regex             = Constants::DEFAULT_YEAR_REGEX;
  my $country_trigraph_regex = Constants::DEFAULT_COUNTRY_TRIGRAPH_REGEX;
  my $file_regex             = Constants::DEFAULT_FILE_REGEX;
  my $create_html            = '';
  my $help                   = '';

  my $player_names_to_ids = {};

  my @tournament_ids_to_convert_to_html = ();

  if (! -e $filename)
  {
    # Covered by TC 1
    $this->set_error_report(
      Utils::format_error([
                            ['ERROR', 'Missing .tou file'],
                            ['File',  $filename]
                          ]));
    return $this;
  }

  if (Utils::tou_is_loaded($dbh, $filename))
  {
    $this->{Constants::TOU_LOADED} = 1;
    return $this;
  }


  my $noext_filename = $filename;
  $noext_filename =~ s/\.(.*)$//;

  my $sts_file = $noext_filename . $sts_file_extension;
  my $sta_file = $noext_filename . $sta_file_extension;

  if (!( -e $sts_file || -e $sta_file))
  {
    # Covered by TC 2
    $this->set_error_report( 
      Utils::format_error([
                            ['ERROR', 'Missing .STS or .STA file'],
                            ['File',  $filename]
                          ]));
    return $this;
  }

  my $date;
  my $tournament_name;
  open(my $tou_read, "<", $filename) or die "Cannot open .tou file $filename: $!";
  my $first_line = <$tou_read>;
  close $tou_read;
  chomp $first_line;
  $first_line =~ s/\r//g;
  if ($first_line =~ /^\*.(\d\d).(\d\d).(\d\d\d\d) (.*)$/)
  {    
    $date = $3 . $2 . $1;
    $tournament_name = $4;
  }  
  else
  {
    # Covered by TC 3
    $this->set_error_report(
      Utils::format_error([
                            ['ERROR', 'Malformed .tou header'],
                            ['File',  $filename],
                          ]));
    return $this;
  }

  # This code prefers to use the .STS file

  my $sts_or_sta_file = $sts_file;
  my $is_sts = 1;
  if (!( -e $sts_file))
  {
    $sts_or_sta_file = $sta_file;
    $is_sts = 0;
  }

  my $switch_world_and_nation = 0;
  my $no_world                = 1;
  my $begin_player_captures   = 0;
  # Read the .STS file
  open(STS_OR_STA_FILE, "<", $sts_or_sta_file) or die "Cannot open .STS or .STA file $sts_or_sta_file: $!";
  while(<STS_OR_STA_FILE>)
  {
    chomp $_;

    # Remove trailing and leading whitespace from line
    $_ =~ s/^\s+|\s+$//g;

    if (!$_){next;}

    # These are common between both .STS and .STA files
    my $player_country;
    my $player_name;
    my $start_rating;
    my $end_rating;

    my $expected_wins;
    my $old_world_rank;
    my $new_world_rank = undef;
    my $old_national_rank;
    my $new_national_rank;

    # Player info must be extracted differently if the file is .STS as
    # opposed to .STA
    if ($is_sts)
    {
      my @player_items = split /,/, $_;
      $player_country    = $player_items[1];
      $player_name       = $player_items[2];
      $expected_wins     = $player_items[4];
      $start_rating      = $player_items[8];
      $end_rating        = $player_items[9];
      $old_world_rank    = $player_items[10];
      $new_world_rank    = $player_items[11];
      $old_national_rank = $player_items[12];
      $new_national_rank = $player_items[13];
    }
    else
    {
      if ($_ =~ /\+-/)
      {
        $begin_player_captures++;
      }
      if ($_ =~ /World.*Nation/i)
      {
        $switch_world_and_nation = 1;
      }
      elsif ($_ =~ /World/)
      {
        $no_world = 0;
      }
      # Remove parentheses from the line because 
      # they were causing problems
      $_  =~ s/\(|\)/ /g;
      # Agonizing pattern match for .STA file
      # which is why .STS is preferred
      #if ($_ =~ /^\|(.)(\w+)\s+([^\|]+)\|\D+?(\d+)?\D+?(\d+)?\D+?\|\D+?(\d+)?\D+?(\d+)?\D+?\|\s+(\S+)?\s+\S+\s+\|\s+(\d+)\D.* (\d+) \|/)
      if ($begin_player_captures >= 2 &&
          $_ =~ /^\|(.)(\w+)\s+([^\|]+)\|([^\|]*)\|([^\|]*)\|([^\|]*)\|([^\|]*)\|/)
      {
        my $is_new_player  = $1; # Unused for now
        $player_country    = $2;
        $player_name       = $3;

        my $national_ranks_string = $4;
        my @nranks = split /\s+/, $national_ranks_string;
        @nranks = grep {$_} @nranks;
        if (scalar @nranks == 2)
        {
          $old_national_rank = $nranks[0];
          $new_national_rank = $nranks[1];
        }
        elsif (scalar @nranks == 1)
        {
          $old_national_rank = undef;
          $new_national_rank = $nranks[0];
        }
        elsif (scalar @nranks > 2)
        {
          # Covered by TC 4
          $this->set_error_report(
            Utils::format_error([
                                  ["ERROR", "Invalid number of items in STA first rank column"], 
                                  ["File", $sts_or_sta_file], 
                                  ["Line", $_],
                                ]));
          return $this;
        }


        my $world_ranks_string = $5;
        my @wranks = split /\s+/, $world_ranks_string;
        @wranks = grep {$_} @wranks;
        if (scalar @wranks == 2)
        {
          $old_world_rank = $wranks[0];
          $new_world_rank = $wranks[1];
        }
        elsif (scalar @wranks == 1)
        {
          $old_world_rank = undef;
          $new_world_rank = $wranks[0];
        }
        elsif (scalar @wranks > 2) {
          # Covered by TC 5
          $this->set_error_report(
            Utils::format_error([
                                  ['ERROR', 'Invalid number of items in STA second rank column'], 
                                  ['File', $sts_or_sta_file], 
                                  ['Line', $_],
                                ]));
          return $this;
        }

        my $wins_string    = $6;
        my @ewins = split /\s+/, $wins_string;
        @ewins = grep {$_} @ewins;
        if (scalar @ewins == 2)
        {
          $expected_wins = $ewins[0];
        }
        elsif (scalar @ewins == 1)
        {
          $expected_wins = undef;
        }
        elsif (scalar @ewins > 2) {
          # Covered by TC 6
          $this->set_error_report(
            Utils::format_error([
                                  ['ERROR', 'Invalid number of items in STA wins column'], 
                                  ['File', $sts_or_sta_file], 
                                  ['Line', $_],
                                ]));
          return $this;
        }

        my $ratings_change_string    = $7;
        my @rchanges = split /\s+/, $ratings_change_string;
        @rchanges = grep {$_} @rchanges;
        if (scalar @rchanges == 3)
        {
          $start_rating  = $rchanges[0];
          $end_rating    = $rchanges[2];
        }
        elsif (scalar @rchanges == 2)
        {
          $start_rating  = $rchanges[0];
          $end_rating    = $rchanges[1];
        }
        elsif (scalar @rchanges == 1)
        {
          $start_rating  = undef;
          $end_rating    = $rchanges[0];
        }
        elsif (scalar @rchanges > 3)
        {
          # Covered by TC 7
          $this->set_error_report(
            Utils::format_error([
                                  ['ERROR', 'Invalid number of items in STA ratings column'], 
                                  ['File', $sts_or_sta_file], 
                                  ['Line', $_],
                                ]));
          return $this;
        }

        if ($switch_world_and_nation)
        {
          my $tmp1 = $old_national_rank;
          my $tmp2 = $new_national_rank;
          $old_national_rank = $old_world_rank;
          $new_national_rank = $new_world_rank;
          $old_world_rank    = $tmp1;
          $new_world_rank    = $tmp2;
        }
        elsif ($no_world)
        {
          $old_world_rank = undef;
          $new_world_rank = undef;
        }
      }
      else
      {
        next;
      }
    }

    # Sometimes byes are represented by players named something like
    # Bye A. If this is the case, we do not need to record the info
    # for this 'player'
    if (Utils::player_name_is_bye($player_name))
    {
      next;
    }

    $expected_wins     = Utils::negative_one_if_false($expected_wins);
    $start_rating      = Utils::negative_one_if_false($start_rating);
    $old_world_rank    = Utils::negative_one_if_false($old_world_rank);
    $new_world_rank    = Utils::negative_one_if_false($new_world_rank);
    $old_national_rank = Utils::negative_one_if_false($old_national_rank);
    $new_national_rank = Utils::negative_one_if_false($new_national_rank);

    $player_country    =~ s/^\s+|\s+$//g;
    $player_name       =~ s/^\s+|\s+$//g;
    $new_world_rank    =~ s/^\s+|\s+$//g;
    $old_world_rank    =~ s/^\s+|\s+$//g;
    $old_national_rank =~ s/^\s+|\s+$//g;
    $new_national_rank =~ s/^\s+|\s+$//g;
    $expected_wins     =~ s/^\s+|\s+$//g;
    $start_rating      =~ s/^\s+|\s+$//g;
    $end_rating        =~ s/^\s+|\s+$//g;    

    my @required_captures =
    grep {!$_}
    (
      $player_country,
      $player_name,
      $start_rating,
      $end_rating
    );
 
    if (@required_captures)
    {
      # Covered by TC 8
      $this->set_error_report(
        Utils::format_error([
                              ['ERROR', 'Required values are uncaptured'], 
                              ['File', $sts_or_sta_file], 
                              ['Name', $player_name]
                            ]));
      return $this;
    }

    # Some country trigraphs in the old aardvark are incorrect
    # and need to be converted to valid ISO 3166 trigraphs
    $player_country = Utils::convert_trigraph($player_country);      
    # Convert possible alt name to correct name

    $player_name           = Utils::convert_name($player_name, $alt_names_hash);
    my $pretty_player_name = Utils::make_pretty($player_name);
    $player_name           = Utils::sanitize($player_name);

    $this->{Constants::TOU_STS_PLAYER_NAMES}->{$player_name} = 1;

    # Search for this player in the players table
    # If this player already exists in the database, we will need their
    # id for the table to add them properly

    my $player_query = "SELECT id, country, last_played FROM $players_tn WHERE BINARY name=\"$pretty_player_name\"";

    my @player_query_result = $dbh->selectrow_array($player_query, {"RaiseError" => 1});

    my $player_id;

    if (!@player_query_result) # Player does not exist
    {
      $player_id = Utils::insert_hash_into_table
      (
        $dbh,
        $players_tn,
        {
          name        => $pretty_player_name,
          country     => $player_country,
          photo       => Utils::get_player_photo($player_name),
          suspended   => 0,  # Updated later
          deceased    => $deceased_players_hash->{$player_name} ? 1 : 0,
          provisional => -1, # Updated laster
          total_games => 0,   # Updated later
          last_played => $date, 
          rating      => $end_rating
        }
      );
    }
    else
    {
      # If the player already exists, the last_played and country fields
      # may need to be updated

      $player_id = shift @player_query_result;
      my $existing_country = shift @player_query_result;
      my $player_last_played = shift @player_query_result;

      $player_last_played =~ s/\D//g;


      my $newer_tourney_cond = $player_last_played < $date;

      my $no_country_cond = !$existing_country &&
                             $player_country;

      my $changed_to_newer_country_cond = $existing_country &&
                                          $player_country &&
                                          $existing_country ne $player_country &&
                                          $player_last_played < $date;

      my $changed_country_cond = $existing_country &&
                                 $player_country &&
                                 $existing_country ne $player_country;

      if ($newer_tourney_cond)
      {
        Utils::update_record_by_id($dbh, $players_tn, $player_id, {'last_played' => $date, 'rating' => $end_rating}); 
      }

      if ($no_country_cond || $changed_to_newer_country_cond)
      {
        Utils::update_record_by_id($dbh, $players_tn, $player_id, {'country' => $player_country}); 
      }
    } 
    $player_data->{$player_name} = [$pretty_player_name, $player_id];
  }

  $this->process();
  return $this;
}

sub get_unblessed_ref
{
  my $obj = shift;

  my $unblessed;

  if (ref($obj) eq 'ARRAY')
  {
    $unblessed = []; 
    for (my $i = 0; $i < scalar @{$obj}; $I++)
    {   
      $unblessed->[$i] = get_unblessed_ref($obj->[$i]);
    }   
  }
  elsif (ref($obj))
  {
    $unblessed = {}; 
    foreach my $key (keys %{$obj})
    {   
      if (!Constants::UNBLESSED_IGNORE_KEYS->{$key})
      {   
        $unblessed->{$key} = get_unblessed_ref($obj->{$key});
      }   
    }   
  }
  else
  {
    $unblessed = $obj;
  }
  return $unblessed;
}

sub to_string
{
  my $this = shift;

  my $event                           = $this->{Constants::TOU_EVENT};
  my $tournament                      = $this->{Constants::TOU_TOURNAMENT};
  my $divisions                       = $this->{Constants::TOU_DIVISION_DATA};

  my $tournament_name = $tournament->{name};
  my $tournament_date = $tournament->{date};

  $tournament_date =~ /(\d\d\d\d)-(\d\d)-(\d\d)/;

  my $tou_date_format = "$3.$2.$1";

  my $tou_string = "*M$tou_date_format $tournament_name\n";

  my @division_keys =
    sort {
           $divisions->{$a}->{Constants::DIVISION_NUMBER} <=> 
           $divisions->{$b}->{Constants::DIVISION_NUMBER}
         } keys %{$divisions};

  for (my $i = 0; $i < scalar @division_keys; $i++)
  {
    $tou_string .= $divisions->{$division_keys[$i]}->to_string();
  }

  $tou_string .= '*** END OF FILE ***';
  return $tou_string;
}

sub is_valid
{
  my $this = shift;
  return $this->{Constants::TOU_VALID};
}

sub load
{
  my $this        = shift;
  my $player_data = shift;

  if (!$this->is_valid())
  {
    return 1;
  }

  my $dbh         = $this->{Constants::TOU_DBH};

  my $filename                        = $this->{Constants::TOU_FILENAME};
  my $event                           = $this->{Constants::TOU_EVENT};
  my $tournament                      = $this->{Constants::TOU_TOURNAMENT};
  my $divisions                       = $this->{Constants::TOU_DIVISION_DATA};

  my $players_tn            = Constants::PLAYERS_TABLE_NAME;
  my $player_alt_names_tn   = Constants::PLAYER_ALT_NAMES_TABLE_NAME;
  my $tournaments_tn        = Constants::TOURNAMENTS_TABLE_NAME;
  my $events_tn             = Constants::EVENTS_TABLE_NAME;
  my $divisions_tn          = Constants::DIVISIONS_TABLE_NAME;
  my $games_tn              = Constants::GAMES_TABLE_NAME;
  my $tournament_results_tn = Constants::TOURNAMENT_RESULTS_TABLE_NAME;
  my $player_results_tn     = Constants::PLAYER_RESULTS_TABLE_NAME;

  # Add to database top down so we can link up the foreign keys
  my $event_id      = Utils::insert_hash_into_table($dbh, $events_tn, $event);

  $tournament->{event_id} = $event_id;

  my $tournament_name = $tournament->{name};
  my $tournament_id = Utils::insert_hash_into_table($dbh, $tournaments_tn, $tournament);

  my @division_keys =
    sort {
           $divisions->{$a}->{Constants::DIVISION_NUMBER} <=> 
           $divisions->{$b}->{Constants::DIVISION_NUMBER}
         } keys %{$divisions};

  for (my $i = 0; $i < scalar @division_keys; $i++)
  {
    my $key = $division_keys[$i];
    my $division      = $divisions->{$key};
    my $division_name = $division->{Constants::DIVISION_NAME};

    my $division_id   = Utils::insert_hash_into_table
    (
      $dbh,
      $divisions_tn,
      {
        tournament_id => $tournament_id,
        name          => $division_name,
        length        => $divisions->{$key}->{Constants::DIVISION_NUMBER_OF_ROUNDS},
        number        => $divisions->{$key}->{Constants::DIVISION_NUMBER}
      }
    );

    my $tournament_results = $division->{Constants::DIVISION_TOURNAMENT_RESULTS};

    foreach my $tr (@{$tournament_results})
    {
      my $total_games = $tr->{wins} + $tr->{losses};
 
      Utils::add_games_to_existing_player($dbh, $tr->{player_id}, $total_games);
      $tr->{division_id} = $division_id;
      Utils::insert_hash_into_table($dbh, $tournament_results_tn, $tr);
    }

    my $gprs = $division->{Constants::DIVISION_GAME_AND_PLAYER_RESULTS};

    foreach my $key (keys %{$gprs})
    {
      my $gpr     = $gprs->{$key};
      my $game    = $gpr->{game};
      my @results = @{$gpr->{results}};

      $game->{division_id} = $division_id;

      my $game_id = Utils::insert_hash_into_table($dbh, $games_tn, $game);
  
      foreach my $result (@results)
      {
        $result->{game_id} = $game_id;
        Utils::insert_hash_into_table($dbh, $player_results_tn, $result);
      }
    }
  }

  my $loaded_tournaments_table_name = Constants::LOADED_TOURNAMENTS_TABLE_NAME;
  $tournament_name =~ s/"//g;

  my $insert_processed_tou =
  "
    INSERT INTO $loaded_tournaments_table_name
    (name, filename)
    VALUES (\"$tournament_name\", \"$filename\")
  ";

  $dbh->do($insert_processed_tou, {"RaiseError" => 1});
  $this->{Constants::TOU_LOADED} = 1; 
  return 0;
}

sub process_division
{
  my $this     = shift;
  my $division = shift;

  my $verification_report = $division->{Constants::DIVISION_VERIFICATION_REPORT};

  if (!$division->is_valid())
  {
    $this->{Constants::TOU_ERROR_REPORT} = $verification_report;
    $this->{Constants::TOU_VALID} = 0;
    return 1;
  }

  $this->{Constants::TOU_WARNING_REPORT} = $verification_report;

  my $number_of_rounds  = $division->{Constants::DIVISION_NUMBER_OF_ROUNDS};
  my @players           = @{$division->{Constants::DIVISION_PLAYERS}};
  my $number_of_rows    = scalar @players;

  my @tournament_results      = ();
  my $game_and_player_results = {};
  my $player_data_hash        = $this->{Constants::TOU_PLAYER_DATA};

  my $spread   = 0;
  my $wins     = 0;
  my $losses   = 0;
  my $byes     = 0;
  my $bye_wins = 0;

  for (my $row = 0; $row < $number_of_rows; $row++)
  {
    my $player_data = $player_data_hash->{Utils::sanitize($players[$row])};
    my $player_name = $players[$row];
    my $sanitized_player_name = Utils::sanitize($player_name); 
    my $player_id   = $player_data->[1];

    if (!$player_name)
    {
      die Dumper(\@players) . Dumper($player_data) . $players[$row];
    }

    $this->{Constants::TOU_PLAYER_NAMES}->{$sanitized_player_name} = 1;

    my $tournament_result =
    {
      player_id       => $player_id,
      player_name     => $player_name,
      position        => 0,
      wins            => 0,
      losses          => 0,
      byes            => 0,
      bye_wins        => 0,
      spread          => 0,
      date            => $this->{Constants::TOU_TOURNAMENT}->{start_date},
      tournament_name => $this->{Constants::TOU_TOURNAMENT}->{name}
    };

    for (my $round = 0; $round < $number_of_rounds; $round++)
    { 
      my $player_result   = $division->get_matrix_index($row, $round);
      my $opponent_number = $player_result->{Constants::RESULT_OPPONENT_NUMBER};
      $tournament_result->{wins}     += $player_result->{Constants::RESULT_WINS};
      $tournament_result->{losses}   += $player_result->{Constants::RESULT_LOSSES};
      $tournament_result->{byes}     += $player_result->{Constants::RESULT_BYES};
      $tournament_result->{bye_wins} += $player_result->{Constants::RESULT_BYE_WINS};
      $tournament_result->{spread}   += $player_result->{Constants::RESULT_SPREAD};
      $player_result->add_to_gpr($game_and_player_results, $player_id);
    }
    push @tournament_results, $tournament_result;
  }

  @tournament_results = Utils::rank_tournament_results(\@tournament_results);

  $division->{Constants::DIVISION_TOURNAMENT_RESULTS}      = \@tournament_results;
  $division->{Constants::DIVISION_GAME_AND_PLAYER_RESULTS} = $game_and_player_results;
  $this->{Constants::TOU_DIVISION_DATA}->{$division->{Constants::DIVISION_NAME}} = $division;
  return 0;
}

sub compare_sts_and_tou_names
{
  my $this                          = shift;

  my $tou_names = $this->{Constants::TOU_PLAYER_NAMES};
  my $sts_names = $this->{Constants::TOU_STS_PLAYER_NAMES};

  foreach my $key (keys %{$sts_names})
  {
    $tou_names->{$key} = 0;
  }

  my $missing_from_sts = join ",", grep {$tou_names->{$_}} keys $tou_names;

  if ($missing_from_sts)
  {
    # Covered by TC 9
    $this->set_error_report(
      Utils::format_error([
                            ['ERROR', 'Names missing in the STS/STA file'],
                            ['File', $this->{Constants::TOU_FILENAME}],
                            ['Missing from STS', $missing_from_sts]
                          ]));
  }
}

sub new_division
{
  my $this                    = shift;
  my $filename                = shift;
  my $current_division_name   = shift;
  my $current_division_number = shift;
  my $players                 = shift;
  my $game_data               = shift;

  my $division =
          Division->new(
                         $filename,
                         $current_division_name,
                         $current_division_number,
                         $players,
                         $game_data
                       );

  $division->process();
  return $this->process_division($division);
}

sub process
{
  my $this                          = shift;

  my $filename                      = $this->{Constants::TOU_FILENAME};
  my @players                       = ();
  my @game_data                     = ();
  my $current_division_number       = 1;
  my $current_division_name         = '';

  my $at_end    = 0;
  my $at_header = 1;

  open(my $fh, "<", $filename)
    or die "Cannot open .tou file $filename: $!";

  while(<$fh>)
  {
    $at_end = $_ =~ /END OF FILE/;
    if ($at_header)
    {
      if (/^\*.(\d\d).(\d\d).(\d\d\d\d) (.*)$/)
      {
        my $date = $3 . $2 . $1;
        my $tournament_name = $4;
    
        # The commented entries are fields that we want to fill in eventually
      
        my $event = 
        {
          "start_date" => $date,
          "end_date"   => $date,
          # "link"       => "link to event",
          # "sponsor"    => "sponsor of event",
          # "country"    => "AAA",
          # "location"   => "location of event",
        };
        my $tournament = 
        {
          "start_date" => $date, # This is changed later
          "end_date"   => $date, # This is changed later
          "name"       => $tournament_name, 
          "country"    => Utils::convert_trigraph(Utils::get_country_from_filename($filename)), 
          # "td"         => "director of tournament",
        };
        $this->{Constants::TOU_EVENT}      = $event;
        $this->{Constants::TOU_TOURNAMENT} = $tournament;
      }
      $at_header = 0;
    }

    if (($_ =~ /^\*(.*)/ || $at_end) && !$at_header)
    {
      # If this is the end of the division, verify the division
      if (@players)
      {
        if (
             $this->new_division
                         (
                           $filename,
                           $current_division_name,
                           $current_division_number++,
                           \@players,
                           \@game_data
                         )
           )

        {
          return 1;
        }
      }
      # Prepare loop for a new division
      if (!$at_end)
      {
        @players       = ();
        @game_data     = ();
        $current_division_name = $1;
        $current_division_name =~ s/^\s+|\s+$//g;
      }
    }
    elsif ($_ =~ /\w\s+(\d+\s+\+?\d+(\s+|$))+/)
    {
      if (!$current_division_number || !$current_division_name)
      {    
        # Covered by TC 10
        $this->set_error_report(
          Utils::format_error([
                                ['ERROR', 'Missing division name'],
                                ['File', $filename],
                              ]));
        return 1;
      }   

      # If a winning negative score is listed, correct it by adding 2000
      # to ensure compliance with the .tou format
      if ($_ =~ /\s2\s?(\-\d+)/)
      {    
        $this->{Constants::TOU_WARNING_REPORT} .= Utils::format_error([
                              ['WARNING', 'Converting negative winning score'],
                              ['File', $filename],
                              ['Line', $_."\n"],
                              ['Rewritten to', $this->{Constants::TOU_REWRITE_FILENAME}]
                            ]);
        my $neg_score = $1 + 2000;
        $_ =~ s/2\s?\-\d+/$neg_score/g;
        $this->{Constants::TOU_REWRITE_NEEDED} = 1;
      }

      my @player_game_data = split/\s+/, $_;
      my $games_played = () = $_ =~ /(\-?\d+\s+\+?\d+(?:\s+|$))/g;
      my @games = ();

      for(my $i = 0; $i < $games_played; $i++)
      {
        my $opp_number  = pop @player_game_data;
        my $player_is_first = 0;
        if (substr($opp_number, 0, 1) eq '+')
        {
          $player_is_first = 1;
        }
        $opp_number =~ s/\D//g;
        my $score       = pop @player_game_data;

        if ($opp_number =~ /\D/ || $score !~ /^-?\d+$/)
        {
          # Covered by TC 11
          $this->set_error_report(
            Utils::format_error([
                                  ['ERROR', "Malformed opponent number or player score"],
                                  ['File', $filename],
                                  ['Opponent number', $opp_number],
                                  ['Player score', $score],
                                  ['Line', $_]
                                ]));
          return 1;
        }

        # Convert the 1-indexed opp number in the TOU to the
        # 0-indexed opp number in the Division and Result objects
        unshift @games, Result->new($score, $opp_number - 1, $player_is_first);
      }

      my $player_name = join " ", @player_game_data;
      $player_name    =~ s/^\s+|\s+$//g;
      $player_name    = Utils::convert_name($player_name, $this->{Constants::TOU_CONVERSION_HASH});

      push @players, $player_name;
      push @game_data, \@games;
    }
  }

  $this->compare_sts_and_tou_names();

  $this->{Constants::TOU_PROCESSED} = 1;
}

1;
