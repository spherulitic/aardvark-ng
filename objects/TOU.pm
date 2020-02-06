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
use Constants;
use HTML;
use Utils;

sub initialize
{
  my $this = shift;

  my $tou = {};

  $tou->{Constants::TOU_ERROR_REPORT}      = '';
  $tou->{Constants::TOU_WARNING_REPORT}    = '';
  $tou->{Constants::TOU_LOADED}            = 0;
  $tou->{Constants::TOU_FILENAME}          = '';
  $tou->{Constants::TOU_VALID}             = 1;
  $tou->{Constants::TOU_NEWED}             = 0;
  $tou->{Constants::TOU_TOURNAMENT_LENGTH} = 0;
  $tou->{Constants::TOU_REWRITE_NEEDED}    = 0;
  $tou->{Constants::TOU_DIVISION_DATA}     = {};

  my $self = bless $tou, $this;
  return $self;
}

sub new 
{
  my $this                  = shift;
  my $dbh                   = shift;
  my $filename              = shift;
  my $alt_names_hash        = shift;
  my $deceased_players_hash = shift;

  my $tou = $this->initialize();

  my $tou_file_extension = Constants::TOU_FILE_EXTENSION;
  my $sts_file_extension = Constants::STS_FILE_EXTENSION;
  my $sta_file_extension = Constants::STA_FILE_EXTENSION;
  
  my $provisional_games_max = Constants::PROVISIONAL_GAMES_MAX;
  
  my $tables = Constants::TABLES;
  
  my $creation_order = Constants::TABLE_CREATION_ORDER;
  
  my $lexicons = Constants::LEXICONS;
  my $players_tn            = Constants::PLAYERS_TABLE_NAME;  
  my $lexicons_tn           = Constants::LEXICONS_TABLE_NAME;
  
  my $tou_data_directory     = Utils::get_environment_name(Constants::TOURNAMENT_DATA_DIR);
  my $working_directory      = Utils::get_environment_name(Constants::DEFAULT_WORKING_DIR);
  my $year_regex             = Constants::DEFAULT_YEAR_REGEX;
  my $country_trigraph_regex = Constants::DEFAULT_COUNTRY_TRIGRAPH_REGEX;
  my $file_regex             = Constants::DEFAULT_FILE_REGEX;
  my $create_html            = '';
  my $help                   = '';

  my $player_names_to_ids = {};

  my @tournament_ids_to_convert_to_html = ();

  if (!( -e $filename))
  {
    $tou->{Constants::TOU_ERROR_REPORT} = Utils::format_error([
                          ["ERROR: ", "Missing .tou file"],
                          ["File:  ", $filename]
                        ]);
    return $tou;
  }

  $tou->{Constants::TOU_FILENAME} = $filename;

  my $tou_file = $filename;
  $filename =~ s/\.(.*)$//;

  my @filename_items = split /\//, $filename;

  my $tournament_country = $filename_items[5];

  my $sts_file = $filename . $sts_file_extension;
  my $sta_file = $filename . $sta_file_extension;

  my $loaded_tournaments_tn = Constants::LOADED_TOURNAMENTS_TABLE_NAME;
  my $tou_query = "SELECT * FROM $loaded_tournaments_tn WHERE filename=\"$tou_file\"";

  my @tou_query_result = $dbh->selectrow_array($tou_query, {"RaiseError" => 1});

  if (@tou_query_result)
  {
    $tou->{Constants::TOU_LOADED} = 1;
    return $tou;
  }

  # First validate and maybe correct the .tou file
  $tou->verify();

  foreach my $div_key (keys %{$tou->{Constants::TOU_DIVISION_DATA}})
  {
    print $tou->{Constants::TOU_DIVISION_DATA}->{$div_key}->{Constants::TOU_DIVISION_VERIFICATION_REPORT};
  }

  if (!$tou->{Constants::TOU_VALID})
  {
    return $tou;
  }

  if (!( -e $sts_file || -e $sta_file))
  {
    $tou->{Constants::TOU_ERROR_REPORT} = 
      Utils::format_error([
                            ["ERROR: ", "Missing .STS or .STA file"],
                            ["File:  ", $filename]
                          ]);
    return $tou;
  }

  # This code prefers to use the .STS file

  my $sts_or_sta_file = $sts_file;
  my $is_sts = 1;
  if (!( -e $sts_file))
  {
    $sts_or_sta_file = $sta_file;
    $is_sts = 0;
  }

  # Read the .tou file for the date only
  my $date = "";
  my $tournament_name = "";
  open(my $tou_read, "<", $tou_file) or die "Cannot open .tou file $tou_file: $!";
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
    $tou->{Constants::TOU_ERROR_REPORT} = Utils::format_error([
                          ["ERROR:", "malformed .tou header"],
                          ["File: ", $tou_file],
                        ]);
    return $tou;
  }

  # These hashes of .STS/.STA names and .tou names will be used to check
  # for discrepancies between the two

  my %st_names  = ();
  my %tou_names = ();

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
    "country"    => Utils::convert_trigraph($tournament_country), 
    # "td"         => "director of tournament",
  };
  my @divisions = ();
  my $tournament_results = {};
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
        elsif (scalar @nranks > 2) {
          $tou->{Constants::TOU_ERROR_REPORT} = Utils::format_error([
                                ["ERROR: ", "invalid number of items in STA first rank column"], 
                                ["File:  ", $sts_or_sta_file], 
                                ["Line:  ", $_],
                              ]);
          return $tou;
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
          $tou->{Constants::TOU_ERROR_REPORT} = Utils::format_error([
                                ["ERROR: ", "invalid number of items in STA second rank column"], 
                                ["File:  ", $sts_or_sta_file], 
                                ["Line:  ", $_],
                              ]);
          return $tou;
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
          $tou->{Constants::TOU_ERROR_REPORT} = Utils::format_error([
                                ["ERROR: ", "invalid number of items in STA wins column"], 
                                ["File:  ", $sts_or_sta_file], 
                                ["Line:  ", $_],
                              ]);
          return $tou;
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
          $tou->{Constants::TOU_ERROR_REPORT} = Utils::format_error([
                                ["ERROR: ", "invalid number of items in STA ratings column"], 
                                ["File:  ", $sts_or_sta_file], 
                                ["Line:  ", $_],
                              ]);
          return $tou;
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
    (
      $player_country,
      $player_name,
      $start_rating,
      $end_rating
    );
    if (grep {!defined($_)} @required_captures)
    {
      $tou->{Constants::TOU_ERROR_REPORT} = Utils::format_error([
                            ["ERROR: ", "required values are uncaptured"], 
                            ["File:  ", $sts_or_sta_file], 
                            ["Name:  ", $player_name],
                            ["Array: ", Dumper(\@required_captures)]
                          ]);
      return $tou;
    }

    # Some country trigraphs in the old aardvark are incorrect
    # and need to be converted to valid ISO 3166 trigraphs
    $player_country = Utils::convert_trigraph($player_country);      
    # Convert possible alt name to correct name

    $player_name = Utils::convert_name($player_name, $alt_names_hash);
    my $pretty_player_name = Utils::make_pretty($player_name);
    $player_name = Utils::sanitize($player_name);
    # Error with name appears twice, can happen if a player switches divisions midtournament
    #if ($st_names{$player_name})
    #{
    #  format_error([
    #                 ["ERROR:  ", "player name appears more than once"],
    #                 ["File:   ", $sts_or_sta_file],
    #                 ["Player: ", $player_name]
    #               ]);
    #  return $tou;
    #}
 
    $st_names{$player_name} = 1;

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
          "name"        => $pretty_player_name,
          "country"     => $player_country,
          "photo"       => Utils::get_player_photo($player_name),
          "suspended"   => 0,  # Updated later
          "deceased"    => !!$deceased_players_hash->{$player_name},
          "provisional" => -1, # Updated laster
          "total_games" => 0,   # Updated later
          "last_played" => $date, 
          "rating"      => $end_rating
        }
      );
      $player_names_to_ids->{$player_name} = $player_id;
    }
    else
    {
      # If the player already exists, the last_played and country fields
      # may need to be updated

      my $player_id = shift @player_query_result;
      my $existing_country = shift @player_query_result;
      my $player_last_played = shift @player_query_result;

      $player_last_played =~ s/\D//g;

      $player_names_to_ids->{$player_name} = $player_id;

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
      #Warning if someone switches countries
      #if ($changed_country_cond)
      #{
      #  format_error([
      #                 ["WARNING:         ", "player switched countries"],
      #                 ["File:            ", $filename],
      #                 ["Player:          ", $player_name],
      #                 ["Current country: ", $existing_country],
      #                 ["New country:     ", $player_country],
      #               ]);
      #}
      } 

      # Keep an mapping of the names to ids in memory
      # so we don't have to query the database more than necessary 
      $player_id = $player_names_to_ids->{$player_name};

      if (!$player_id)
      {
        $tou->{Constants::TOU_ERROR_REPORT} = Utils::format_error([
                              ["ERROR: ", "player name does not have id"], 
                              ["File:  ", $sts_or_sta_file], 
                              ["Name:  ", $player_name] 
                            ]);
        return $tou;
      }

      # Still need spread and position
      $tournament_results->{$player_name} = 
      {
        "player_id"         => $player_id,
        "player_name"       => $pretty_player_name,
        "division_id"       => -1, # This will be replaced with the actual id later
        # Calculations done later because byes are annoying
        "wins"              => 0,
        "losses"            => 0,
        "byes"              => 0,
        # "prize_money"    => 0,
        # "prize_currency" => "AAA",
        # "prize_ech_rate" => 1,
        "start_rating"      => $start_rating,
        "end_rating"        => $end_rating,
        "date"              => $date,
        "tournament_name"   => $tournament_name,

        "expected_wins"     => $expected_wins,
        "old_world_rank"    => $old_world_rank,
        "new_world_rank"    => $new_world_rank,
        "old_national_rank" => $old_national_rank,
        "new_national_rank" => $new_national_rank,
      };
    }

    # Now parse the .tou file for game data
    my $current_division_number = 0;
    my $current_division_name   = "";
    my $current_player_number   = 1;

    my $tou_game_data_hashref = {};

    my %tou_div_names = ();
    my $player_spreads = {};
    my $is_header = 1;
    # Read the .tou file
    open(TOU_FILE, "<", $tou_file) or die "Cannot open .tou file $tou_file: $!";
    while(<TOU_FILE>)
    {
      chomp $_;
      if ($_ =~ /^\*(.*)/ && $_ !~ /END OF FILE/ && !$is_header)
      {
        # Prepare the loop for a new division
        my $div_name = $1;
        $div_name =~ s/^\s+|\s+$//g;
        $current_division_number++;
        $current_division_name = $div_name;
        $current_player_number = 1;
        push @divisions, {"number" => $current_division_number, "name" => $current_division_name, "length" => -1};
      }
      elsif ($_ =~ /\w\s+(\d+\s+\+?\d+(\s+|$))+/)
      {
        if (!$current_division_number || !$current_division_name)
        {
          $tou->{Constants::TOU_ERROR_REPORT} = Utils::format_error([
                                ["ERROR:", "Missing division name"],
                                ["File: ", $tou_file],
                              ]);
          return $tou;
        }

        my @player_game_data = split/\s+/, $_;
    
        my @games = ();
        
        # The games in the .tou are represented by score/opp_number pairs
        # This detects how many of those pairs there are
        my $games_played = () = $_ =~ /(\d+\s+\+?\d+(?:\s+|$))/g;

        my $current_div_hash = $divisions[-1];

        if ($current_div_hash->{'length'} == -1)
        {
          $current_div_hash->{'length'} = $games_played;
        }
        elsif ($current_div_hash->{'length'} != $games_played)
        {
             $tou->{Constants::TOU_ERROR_REPORT} = Utils::format_error([
                                   ["ERROR:    ", "inconsistent number of tournament games"],
                                   ["File:     ", $tou_file],
                                   ["Division: ", $current_division_name],
                                   ["Line:     ", $_]
                                 ]);
            return $tou;         
        }

        for(my $i = 0; $i < $games_played; $i++)
        {
          my $opp_number  = pop @player_game_data;
          $opp_number =~ s/\D//g;
          my $score       = pop @player_game_data;

          if ($opp_number =~ /\D/ || $score !~ /^-?\d+$/)
          {
            $tou->{Constants::TOU_ERROR_REPORT} = Utils::format_error([
                                  ["ERROR:        ", "Malformed opponent number or player score"],
                                  ["File:         ", $tou_file],
                                  ["Opp number:   ", $opp_number],
                                  ["Player score: ", $score],
                                  ["Games played: ", $games_played],
                                  ["Line:         ", $_]
                                ]);
            return $tou;
          }
          if ($opp_number == $current_player_number || $score == 1350)
          {
            $score = 50;
          }
          # Allow down to -100 in winning score
          elsif ($score > 1900)
          {
            $score -= 2000;
          }
          elsif ($score > 1000)
          {
            $score -= 1000;
          }
          unshift @games, [$score, $opp_number];
        }

        my $player_name = join " ", @player_game_data;
        $player_name =~ s/^\s+|\s+$//g;

        # Convert possible alt name to real name

        $player_name = Utils::convert_name($player_name, $alt_names_hash);
        my $pretty_player_name = Utils::make_pretty($player_name);
        $player_name = Utils::sanitize($player_name);
        my $og_player_name = $player_name;
        my $div_player_name = $current_division_name . "-" . $player_name;

        if ($tou_div_names{$div_player_name})
        {
          $tou->{Constants::TOU_ERROR_REPORT} = Utils::format_error([
                                ["ERROR:    ", "player name appears more than once"],
                                ["File:     ", $tou_file],
                                ["Division: ", $current_division_name],
                                ["Player:   ", $player_name]
                              ]);
          return $tou;
        }

        if ($tou_names{$player_name})
        {
          # A player has switched divisions mid tournament which is a massive pain in the ass
          $tou->{Constants::TOU_ERROR_REPORT} = Utils::format_error([
                                ["WARNING:  ", "player has switched divisions mid-tournament"],
                                ["File:     ", $tou_file],
                                ["Division: ", $current_division_name],
                                ["Player:   ", $player_name]
                              ]);
          $player_names_to_ids->{$div_player_name} = $player_names_to_ids->{$player_name};
          $player_name = $div_player_name;
          $tournament_results->{$player_name} = 
          {
            "player_id"       => $player_names_to_ids->{$div_player_name},
            "player_name"     => $pretty_player_name,
            "division_id"     => -1, # This will be replaced with the actual id later
            # Calculations done later because byes are annoying
            "wins"            => 0,
            "losses"          => 0,
            "byes"            => 0,
            # "prize_money"    => 0,
            # "prize_currency" => "AAA",
            # "prize_ech_rate" => 1,
            "start_rating"    => $tournament_results->{$og_player_name}->{'start_rating'},
            "end_rating"      => $tournament_results->{$og_player_name}->{'end_rating'},
            "date"            => $date,
            "tournament_name" => $tournament_name
          };
        }
 
        $tou_names{$og_player_name} = 1;
        $tou_div_names{$div_player_name} = 1;

        $tournament_results->{$player_name}->{'division_id'} = $current_division_name; # Will be changed later

        if (!Utils::player_name_is_bye($player_name) && !$tournament_results->{$player_name})
        {
          $tou->{Constants::TOU_ERROR_REPORT} = Utils::format_error([
                                ["ERROR:", "Player name does not appear in corresponding .STS file"], 
                                ["Name: ", $player_name], 
                                ["File: ", $tou_file], 
                                ["Line: ", $_],
                              ]);
          return $tou;                
        }

        $player_spreads->{$player_name} = 0;

        $tou_game_data_hashref->{$current_division_name . "-" . $current_player_number} = 
        {
          "name"  => $player_name,
          "games" => \@games
        };

        $current_player_number++;
      }
      $is_header = 0;
    }

    my $failure_comp = Utils::compare_names(\%tou_names, \%st_names);

    if ($failure_comp)
    {
      my $not_in_tou = $failure_comp->[0];
      my $not_in_st  = $failure_comp->[1];

      $tou->{Constants::TOU_ERROR_REPORT} = Utils::format_error([
                            ["ERROR:                ", "names in the .tou and .STS/.STA files do not match" ],
                            ["File:                 ", $filename],
                            ["Missing in .tou:      ", $not_in_tou],
                            ["Missing in .STS/.STA: ", $not_in_st]
                          ]);
      return $tou;
    }


    my $game_and_player_results_hashref = {};

    foreach my $key (keys %{$tou_game_data_hashref})
    {
      $key =~ /(.*)-(.*)/;
      my $division      = $1;
      my $player_number = $2;

      my $player_item   = $tou_game_data_hashref->{$key};

      my $player_name   = $player_item->{'name'};

      if (Utils::player_name_is_bye($player_name))
      {
        $tournament_results->{$player_name}->{'is_bye'} = 1;
        next;
      }

      my @player_games  = @{$player_item->{'games'}};
      my $num_player_games = scalar @player_games;

      for(my $i = 0; $i < $num_player_games; $i++)
      {
        my $player_score = $player_games[$i]->[0];
        my $opp_number   = $player_games[$i]->[1];

        my $opp_opp_number = $tou_game_data_hashref->{$division . "-" . $opp_number}->{'games'}->[$i]->[1];

        if (!$opp_opp_number || $opp_opp_number != $player_number)
        {
          $tou->{Constants::TOU_ERROR_REPORT} = Utils::format_error([
                                ["ERROR:             ", "opponent of opponent is not player"],
                                ["Files:             ", $filename],
                                ["Division:          ", $division],
                                ["Round:             ", $i + 1],
                                ["Player name:       ", $player_name],
                                ["Player number:     ", $player_number],
                                ["Opp number:        ", $opp_number],
                                ["Opp of opp number: ", $opp_opp_number]
                              ]);
          return $tou;
        }


        my $opp_key  = $division . "-" . $opp_number;
        my $opp_item = $tou_game_data_hashref->{$opp_key};

        my $opp_score;
        my $opp_name;


        if (!(defined $opp_item))
        {
        #This assumes invalid player numbers are errors
        #and is commented so that invalid numbers are treated as byes
        #format_error([
        #               ["ERROR:        ", "Undefined opponent item"],
        #               ["Files:        ", $filename],
        #               ["Division:     ", $division],
        #               ["Round:        ", $i + 1],
        #               ["Num p games   ", $num_player_games],
        #               ["Round:        ", $i + 1],
        #               ["Player name:  ", $player_name],
        #               ["Player score: ", $player_score],
        #               ["Opp key:      ", $opp_key],
        #             ]);
        #return $tou;
        $opp_score = 0;
        $opp_name = "BYE";
        } 
        else
        {
          $opp_score = $opp_item->{'games'}->[$i]->[0];
          $opp_name  = $opp_item->{'name'};
        }

        if (!(defined $opp_score) || !(defined $opp_name))
        {
          $tou->{Constants::TOU_ERROR_REPORT} = Utils::format_error([
                                ["ERROR:        ", "Undefined opponent name or score"],
                                ["Files:        ", $filename],
                                ["Division:     ", $division],
                                ["Round:        ", $i + 1],
                                ["Num p games   ", $num_player_games],
                                ["Player name:  ", $player_name],
                                ["Player score: ", $player_score],
                                ["Num opp games:", scalar @{$opp_item->{'games'}}],
                                ["Opp name:     ", $opp_name],
                                ["Opp score:    ", $opp_score],
                                ["Opp key:      ", $opp_key],
                              ]);
          return $tou;
        } 

        my $is_bye = Utils::player_name_is_bye($opp_name) || $opp_number == $player_number;

        $tournament_results->{$player_name}->{'byes'} += !!$is_bye;

        my $players_key = $player_number . "-" . $opp_number;

        if ($opp_number < $player_number)
        {
          $players_key = $opp_number . "-" . $player_number;
        }

        my $db_struct_key = join "-", ($division, $i, $players_key);

        if (!($game_and_player_results_hashref->{$db_struct_key}))
        {

          if ($is_bye)
          {
            $player_score = 50;
            $opp_score    = 0;
          }
          else
          {
            $player_spreads->{$opp_name}    += $opp_score    - $player_score;
          }

          $player_spreads->{$player_name} += $player_score - $opp_score;

          my $player_result;
          my $opp_result;
  
          if ($player_score == $opp_score)
          {
            # if ($is_bye){print "$player_score - $opp_score - $player_name - $opp_name\n\n";}
            $player_result = 0;
            $opp_result    = 0;
            $tournament_results->{$player_name}->{'wins'}   += 0.5;
            $tournament_results->{$player_name}->{'losses'} += 0.5;
            if (!$is_bye)
            {
              $tournament_results->{$opp_name}->{'wins'}      += 0.5;
              $tournament_results->{$opp_name}->{'losses'}    += 0.5;
            }
          }
          elsif ($opp_score > $player_score)
          {
            $player_result = -1;
            $opp_result    = 1;
            $tournament_results->{$player_name}->{'losses'} += 1;
            if (!$is_bye)
            {
              $tournament_results->{$opp_name}->{'wins'}      += 1;
            }
          }
          else
          {
            $player_result = 1;
            $opp_result    = -1;
            if (!$is_bye)
            {
              $tournament_results->{$player_name}->{'wins'} += 1;
              $tournament_results->{$opp_name}->{'losses'}  += 1;
            }
          }

          $game_and_player_results_hashref->{$db_struct_key} = 
          {
            "game" => {
                        "division_id"  => $division, # This will be replaced with actual id later 
                        "round"        => $i + 1,
                        "lexicon_id"   => 1, # Unsure how to determine lexicon for game at this point
                        "gcg_filename" => "example.gcg" # We'll figure this out later
                      },
            "player1_result" => {
                                  "player_id" => $player_names_to_ids->{$player_name}, # This will be replaced with actual id later
                                  "game_id"   => -1, # This will be replaced with actual id later
                                  "score"     => $player_score,
                                  "result"    => $player_result,   
                                },
            "player2_result" => {
                                  "player_id" => $player_names_to_ids->{$opp_name}, # This will be replaced with actual id later
                                  "game_id"   => -1, # This will be replaced with actual id later
                                  "score"     => $opp_score,
                                  "result"    => $opp_result,   
                                }
          };
          if ($is_bye)
          {
            $game_and_player_results_hashref->{$db_struct_key}->{"player2_result"}->{"is_bye"} = 1;
          }
        }
      }
    }

    # TOU Processing is complete
    # Store all perl data structures in the TOU object
    # for database processing. The following needs to be added:
    #
    # Event
    # Tournament
    # Divisions
    # Tournament Results
    # Player Results
    $tou->{Constants::TOU_EVENT}                   = $event;
    $tou->{Constants::TOU_TOURNAMENT}              = $tournament;
    $tou->{Constants::TOU_DIVISIONS}               = \@divisions;
    $tou->{Constants::TOU_TOURNAMENT_RESULTS}      = $tournament_results;
    $tou->{Constants::TOU_GAME_AND_PLAYER_RESULTS} = $game_and_player_results_hashref;
    $tou->{Constants::TOU_PLAYER_SPREADS}          = $player_spreads;
    $tou->{Constants::TOU_NEWED}                   = 1;
    return $tou;
}

sub correct_division_pairings
{
  my $this          = shift;
  my $division_name = shift;

  my $division_data       = $this->{Constants::TOU_DIVISION_DATA}->{$division_name};

  # If the division is valid, no correct is needed
  if (!$division_data->{Constants::TOU_DIVISION_VERIFICATION_REPORT})
  {
    return;
  }

  my $division_matrix_ref = $division_data->{Constants::TOU_DIVISION_MATRIX};
  my $num_rows            = $division_data->{Constants::TOU_DIVISION_NUM_PLAYERS};
  my $num_cols            = $division_data->{Constants::TOU_DIVISION_TOURNAMENT_LENGTH};
  my $player_names_ref    = $division_data->{Constants::TOU_DIVISION_PLAYER_NAMES};

  my $corrections     = "";
  my $num_corrections = 0;

  # Start correcting from round 1 to the last round

  for (my $i = 0; $i < $num_cols; $i++)
  {
    # Get the invalid pairings for this round
    my @badpairings = $this->find_bad_pairings($division_name, $i);
    while(1)
    {
      @badpairings = $this->find_bad_pairings($division_name, $i);
      my $old_num_badpairings = scalar @badpairings;
      while(@badpairings)
      {
        # Here, $ip is the 1-indexed player number which is invalidly paired.
        # We have to use $ip-1 because the division matrix is 0-indexed while
        # the .tou file is 1-indexed.

        my $ip = shift @badpairings;
        my $old_pairing =  $division_matrix_ref->[($ip-1) * $num_cols + $i]->[1];
        my $pairing_found = 0;
  
        my @missing = $this->find_missing($division_name, $i);
  
        # Iterate through all of the players whose numbers do not appear.
        # These players are listed in the @missing array. If a missing
        # player has $ip as an opponent. Unpair $ip with the old bad
        # pairing and pair them with the player who is missing from the
        # division.

        while(@missing)
        {
          my $m = shift @missing;
          my $missing_opp = $division_matrix_ref->[($m-1) * $num_cols + $i]->[1];
          if ($missing_opp && $missing_opp == $ip)
          {
            $division_matrix_ref->[($ip-1) * $num_cols + $i]->[1] = $m;
            my $cor = sprintf "   Round %3s: [%3s, %3s] -> [%3s, %3s] (pairing)\n", $i+1, $ip, $old_pairing, $ip, $m;
            $corrections .= $cor;
            # print $cor;
            # print "Pairing $ip with $m in round " . ($i+1) . "\n";
            # print division_matrix_to_string($player_names_ref, $division_matrix_ref, $num_cols, $i, $ip);
            $num_corrections++;
            $pairing_found = 1;
          }
        }
      }
      # Update the invalid pairings array
      @badpairings = $this->find_bad_pairings($division_name, $i);
      my $new_num_badpairings = scalar @badpairings;
      
      # If the number of invalid pairings pairings did not change after the
      # attempted corrections, abort this phase of the corrections
      # as there is not enough information to correct in this phase.
      if ($old_num_badpairings == $new_num_badpairings)
      {
        last;
      }
    }

    # Assume players playing nonexistent players get byes
    for (my $k = 0; $k < $num_rows; $k++)
    {
      my $item = $division_matrix_ref->[$k * $num_cols + $i];
      if (defined $item)
      {
        my $opp = $item->[1];
        if ($opp < 0 || $opp > $num_rows)
        {
          # If a player is paired with a non existent player number assume a bye
          $corrections .= sprintf "   Round %3s: [%3s, %3s] -> [%3s, %3s] (bye, invalid player number)\n", $i+1, $k+1, $opp, $k+1, $k+1;
          $item->[1] = $k+1;
          $item->[0] = Constants::DEFAULT_BYE_SCORE;
          $opp       = $k+1;
          $num_corrections++;
        }
      }
    }
    # If pairings can't be found assume byes
    @badpairings = $this->find_bad_pairings($division_name, $i);
    while(@badpairings)
    {
      my $ip = shift @badpairings;
      my $old_pairing =  $division_matrix_ref->[($ip-1) * $num_cols + $i]->[1];

      # If no opp plays this player, assume they have a bye
      $division_matrix_ref->[($ip - 1) * $num_cols + $i]->[1] = $ip;
      $division_matrix_ref->[($ip - 1) * $num_cols + $i]->[0] = Constants::DEFAULT_BYE_SCORE;

      my $cor.= sprintf "   Round %3s: [%3s, %3s] -> [%3s, %3s] (bye, no valid opponent)\n", $i+1, $ip, $old_pairing, $ip, $ip;
      $corrections .= $cor;
      $num_corrections++;
    }
  }
  if ($num_corrections)
  {
    $division_data->{Constants::TOU_DIVISION_VERIFICATION_REPORT} .= "Made $num_corrections corrections\n\n" . $corrections;
    $this->{Constants::TOU_REWRITE_NEEDED} = 1;
  }
}

sub create_division_matrix
{
  my $this                   = shift;
  my $division_name          = shift;
  my $division_data_arrayref = shift;
  my $tourney_length         = shift;

  my @division_data_array    = @{$division_data_arrayref};

  my $start_line = shift @division_data_array;

  my $num_players = scalar @division_data_array;

  my @player_names = ();

  my @division_matrix = ();

  my $num_missing_games = 0;

  # The division matrix is a 1-d array modeling a 2-d array.
  # To get the element [a, b], use division_matrix[(tourney_length * a) + b]

  for (my $i = 0; $i < $num_players; $i++)
  {
    my @player_data_array = @{$division_data_array[$i]};

    push @player_names, (shift @player_data_array);
    
    for (my $k = 0; $k < $tourney_length; $k++)
    {
      if (@player_data_array)
      {
        push @division_matrix, (shift @player_data_array);
      }
      else
      {
        push @division_matrix, undef;
        $num_missing_games++;
      }
    }
  }

  my $division_data = {};

  $division_data->
    {Constants::TOU_DIVISION_MATRIX}              = \@division_matrix;
  $division_data->
    {Constants::TOU_DIVISION_PLAYER_NAMES}        = \@player_names;
  $division_data->
    {Constants::TOU_DIVISION_NUM_PLAYERS}         = scalar @player_names;
  $division_data->
    {Constants::TOU_DIVISION_NUM_MISSING_GAMES}   = $num_missing_games;
  $division_data->
    {Constants::TOU_DIVISION_TOURNAMENT_LENGTH}   = $tourney_length;
  $division_data->
    {Constants::TOU_DIVISION_VERIFICATION_REPORT} = '';

  $this->{Constants::TOU_DIVISION_DATA}->{$division_name} = $division_data;
}

sub division_matrix_to_string
{
  my $player_names_arrayref = shift;
  my $division_matrix_ref            = shift;
  my $tourney_length        = shift;

  my $col_to_bold = shift;
  my $row_to_bold = shift;

  my $s = "";

  my $num_names =  scalar @{$player_names_arrayref};

  $s .= sprintf "%-28s", "";
 
  for (my $i = 0; $i < $tourney_length; $i++)
  {
    $s .= sprintf "%4s", $i + 1;
  }
  $s .= "\n\n";
  for (my $i = 0; $i < $num_names; $i++)
  {
    my $trunc_name = substr($player_names_arrayref->[$i], 0, 20);
    $s .= sprintf "%-4s", $i + 1;
    $s .= sprintf "%-24s", $trunc_name; 
    for (my $k = 0; $k < $tourney_length; $k++)
    {
      my $item = $division_matrix_ref->[$i * $tourney_length + $k];
      if ($item)
      {
        $item = $item->[1];
      }
      else
      {
        $item = -1;
      }
      if (defined $row_to_bold && defined $col_to_bold && $i == $row_to_bold && $k == $col_to_bold)
      {
        $s .= Term::ANSIColor::colored( (sprintf "%4s", $item), 'bold green');
      }
      else
      {
        $s .= sprintf "%4s", $item;
      }
    }
    $s .= "\n" 
  }
  return "Number of Players: $num_names\nNumber of Games: $tourney_length\n\n$s\n";
}

sub fill_division_with_byes
{
  # This subroutine replaces missing games with byes

  my $this                = shift;
  my $division_name       = shift;

  my $division_data       = $this->{Constants::TOU_DIVISION_DATA}->{$division_name};
  my $division_matrix_ref = $division_data->{Constants::TOU_DIVISION_MATRIX};
  my $num_players         = $division_data->{Constants::TOU_DIVISION_NUM_PLAYERS};
  my $tourney_length      = $division_data->{Constants::TOU_DIVISION_TOURNAMENT_LENGTH};
  my $num_missing_games   = $division_data->{Constants::TOU_DIVISION_NUM_MISSING_GAMES};

  my $byes_to_add = $num_missing_games;

  my $bye_report = "";

  while($num_missing_games > 0)
  {
    # In this loop, find the earliest missing game that must be a bye
    # If arbitrary missing games are replaced with byes, valid pairing
    # data could be lost.

    my $min_col = $tourney_length;
    my $min_row = -1;
    row: for (my $row = 0; $row < $num_players; $row++)
    {
      my $num_missing = $this->num_missing_games_in_row($division_name, $row);

      if ($num_missing > 0)
      {
        for (my $col = 0; $col < $tourney_length; $col++)
        {
          # Here we are iterating over every missing game.
          # If a player was a missing game in a round where
          # they could be potentially playing someone else,
          # a bye should not be added. 
          my $pp = $this->potential_pairing($division_name, $col, $row);
                                     

          # If there is no potential pairing and the bye is before
          # the current minimum round bye, update the minimum round bye
          # with this bye.

          if (!$pp && $col < $min_col)
          {
            $min_col = $col;
            $min_row = $row;
          }
        }
      }
    }

    # Insert Bye if available bye is found
    if ($min_col < $tourney_length)
    {
      $bye_report .= $this->insert_bye(
                                        $division_name,
                                        $min_col,
                                        $min_row,
                                        [Constants::DEFAULT_BYE_SCORE, $min_row+1]
                                      );
      $num_missing_games--;
    }
    else
    {
      $division_data->{Constants::TOU_DIVISION_VERIFICATION_REPORT} .= "Cannot fille division with byes: not enough info\n";
      return;
    }
  }

  if ($byes_to_add > 0)
  {
    $division_data->{Constants::TOU_DIVISION_VERIFICATION_REPORT} .= "Added $byes_to_add byes:\n\n" . $bye_report;
    $this->{Constants::TOU_REWRITE_NEEDED} = 1;
  }
}

sub find_bad_pairings
{
  my $this          = shift;
  my $division_name = shift;
  my $i             = shift;

  my $division_data       = $this->{Constants::TOU_DIVISION_DATA}->{$division_name};
  my $division_matrix_ref = $division_data->{Constants::TOU_DIVISION_MATRIX};
  my $num_rows            = $division_data->{Constants::TOU_DIVISION_NUM_PLAYERS};
  my $num_cols            = $division_data->{Constants::TOU_DIVISION_TOURNAMENT_LENGTH};

  # This subroutine returns an array of invalid pairings for round $i + 1.
  # A pairing is invalid if the opponent of the opponent of the player is
  # not the player themself.

  my @badpairings = ();
  for (my $k = 0; $k < $num_rows; $k++)
  {
    my $item = $division_matrix_ref->[$k * $num_cols + $i];
    if (defined $item)
    {
      my $opp = $item->[1];
      my $opp_opp = $division_matrix_ref->[($opp-1) * $num_cols + $i]->[1];
      if (!$opp_opp || $opp_opp != $k + 1)
      {
        push @badpairings, $k+1;
      }
   }
  }
  return @badpairings;
}

sub find_missing
{
  my $this          = shift;
  my $division_name = shift;
  my $i             = shift;

  my $division_data       = $this->{Constants::TOU_DIVISION_DATA}->{$division_name};
  my $division_matrix_ref = $division_data->{Constants::TOU_DIVISION_MATRIX};
  my $num_rows            = $division_data->{Constants::TOU_DIVISION_NUM_PLAYERS};
  my $num_cols            = $division_data->{Constants::TOU_DIVISION_TOURNAMENT_LENGTH};

  # This subroutine returns an array of players whose player numbers do not
  # appear in the column for round $i + 1

  my %missing_hash = ();
  for (my $b = 0; $b < $num_rows; $b++)
  {
    $missing_hash{$b+1} = 1;
  }
  for (my $b = 0; $b < $num_rows; $b++)
  {
    my $opp = $division_matrix_ref->[$b * $num_cols + $i]->[1];
    if ($missing_hash{$opp})
    {
      delete $missing_hash{$opp};
    }
  }
  my @a = keys %missing_hash;
  return @a;
}

sub format_verification
{
  my $this          = shift;
  my $division_name = shift;

  my $division_data       = $this->{Constants::TOU_DIVISION_DATA}->{$division_name};
  my $division_matrix_ref = $division_data->{Constants::TOU_DIVISION_MATRIX};
  my $num_rows            = $division_data->{Constants::TOU_DIVISION_NUM_PLAYERS};
  my $num_cols            = $division_data->{Constants::TOU_DIVISION_TOURNAMENT_LENGTH};
  
  my $tou_file = $this->{Constants::TOU_FILENAME};
  my $valid    = $division_data->{Constants::TOU_DIVISION_VALID};
  my $verification_report = $division_data->{Constants::TOU_DIVISION_VERIFICATION_REPORT};

  if ($verification_report)
  {
    my $formatted_report = <<VR
***************************************
********* Verification Report *********
***************************************
 
$verification_report
VR
;
    my $status;

    if ($valid)
    {
      $status = 'NONFATAL';
    }
    else
    {
      $status = 'FATAL';
    }

    my $verify_info = Utils::format_error([
                                            ['VERIFICATION: ', 'TOU file failed verification (report below)'],
                                            ['Status:       ', $status],
                                            ['File:         ', $tou_file],
                                            ['Division:     ', $division_name]
                                          ]);
    $division_data->{Constants::TOU_DIVISION_VERIFICATION_REPORT} =
      $verify_info . "\n" . $formatted_report;
  }
}

sub insert_bye
{
  my $this          = shift;
  my $division_name = shift;
  my $col           = shift;
  my $row           = shift;
  my $item          = shift;

  my $division_data       = $this->{Constants::TOU_DIVISION_DATA}->{$division_name};
  my $division_matrix_ref = $division_data->{Constants::TOU_DIVISION_MATRIX};
  my $num_rows            = $division_data->{Constants::TOU_DIVISION_NUM_PLAYERS};
  my $num_cols            = $division_data->{Constants::TOU_DIVISION_TOURNAMENT_LENGTH};

  # Insert a bye in the division matrix at column $col and row $row.
  # Shift the succeeding (by round) player data by one round.
  for (my $i = $col; $i < $num_cols; $i++)
  {
    my $replaced_value = $division_matrix_ref->[$row * $num_cols + $i];
    $division_matrix_ref->[$row * $num_cols + $i] = $item;

    $item = $replaced_value;

    if ($i == $num_cols - 1 && defined $item)
    {
      return sprintf "Bye insert failed at (%s, %s), attempted to erase a valid value\n", $col, $row;
    }
    
    if (!(defined $item))
    {
      last;
    }
  }
  return sprintf "   Round %3s:            -> [%3s, %3s] (bye)\n", $col+1, $row+1, $row+1;
}

sub load
{
  my $this = shift;
  my $dbh  = shift;

  if (!$this->{Constants::TOU_NEWED})
  {
    $this->{Constants::TOU_ERROR_REPORT} = Utils::format_error([
                            ["ERROR: ", "attempted to load an uninitialized TOU object"],
                            ["File:  ", $this->{Constants::TOU_FILENAME}]
                        ]);
    return;  
  }

  my $filename                        = $this->{Constants::TOU_FILENAME};
  my $event                           = $this->{Constants::TOU_EVENT};
  my $tournament                      = $this->{Constants::TOU_TOURNAMENT};
  my @divisions                       = @{$this->{Constants::TOU_DIVISIONS}};
  my $tournament_results              = $this->{Constants::TOU_TOURNAMENT_RESULTS};
  my $game_and_player_results_hashref = $this->{Constants::TOU_GAME_AND_PLAYER_RESULTS};
  my $player_spreads                  = $this->{Constants::TOU_PLAYER_SPREADS};

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

  if (!$event_id)
  {
    $this->{Constants::TOU_ERROR_REPORT} = Utils::format_error([
                            ["ERROR: ", "hash insert failed"],
                            ["File:  ", $filename],
                            ["Table: ", $events_tn],
                            ["Hash:  ", Dumper($event)],
                        ]);
    return;  
  }

  $tournament->{event_id} = $event_id;

  my $tournament_name = $tournament->{name};
  my $tournament_id = Utils::insert_hash_into_table($dbh, $tournaments_tn, $tournament);

  if (!$tournament_id)
  {
    $this->{Constants::TOU_ERROR_REPORT} = Utils::format_error([
                            ["ERROR: ", "hash insert failed"],
                            ["File:  ", $filename],
                            ["Table: ", $tournaments_tn],
                            ["Hash:  ", Dumper($tournament)],
                        ]);
    return;  
  }

  foreach my $div (@divisions)
  {
    $div->{"tournament_id"} = $tournament_id;
  }
 
  my $division_id_hash = Utils::insert_hash_list_into_table($dbh, $divisions_tn, \@divisions, "name");

  foreach my $key (keys %{$tournament_results})
  {
    my $tr = $tournament_results->{$key};
    if ($tr->{'is_bye'})
    {
      delete $tournament_results->{$key};
      next;
    }

    my $total_games = $tr->{'wins'} + $tr->{'losses'};

    if ($total_games == 0)
    {
      $this->{Constants::TOU_ERROR_REPORT} = Utils::format_error([
                            ["WARNING:   ", "player played zero games for the tournament"],
                            ["File:      ", $filename],
                            ["Player ID: ", $tr->{'player_id'}]
                          ]);
    }

    Utils::add_games_to_existing_player($dbh, $tr->{'player_id'}, $total_games);

    my $division_name = $tr->{"division_id"};
    my $division_id = $division_id_hash->{$division_name};

    $tr->{"division_id"} = $division_id;
    $tr->{"spread"}      = $player_spreads->{$key};
  }

  my $failure = Utils::rank_tournament_results($tournament_results);
  if ($failure)
  {
    unshift @$failure, ["Files:  ", $filename];
    unshift @$failure, ["ERROR:  ", "Ranking tournament results failed"];
    Utils::format_error($failure);
    return;
  }

  foreach my $key (keys %{$tournament_results})
  {
    my $player_id        = $tournament_results->{$key}->{'player_id'};
    my $div_id           = $tournament_results->{$key}->{'division_id'};

    if (!$player_id || !$div_id)
    {
      $this->{Constants::TOU_ERROR_REPORT} = Utils::format_error([
                            ["ERROR: ", "no player id or maybe division id for tournament result"],
                            ["File: ", $filename],
                            ["player: ", $key],
                            ["player id: ", $player_id],
                            ["division id: ", $div_id],
                            ["tr: ", Dumper($tournament_results->{$key})]
                          ]);
      return;
    }
    Utils::insert_hash_into_table($dbh, $tournament_results_tn, $tournament_results->{$key});
  }
 

  # print Dumper($game_and_player_results_hashref);

  foreach my $key (keys $game_and_player_results_hashref)
  {
    my $gapr = $game_and_player_results_hashref->{$key};

    $gapr->{"game"}->{"division_id"} = $division_id_hash->{$gapr->{"game"}->{"division_id"}};
    my $game_id = Utils::insert_hash_into_table($dbh, $games_tn, $gapr->{"game"});

    $gapr->{"player1_result"}->{"game_id"} = $game_id;
    $gapr->{"player2_result"}->{"game_id"} = $game_id;

    Utils::insert_hash_into_table($dbh, $player_results_tn, $gapr->{"player1_result"});
    if (!$gapr->{"player2_result"}->{"is_bye"})
    {
      Utils::insert_hash_into_table($dbh, $player_results_tn, $gapr->{"player2_result"});
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
}

sub matrix_row_to_file_string
{
  my $division_matrix_ref = shift;
  my $num_cols   = shift;
  my $row        = shift;

  my $s = "";

  for (my $i = 0; $i < $num_cols; $i++)
  {
    # The item is [score, opponent number, '+' is player went first else '']
    my $item = $division_matrix_ref->[$row * $num_cols + $i];
    my $score = $item->[0];
    my $opp   = $item->[2] . $item->[1];
    $s .= (sprintf "%6s", $score ) . (sprintf "%6s", $opp) . " ";
  }
  return $s . "\n";
}

sub num_missing_games_in_row
{
  my $this = shift;
  my $division_name = shift;
  my $row = shift;

  my $division_data       = $this->{Constants::TOU_DIVISION_DATA}->{$division_name};
  my $division_matrix_ref = $division_data->{Constants::TOU_DIVISION_MATRIX};
  my $tourney_length      = $division_data->{Constants::TOU_DIVISION_TOURNAMENT_LENGTH};

  my $sum = 0;
  for (my $i = 0; $i < $tourney_length; $i++)
  {
    if (!(defined $division_matrix_ref->[$row * $tourney_length + $i]))
    {
      $sum++;
    }
  }
  return $sum;
}

sub populate_new_lines_hashref
{
  my $this          = shift;
  my $division_name = shift;
  my $hashref       = shift;
  my $start_line    = shift;

  my $division_data       = $this->{Constants::TOU_DIVISION_DATA}->{$division_name};
  my $division_matrix_ref = $division_data->{Constants::TOU_DIVISION_MATRIX};
  my $num_rows            = $division_data->{Constants::TOU_DIVISION_NUM_PLAYERS};
  my $num_cols            = $division_data->{Constants::TOU_DIVISION_TOURNAMENT_LENGTH};
  my $player_names_ref    = $division_data->{Constants::TOU_DIVISION_PLAYER_NAMES};

  my @player_names_array = @{$player_names_ref};
  
  for (my $i = 0; $i < $num_rows; $i++)
  {
    # Create a new line for the .tou
    # First the player name is listed, followed by the game data
    # as per the .tou format

    $hashref->{$start_line} = (sprintf "%-30s", (shift @player_names_array)) . " ";
    $hashref->{$start_line} .= TOU::matrix_row_to_file_string($division_matrix_ref, $num_cols, $i);
    $start_line++;
  }
}

sub potential_pairing
{
  my $this          = shift;
  my $division_name = shift;
  my $column        = shift;
  my $row           = shift;

  my $division_data       = $this->{Constants::TOU_DIVISION_DATA}->{$division_name};
  my $division_matrix_ref = $division_data->{Constants::TOU_DIVISION_MATRIX};
  my $num_rows            = $division_data->{Constants::TOU_DIVISION_NUM_PLAYERS};
  my $num_cols            = $division_data->{Constants::TOU_DIVISION_TOURNAMENT_LENGTH};

  # Find a potential pairing for the player in row $row and the round
  # corresponding to column $col. Depending on how many missing
  # games each player has, the potential game data that makes the
  # valid pairing could be separated by more than one column.

  for (my $i = 0; $i < $num_rows; $i++)
  {
    my $num_missing = $this->num_missing_games_in_row($division_name, $num_cols, $i);
    my $limit = max($column - $num_missing, 0);
    if ($i == $row)
    {
      $limit = $column
    }
    for (my $k = $column; $k >= $limit; $k--)
    {
      my $el = $division_matrix_ref->[$i * $num_cols + $k];
      if ($el && $el->[1] == $row + 1)
      {
        return $i + 1;
      }
    }
  }
  return 0;
}

sub validate_division
{
  # This subroutine validates a division matrix by ensuring the following:
  #   - There is data for every player in every round
  #   - For every round, every player number appear exactly once
  #   - The opponent of the opponent of the player is the player themself

  my $this          = shift;
  my $division_name = shift;
  my $set_valid     = shift;

  my $division_data       = $this->{Constants::TOU_DIVISION_DATA}->{$division_name};
  my $division_matrix_ref = $division_data->{Constants::TOU_DIVISION_MATRIX};
  my $num_rows            = $division_data->{Constants::TOU_DIVISION_NUM_PLAYERS};
  my $num_cols            = $division_data->{Constants::TOU_DIVISION_TOURNAMENT_LENGTH};

  my %column_hash = ();

  my $report_string = "";

  for (my $i = 0; $i < $num_rows; $i++)
  {
    $column_hash{$i+1} = 0;
  }
  
  for (my $i = 0; $i < $num_cols; $i++)
  {
    for (my $k = 0; $k < $num_rows; $k++)
    {
      my $item = $division_matrix_ref->[$k * $num_cols + $i];
      if (!(defined $item))
      {
        # Check that each matrix entry has data.
        $report_string .= sprintf "   undefined item at (%s, %s)\n", $k, $i;
      }
      if (defined $item)
      {
        if ($column_hash{$item->[1]})
        {
          # Check that a player isn't paired against more than one person.
          $report_string .= 
            sprintf "   more than one player plays player %s in round %s\n",
                    $item->[1], $i+1;
        }
        $column_hash{$item->[1]} += 1;
        my $opp = $item->[1];
        my $opp_opp = $division_matrix_ref->[($opp-1) * $num_cols + $i]->[1];
        if (!$opp_opp || $opp_opp != $k + 1)
        {
          if (!$opp_opp)
          {
            $opp_opp = "undef";
          }
          # Check that the opponent of the opponent of the player is the
          # player.
          $report_string .=
            sprintf "   opponent of opponent is not player
                        (player, opp, opp of opp) = (%s, %s, %s)
                        in round %s\n", $k+1, $opp, $opp_opp, $i+1;
        }
      }
    }
    foreach my $key (keys %column_hash)
    {
      if (!$column_hash{$key})
      {
        # Check that the player is paired against someone as opposed to no one.
        $report_string .=
          sprintf "   missing player number             %s in round %s\n",
                  $key, $i+1;
      }
    }
    foreach my $key (keys %column_hash)
    {
      $column_hash{$key} = 0;
    }
  }

  if ($report_string)
  {
    $division_data->{Constants::TOU_DIVISION_VERIFICATION_REPORT} .= "\n" . $report_string;
    $division_data->{Constants::TOU_DIVISION_VALID} = 0;
    if ($set_valid)
    {
      $this->{Constants::TOU_VALID} = 0;
      $this->{Constants::TOU_REWRITE_NEEDED} = 0;
    }
    else
    {
      $this->{Constants::TOU_REWRITE_NEEDED} = 1;
    }
  }
  else
  {
    $division_data->{Constants::TOU_DIVISION_VALID} = 1;
  }
}

sub verify_division
{
  my $this                   = shift;
  my $division_name          = shift;
  my $division_data_arrayref = shift;
  my $tourney_length         = shift;
  my $new_lines_hashref      = shift;

  my @division_data_array = @{$division_data_arrayref};
  my $start_line          = shift @division_data_array;
  my $num_players         = scalar @division_data_array;

  # Create a matrix representation of the division. With the matrix
  # abstraction the division becomes easier to verify, correct, and
  # rewrite.

  $this->create_division_matrix($division_name, $division_data_arrayref, $tourney_length);

  # If players are missing games, the matrix will be jagged.
  # Before verification, the matrix must be square, so byes are put in place
  # of missing games.

  $this->fill_division_with_byes($division_name);

  $this->validate_division($division_name);

  # If the verification report is not the empty string, errors were found, so the
  # correct_division_pairings subroutine is called to attempt to correct the
  # errors.

  $this->correct_division_pairings($division_name);
  
  # After correction, revalidate, as the correction may have failed or further
  # corrupted the division data. Pass in a true additional argument to set
  # the TOU and division valid bit.

  $this->validate_division($division_name, 1);

  # If there are corrections or errors, additional formatting is needed
  $this->format_verification($division_name);
  
  # If a rewrite is needed, populate the $new_lines_hashref which will be used
  # to rewrite the .tou file.

  if ($this->{Constants::TOU_REWRITE_NEEDED})
  {
    $this->populate_new_lines_hashref(
                                       $division_name,
                                       $new_lines_hashref,
                                       $start_line
                                     );
  }
}

sub verify
{
  # This subroutine attempts to correct and verify the input .tou specified
  # by $input_filename. If at least one correction is made, a new .tou file
  # is written to $output_filename
  #
  my $this            = shift;
  my $input_filename  = $this->{Constants::TOU_FILENAME};
  my $output_filename = $this->{Constants::TOU_FILENAME};

  my $line_number = 1;
  my $div_name;
  my @division_data_array = ();
  my %file_contents = ();
  my $new_lines_hashref = {};
  my $tourney_length = 0;

  my @division_reports = ();
  my $valid = 1;
  my $file_has_changed = 0;

  open(INPUT_FILE, "<", $input_filename)
    or die "Cannot open .tou file $input_filename: $!";

  while(<INPUT_FILE>)
  {
    $file_contents{$line_number} = $_;
    chomp $_;
    my $at_end = $_ =~ /END OF FILE/;
    if ($_ =~ /^\*(.*)/ || $at_end)
    {
      # If this is the end of the division, verify the division
      if (@division_data_array)
      {
        $this->verify_division(
                                $div_name,
                                \@division_data_array,
                                $tourney_length,
                                $new_lines_hashref
                              );
      }
      # Prepare loop for a new division
      if (!$at_end)
      {
        $div_name = $1;
        $div_name =~ s/^\s+|\s+$//g;
        @division_data_array = ();
        $tourney_length = 0;
      }
    }
    elsif ($_ =~ /\w\s+(\d+\s+\+?\d+(\s+|$))+/)
    {

      # If a winning negative score is listed, correct it by adding 2000
      # to ensure compliance with the .tou format
      if ($_ =~ /2\s?(\-\d+)/)
      {    
        $this->{Constants::TOU_WARNING_REPORT} .= Utils::format_error([
                              ["WARNING:      ", "converting negative winning score"],
                              ["File:         ", $input_filename],
                              ["Line:         ", $_."\n"],
                              ["Rewritten to: ", $output_filename]
                            ]);
        my $neg_score = $1 + 2000;
        $_ =~ s/2\s?\-\d+/$neg_score/g;
        $this->{Constants::TOU_REWRITE_NEEDED} = 1;
      }

      my @player_game_data = split/\s+/, $_;
  
      my @games = ();

      my $games_played = () = $_ =~ /(\d+\s+\+?\d+(?:\s+|$))/g;

      $tourney_length = List::Util::max($games_played, $tourney_length);

      for(my $i = 0; $i < $games_played; $i++)
      {
        my $opp_number  = pop @player_game_data;
        my $score       = pop @player_game_data;

        my $first_string = '';
     
        if ($opp_number =~ /\+/)
        {
          $first_string = '+';
        }

        $opp_number =~ s/\D//g;
        $score      =~ s/\D//g;

        unshift @games, [$score, $opp_number, $first_string];
      }

      my $player_name = join " ", @player_game_data;
      $player_name =~ s/^\s+|\s+$//g;

      unshift @games, $player_name;

      # If this is the first division listed in this .tou file, prepend the
      # current line number of the file to the division data. The line
      # number will be needed if a correction is made and the file needs
      # to be rewritten

      if (!@division_data_array)
      {
        unshift @division_data_array, $line_number;
      }
      
      push @division_data_array, \@games;
    }
    $line_number++; 
  }

  # If the file has changed, rewrite it using the new_lines_hashref
  if ($this->{Constants::TOU_REWRITE_NEEDED})
  {
    open(my $fh, ">", $output_filename);
    for (my $i = 1; $i < $line_number; $i++)
    {
      my $maybe_new_line = $new_lines_hashref->{$i};
      if ($maybe_new_line)
      {
        print $fh $maybe_new_line;
      }
      else
      {
        print $fh $file_contents{$i};
      }
    }
    close $fh;
  }
}

1;
