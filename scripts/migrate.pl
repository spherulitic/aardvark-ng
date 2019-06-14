#!/usr/bin/perl

# This script uses tournament files to build a database of tournament data.

use strict;
use warnings;
use Getopt::Long;
use Pod::Usage qw(pod2usage);
use DBI;
use Data::Dumper;

use lib './modules';
use Constants;

require './scripts/correct_and_verify.pl';
require './scripts/get_tournament_data_filenames.pl';

my $tou_file_extension = Constants::TOU_FILE_EXTENSION;
my $sts_file_extension = Constants::STS_FILE_EXTENSION;
my $sta_file_extension = Constants::STA_FILE_EXTENSION;

my $provisional_games_max = Constants::PROVISIONAL_GAMES_MAX;

my $database_name = Constants::DATABASE_NAME;
my $host_name     = Constants::DATABASE_HOST_NAME;
my $user_name     = Constants::DATABASE_USER_NAME;
my $password      = Constants::DATABASE_PASSWORD;

my $tables = Constants::TABLES;

my $creation_order = Constants::TABLE_CREATION_ORDER;

my $lexicons = Constants::LEXICONS;

my $players_tn            = Constants::PLAYERS_TABLE_NAME;
my $player_alt_names_tn   = Constants::PLAYER_ALT_NAMES_TABLE_NAME;
my $tournaments_tn        = Constants::TOURNAMENTS_TABLE_NAME;
my $events_tn             = Constants::EVENTS_TABLE_NAME;
my $divisions_tn          = Constants::DIVISIONS_TABLE_NAME;
my $games_tn              = Constants::GAMES_TABLE_NAME;
my $tournament_results_tn = Constants::TOURNAMENT_RESULTS_TABLE_NAME;
my $player_results_tn     = Constants::PLAYER_RESULTS_TABLE_NAME;
my $lexicons_tn           = Constants::LEXICONS_TABLE_NAME;

my $working_directory      = Constants::DEFAULT_WORKING_DIR;
my $year_regex             = Constants::DEFAULT_YEAR_REGEX;
my $country_trigraph_regex = Constants::DEFAULT_COUNTRY_TRIGRAPH_REGEX;
my $file_regex             = Constants::DEFAULT_FILE_REGEX;
my $initialize             = '';
my $add_tournament         = '';
my $help                   = '';

my %deceased_players_hash = ();

my %alt_names_hash = ();

my $photo_dir = $working_directory . "/" . Constants::PHOTO_DIR;

unless (caller)
{
  main();
}


sub main
{
  
  GetOptions (
               'directory:s' => \$working_directory,
               'year:s'      => \$year_regex,
               'country:s'   => \$country_trigraph_regex,
               'file:s'      => \$file_regex,
               'initialize'  => \$initialize,
               'add'         => \$add_tournament,
               'help|?'      => \$help,
             ); 

  pod2usage(1) if $help;  
  

  my $dbh = initialize_database($database_name, $host_name, $user_name,
                                $password, $tables, $creation_order,
                                $add_tournament);
  
  if ($initialize){return;}
  
 
  my $lexicon_ids = insert_hash_list_into_table($dbh, $lexicons_tn, $lexicons,
                                                "name");
  
  my $filenames_array_ref = get_tournament_data_filenames($working_directory,
                            $year_regex, $country_trigraph_regex, $file_regex);
  
  printf "Filnames found: %s\n\n", scalar @{$filenames_array_ref};

  # print Dumper($filenames_array_ref);

  # check_for_duplicate_files($filenames_array_ref);

  populate_alt_names_hash();

  # print Dumper(\%alt_names_hash);

  populate_deceased_players_hash();
  load_tournament_files($dbh, $filenames_array_ref);
}

sub populate_deceased_players_hash
{
  my $deceased_players_filename = Constants::INPUT_DIR . "/" .
                                  Constants::DECEASED_PLAYERS;
  
  open(DECEASED, "<", $deceased_players_filename);
  while(<DECEASED>)
  {
    chomp $_;
    $_ =~ s/^\s+|\s+$//g;

    my $true_name = $_;
    my $alt_name  = $alt_names_hash{$_};

    if ($alt_name)
    {
      $true_name = $alt_name;
    }

    $deceased_players_hash{$_} = 1;
  }
}
sub populate_alt_names_hash
{
  my $dup_filename = Constants::INPUT_DIR . "/" . Constants::INPUT_MERGE_FILE;

  open(DUP, "<", $dup_filename);

  while(<DUP>)
  {
    chomp $_;

    $_ =~ s/^\s+|\s+$//g;

    if ($_ =~ /^#/ || !$_){next;}

    my @names = split /,/, $_;

    @names = map { $_ =~ s/^\s+|\s+$//gr  } @names;

    if (!@names){next;}
    
    my $true_name = shift @names;

    foreach my $alt_name (@names)
    {
      if ($alt_names_hash{$alt_name})
      {
        print "ERROR:    alt name already mapped\n";
        print "Alt name: $alt_name\n";
        die;
      }
      $alt_names_hash{$alt_name} = $true_name;
    }
  }
}

sub convert_name
{
  my $name = shift;

  $name =~ s/^\s+|\s+$//g;

  my $true_name = $alt_names_hash{$name};

  if ($true_name)
  {
    return $true_name;
  }
  return $name;
}

sub initialize_database
{
  my $database_name = shift;
  my $host_name     = shift;
  my $user_name     = shift;
  my $password      = shift;

  my $tables_ref         = shift;
  my $creation_order_ref = shift;

  my $add_tournament     = shift;

  my %tables = %{$tables_ref};
  my @creation_order = @{$creation_order_ref};

  # Connect to the database
  my $dbh = DBI->connect("DBI:mysql:database=$database_name;host=$host_name",
                         $user_name, $password,
                         {'RaiseError' => 1});
  

  # If a tournament is being added, don't recreate each table
  if (!$add_tournament)
  {
    for(my $i = 0; $i < scalar @creation_order; $i++)
    {
      my $key = $creation_order[$i];
      my @columns = @{$tables{$key}};
    
      my $columns_string = join ", ", @columns;
    
      my $statement = "CREATE TABLE $key ($columns_string)";
    
      $dbh->do($statement);
    }
  }

  return $dbh;
}


sub load_tournament_files
{
  my $dbh = shift;
  my $filenames_array_ref = shift;

  my @filenames_array = @{$filenames_array_ref};

  my $player_names_to_ids = {};

  filename: foreach my $filename (@filenames_array)
  {
    my $tou_file = $filename;

    $filename =~ s/\.(.*)$//;

    my $sts_file = $filename . $sts_file_extension;
    my $sta_file = $filename . $sta_file_extension;

    if (!( -e $tou_file))
    {
      format_error([
                     ["ERROR: ", "Missing .tou file"],
                     ["File:  ", $tou_file]
                   ]);
      next filename;
    }


    # First validate the .tou file
    my $reports = correct_and_verify_tournament($tou_file, $tou_file);

    my $parse  = parse_reports($reports, $tou_file, $tou_file);  
    if ($parse)
    { 
      print $parse."\n";
    }

    if (!( -e $sts_file || -e $sta_file))
    {
      format_error([
                     ["ERROR: ", "Missing .STS or .STA file"],
                     ["File:  ", $filename]
                   ]);
      next filename;
    }

    my $sts_or_sta_file = $sts_file;
    my $is_sts = 1;
    if (!( -e $sts_file))
    {
      $sts_or_sta_file = $sta_file;
      $is_sts = 0;
    }


    # Read the .tou file for the date only
    my $date;
    open(my $tou_read, "<", $tou_file) or die "Cannot open .tou file $tou_file: $!";
    my $first_line = <$tou_read>;
    close $tou_read;
    chomp $first_line;
    if ($first_line =~ /^\*.(\d\d).(\d\d).(\d\d\d\d) .*$/)
    {
      $date = $3 . $2 . $1;
    }
    else
    {
      format_error([
                     ["ERROR:", "malformed .tou header"],
                     ["File: ", $tou_file],
                   ]);
      next filename;
    }

    my %st_names  = ();
    my %tou_names = ();

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
      # "td"         => "director of tournament",
    };
    my @divisions = ();
    my $tournament_results = {};

    # my $games;
    # my $player_results;

    # Read the .STS file
    open(STS_OR_STA_FILE, "<", $sts_or_sta_file) or die "Cannot open .STS or .STA file $sts_or_sta_file: $!";
    while(<STS_OR_STA_FILE>)
    {
      chomp $_;

      # Remove trailing and leading whitespace from line
      $_ =~ s/^\s+|\s+$//g;

      if (!$_){next;}

      # Must defined these
      my $player_country;
      my $player_name;
      my $start_rating;
      my $end_rating;

      # Player info must be extracted differently if the file is .STS as
      # opposed to .STA
      if ($is_sts)
      {
        my @player_items = split /,/, $_;

        # Remove trailing and leading whitespace for all items
        @player_items = map { $_ =~ s/^\s+|\s+$//gr } @player_items;

        $player_country = $player_items[1];
        $player_name    = $player_items[2];
        $start_rating   = $player_items[8];
        $end_rating     = $player_items[9];
      }
      else
      {
        if ($_ =~ /^\|(.)(\w+)\s+([^\|]+)\|.*\|.*\|.*\|\s+(\d+)\D.* (\d+) \|/)
        {
          my $is_new_player = $1; # Unused for now
          $player_country   = $2;
          $player_name      = $3;
          $start_rating     = $4;
          $end_rating       = $5;

          $player_country =~ s/^\s+|\s+$//g;
          $player_name    =~ s/^\s+|\s+$//g;
          $start_rating   =~ s/^\s+|\s+$//g;
          $end_rating     =~ s/^\s+|\s+$//g;
        }
        else
        {
          next;
        }
      }

      if (player_name_is_bye($player_name))
      {
        next;
      }

      if ($player_country !~ /[A-Z][A-Z][A-Z]/)
      {
        $player_country = undef;
      }

      # Convert possible alt name to correct name

      $player_name = convert_name($player_name);
      # Error with name appears twice, can happen if a player switches divisions midtournament
#      if ($st_names{$player_name})
#      {
#        format_error([
#                       ["ERROR:  ", "player name appears more than once"],
#                       ["File:   ", $sts_or_sta_file],
#                       ["Player: ", $player_name]
#                     ]);
#        next filename;
#      }
 
      $st_names{$player_name} = 1;

      # Search for this player in the players table
      my $player_query = "SELECT id, country, last_played FROM $players_tn WHERE BINARY name=\"$player_name\"";

      my @player_query_result = $dbh->selectrow_array($player_query, {"RaiseError" => 1});


      my $player_id;

      if (!@player_query_result) # Player does not exist
      {
        $player_id = insert_hash_into_table
        (
          $dbh,
          $players_tn,
          {
            "name"        => $player_name,
            "country"     => $player_country,
            "photo"       => get_player_photo($player_name),
            "suspended"   => 0,  # Updated later
            "deceased"    => !!$deceased_players_hash{$player_name},
            "provisional" => -1, # Updated laster
            "total_games" => 0,   # Updated later
            "last_played" => $date
          }
        );
        $player_names_to_ids->{$player_name} = $player_id;

        # Insert player into an PLAYER_ALT_NAMES table
        insert_hash_into_table
        (
          $dbh,
          $player_alt_names_tn,
          {
            "alt_name"  => $player_name,
            "player_id" => $player_id
          }
        );
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
          update_record_by_id($dbh, $players_tn, $player_id, {'last_played' => $date}); 
        }

        if ($no_country_cond || $changed_to_newer_country_cond)
        {
          update_record_by_id($dbh, $players_tn, $player_id, {'country' => $player_country}); 
        }
#       Warning if someone switches countries
#       if ($changed_country_cond)
#       {
#         format_error([
#                        ["WARNING:         ", "player switched countries"],
#                        ["File:            ", $filename],
#                        ["Player:          ", $player_name],
#                        ["Current country: ", $existing_country],
#                        ["New country:     ", $player_country],
#                      ]);
#       }
      } 
 
      $player_id = $player_names_to_ids->{$player_name};

      if (!$player_id)
      {
        format_error([
                       ["ERROR: ", "player name does not have id"], 
                       ["File:  ", $sts_or_sta_file], 
                       ["Name:  ", $player_name] 
                     ]);
      }
 
      # Still need spread and position
      $tournament_results->{$player_name} = 
      {
        "player_id"      => $player_id,
        "division_id"    => -1, # This will be replaced with the actual id later
        # Calculations done later because byes are annoying
        "wins"           => 0,
        "losses"         => 0,
        "byes"           => 0,
        # "prize_money"    => 0,
        # "prize_currency" => "AAA",
        # "prize_ech_rate" => 1,
        "start_rating"   => $start_rating,
        "end_rating"     => $end_rating,
      };
    }

    # Now parse the .tou file for game data

    my $current_division_number = 0;
    my $current_division_name   = "";
    my $current_player_number   = 1;

    my $tou_game_data_hashref = {};

    my %tou_div_names = ();
    my $player_spreads = {};
    # Read the .tou file
    open(TOU_FILE, "<", $tou_file) or die "Cannot open .tou file $tou_file: $!";
    while(<TOU_FILE>)
    {
      chomp $_;
      if ($_ =~ /^\*(.*)/ && $_ !~ /END OF FILE/)
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
          format_error([
                         ["ERROR:", "Missing division name"],
                         ["File: ", $tou_file],
                       ]);
          next filename;
        }

        my @player_game_data = split/\s+/, $_;
    
        my @games = ();

        my $games_played = () = $_ =~ /(\d+\s+\+?\d+(?:\s+|$))/g;

        my $current_div_hash = $divisions[-1];

        if ($current_div_hash->{'length'} == -1)
        {
          $current_div_hash->{'length'} = $games_played;
        }
        elsif ($current_div_hash->{'length'} != $games_played)
        {
             format_error( [
                           ["ERROR:    ", "inconsistent number of tournament games"],
                           ["File:     ", $tou_file],
                           ["Division: ", $current_division_name],
                           ["Line:     ", $_]
                         ]);
            next filename;         
        }

        for(my $i = 0; $i < $games_played; $i++)
        {
          my $opp_number  = pop @player_game_data;
          $opp_number =~ s/\D//g;
          my $score       = pop @player_game_data;

          if ($opp_number =~ /\D/ || $score !~ /^-?\d+$/)
          {
            format_error( [
                           ["ERROR:        ", "Malformed opponent number or player score"],
                           ["File:         ", $tou_file],
                           ["Opp number:   ", $opp_number],
                           ["Player score: ", $score],
                           ["Games played: ", $games_played],
                           ["Line:         ", $_]
                         ]);
            next filename;
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

        $player_name = convert_name($player_name);

        my $og_player_name = $player_name;

        my $div_player_name = $current_division_name . "-" . $player_name;

        if ($tou_div_names{$div_player_name})
        {
          format_error([
                         ["ERROR:    ", "player name appears more than once"],
                         ["File:     ", $tou_file],
                         ["Division: ", $current_division_name],
                         ["Player:   ", $player_name]
                       ]);
          next filename;
        }

        if ($tou_names{$player_name})
        {
          # A player has switched divisions mid tournament which is a massive pain in the ass
          format_error([
                         ["WARNING:  ", "player has switched divisions mid-tournament"],
                         ["File:     ", $tou_file],
                         ["Division: ", $current_division_name],
                         ["Player:   ", $player_name]
                       ]);
          $player_names_to_ids->{$div_player_name} = $player_names_to_ids->{$player_name};
          $player_name = $div_player_name;
          $tournament_results->{$player_name} = 
          {
            "player_id"      => $player_names_to_ids->{$div_player_name},
            "division_id"    => -1, # This will be replaced with the actual id later
            # Calculations done later because byes are annoying
            "wins"           => 0,
            "losses"         => 0,
            "byes"           => 0,
            # "prize_money"    => 0,
            # "prize_currency" => "AAA",
            # "prize_ech_rate" => 1,
            "start_rating"   => $tournament_results->{$og_player_name}->{'start_rating'},
            "end_rating"     => $tournament_results->{$og_player_name}->{'end_rating'},
          };
        }
 
        $tou_names{$og_player_name} = 1;
        $tou_div_names{$div_player_name} = 1;

        $tournament_results->{$player_name}->{'division_id'} = $current_division_name; # Will be changed later

        if (!player_name_is_bye($player_name) && !$tournament_results->{$player_name})
        {
          format_error([
                         ["ERROR:", "Player name does not appear in corresponding .STS file"], 
                         ["Name: ", $player_name], 
                         ["File: ", $tou_file], 
                         ["Line: ", $_],
                       ]);
          next filename;                
        }

        $player_spreads->{$player_name} = 0;

        $tou_game_data_hashref->{$current_division_name . "-" . $current_player_number} = 
        {
          "name"  => $player_name,
          "games" => \@games
        };

        $current_player_number++;
      }
    }

    my $failure_comp = compare_names(\%tou_names, \%st_names);

    if ($failure_comp)
    {
      my $not_in_tou = $failure_comp->[0];
      my $not_in_st  = $failure_comp->[1];

      format_error([
                     ["ERROR:                ", "names in the .tou and .STS/.STA files do not match" ],
                     ["File:                 ", $filename],
                     ["Missing in .tou:      ", $not_in_tou],
                     ["Missing in .STS/.STA: ", $not_in_st]
                   ]);
      next filename;
    }


    my $game_and_player_results_hashref = {};

    foreach my $key (keys %{$tou_game_data_hashref})
    {
      $key =~ /(.*)-(.*)/;
      my $division      = $1;
      my $player_number = $2;

      my $player_item   = $tou_game_data_hashref->{$key};

      my $player_name   = $player_item->{'name'};

      if (player_name_is_bye($player_name))
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
          format_error([
                         ["ERROR:             ", "opponent of opponent is not player"],
                         ["Files:             ", $filename],
                         ["Division:          ", $division],
                         ["Round:             ", $i + 1],
                         ["Player name:       ", $player_name],
                         ["Player number:     ", $player_number],
                         ["Opp number:        ", $opp_number],
                         ["Opp of opp number: ", $opp_opp_number]
                       ]);
          next filename;
        }


        my $opp_key  = $division . "-" . $opp_number;
        my $opp_item = $tou_game_data_hashref->{$opp_key};

        my $opp_score;
        my $opp_name;


        if (!(defined $opp_item))
        {
#          This assumes invalid player numbers are errors
#          and is commented so that invalid numbers are treated as byes
#          format_error([
#                         ["ERROR:        ", "Undefined opponent item"],
#                         ["Files:        ", $filename],
#                         ["Division:     ", $division],
#                         ["Round:        ", $i + 1],
#                         ["Num p games   ", $num_player_games],
#                         ["Round:        ", $i + 1],
#                         ["Player name:  ", $player_name],
#                         ["Player score: ", $player_score],
#                         ["Opp key:      ", $opp_key],
#                       ]);
#          next filename;
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
          format_error([
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
          next filename;
        } 

        my $is_bye = player_name_is_bye($opp_name) || $opp_number == $player_number;


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
    # Add to database top down so we can link up the foreign keys
    my $event_id      = insert_hash_into_table($dbh, $events_tn, $event);

    if (!$event_id)
    {
      format_error([
                       ["ERROR: ", "hash insert failed"],
                       ["File:  ", $filename],
                       ["Table: ", $events_tn],
                       ["Hash:  ", Dumper($event)],
                   ]);
      next filename;  
    }

    $tournament->{"event_id"} = $event_id;

    my $tournament_id = insert_hash_into_table($dbh, $tournaments_tn, $tournament);

    if (!$tournament_id)
    {
      format_error([
                       ["ERROR: ", "hash insert failed"],
                       ["File:  ", $filename],
                       ["Table: ", $tournaments_tn],
                       ["Hash:  ", Dumper($tournament)],
                   ]);
      next filename;  
    }


    foreach my $div (@divisions)
    {
      $div->{"tournament_id"} = $tournament_id;
    }
   
   
    my $division_id_hash = insert_hash_list_into_table($dbh, $divisions_tn, \@divisions, "name");

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
        format_error([
                       ["WARNING:   ", "player played zero games for the tournament"],
                       ["File:      ", $filename],
                       ["Player ID: ", $tr->{'player_id'}]
                     ]);
      }

      add_games_to_existing_player($dbh, $tr->{'player_id'}, $total_games);

      my $division_name = $tr->{"division_id"};
      my $division_id = $division_id_hash->{$division_name};

      $tr->{"division_id"} = $division_id;
      $tr->{"spread"}      = $player_spreads->{$key};
    }
    # print "the reses:\n" . Dumper($tournament_results);
    # Position must be derived at this point
    my $failure = rank_tournament_results($tournament_results);
    if ($failure)
    {
      unshift @$failure, ["Files:  ", $filename];
      unshift @$failure, ["ERROR:  ", "Ranking tournament results failed"];
      format_error($failure);
      next filename;
    }

    foreach my $key (keys %{$tournament_results})
    {
      my $player_id        = $tournament_results->{$key}->{'player_id'};
      my $div_id           = $tournament_results->{$key}->{'division_id'};

      if (!$player_id || !$div_id)
      {
        format_error([
                       ["ERROR: ", "no player id or maybe division id for tournament result"],
                       ["File: ", $filename],
                       ["player: ", $key],
                       ["player id: ", $player_id],
                       ["division id: ", $div_id],
                       ["tr: ", Dumper($tournament_results->{$key})],
                       ["names to ids: ", Dumper($player_names_to_ids)],
                     ]);
      }
      insert_hash_into_table($dbh, $tournament_results_tn, $tournament_results->{$key});
    }
   

    # print Dumper($game_and_player_results_hashref);
 
    foreach my $key (keys $game_and_player_results_hashref)
    {
      my $gapr = $game_and_player_results_hashref->{$key};

      $gapr->{"game"}->{"division_id"} = $division_id_hash->{$gapr->{"game"}->{"division_id"}};
      my $game_id = insert_hash_into_table($dbh, $games_tn, $gapr->{"game"});

      $gapr->{"player1_result"}->{"game_id"} = $game_id;
      $gapr->{"player2_result"}->{"game_id"} = $game_id;

      insert_hash_into_table($dbh, $player_results_tn, $gapr->{"player1_result"});
      if (!$gapr->{"player2_result"}->{"is_bye"})
      {
        insert_hash_into_table($dbh, $player_results_tn, $gapr->{"player2_result"});
      }
    }
  }

  # Update last played date for all players
  # Legacy code, last played is now updated on the fly
#  my $update_last_played =
#  "
#  UPDATE $players_tn AS p
#  SET p.last_played =
#  (
#    SELECT MAX(end_date)
#    FROM tournaments AS t, divisions AS d, tournament_results AS tr
#    WHERE p.id = tr.player_id AND tr.division_id = d.id AND d.tournament_id = t.id
#  )
#  "; 
#  $dbh->do($update_last_played, {"RaiseError" => 1});


  # Update provisional status for all players

  my $update_provisional =
  "
  UPDATE $players_tn AS p
  SET p.provisional =
  (
    CASE
      WHEN p.total_games < $provisional_games_max
        THEN 1
      ELSE 0
    END
  )
  "; 
  $dbh->do($update_provisional, {"RaiseError" => 1});
}

sub get_player_photo
{
  my $name = shift;

  $name =~ s/\s//g;

  $name = lc $name;

  my $filename = $photo_dir . "/" . $name . ".jpg";

  if (-e $filename)
  {
    return $filename;
  }
  return undef; 
}

sub compare_names
{
  my $tou_ref = shift;
  my $st_ref  = shift;

  my $not_in_tou = "";
  my $not_in_st  = "";

  foreach my $tou_key (keys %{$tou_ref})
  {
      if (!($st_ref->{$tou_key}) && !player_name_is_bye($tou_key))
      {
        $not_in_st .= $tou_key . ", ";
      }
  }

  foreach my $st_key (keys %{$st_ref})
  {
    if (!$tou_ref->{$st_key} && !player_name_is_bye($st_key))
    {
      $not_in_tou .= $st_key . ", ";
    }
  }

  if ($not_in_tou || $not_in_st)
  {
    return [$not_in_tou,$not_in_st];
  }
  return 0;

}

sub player_name_is_bye
{
  my $name = shift;

  $name = sanitize($name);

  if ($name eq "RUSSELLBYERS")
  {
    return 0;
  }

  return ($name =~ /BYE/);
}

sub sanitize
{
  my $name = shift;
  
  $name = uc $name;

  $name =~ s/[^A-Z]//g;

  return $name;
}

sub add_games_to_existing_player
{
  my $dbh          = shift;
  my $player_id  = shift;
  my $games_played = shift;  

  my $total_games_update = "UPDATE $players_tn SET total_games = total_games + $games_played WHERE id=$player_id";
  $dbh->do($total_games_update, {"RaiseError" => 1});
  return $dbh->last_insert_id(undef, undef, undef, undef);
}

sub update_record_by_id
{
  my $dbh             = shift;
  my $table_name      = shift;
  my $id              = shift;
  my $fields_hash_ref = shift;

  foreach my $key (keys %{$fields_hash_ref})
  {
    my $value = $fields_hash_ref->{$key};
    my $update = "UPDATE $table_name SET $key = '$value' WHERE id=$id";
    $dbh->do($update, {"RaiseError" => 1});
  }
}

sub rank_tournament_results
{
  my $tournament_results = shift;

  my $divisions = {};

  foreach my $key (keys %{$tournament_results})
  {
    my $tr = $tournament_results->{$key};

    my $div = $tr->{'division_id'};

    if (!$div)
    {
      return [
               ["Result: ", Dumper($tr)],
               ["Key:    ", $key],
             ];
    }

    my $div_arrayref = $divisions->{$div};

    my $new_item = [$key, $tr->{'wins'}, $tr->{'spread'}];

    if (!$div_arrayref)
    {
      $divisions->{$div} = [$new_item];
    }
    else
    {
      push @$div_arrayref, $new_item;
    }
  }

  foreach my $key (keys %{$divisions})
  {
    my @div_array = @{$divisions->{$key}};


    my @ranked_players = sort
                         { 
                           if ($b->[1] == $a->[1]) {$b->[2] <=> $a->[2];}
                           else {$b->[1] <=> $a->[1];}
                         } 
                         @div_array;

    for (my $i = 0; $i < scalar @ranked_players; $i++)
    {
      my $player_name     = $ranked_players[$i]->[0];
      my $player_position = $i + 1;
      $tournament_results->{$player_name}->{'position'} = $player_position;
    }
  }
  return 0;
}


sub insert_hash_list_into_table
{
  my $dbh     = shift;
  my $table   = shift;
  my $listref = shift;

  my $last_insert_id_key_field = shift;

  my $last_insert_id_hash = {};

  my @list = @{$listref};

  foreach my $item (@list)
  {
    my $id = insert_hash_into_table($dbh, $table, $item);
    if ($last_insert_id_key_field)
    {
      $last_insert_id_hash->{$item->{$last_insert_id_key_field}} = $id;
    }
  }
  return $last_insert_id_hash;
}

sub insert_hash_into_table
{
  my $dbh     = shift;
  my $table   = shift;
  my $hashref = shift;
 
  #print "the hashref: " . Dumper($hashref);
 

  my $keys_string   = "(";
  my $values_string = "(";

  foreach my $key (keys %{$hashref})
  {
    if (defined $hashref->{$key})
    {
      $keys_string   .= "$key,";
      $values_string .= "\"$hashref->{$key}\",";
    }
  }

  chop($keys_string);
  chop($values_string);

  if (!$keys_string || !$values_string)
  {

    return undef;
  }

  $keys_string   .= ")";
  $values_string .= ")";

  $dbh->do("INSERT INTO $table $keys_string VALUE $values_string;", {"RaiseError" => 1}  );
  return $dbh->last_insert_id(undef, undef, undef, undef);
}

sub format_error
{
  my $error_arrayref = shift;

  my $l = scalar @{$error_arrayref};

  for (my $i = 0; $i < $l; $i++)
  {
    my $item1 =  $error_arrayref->[$i]->[0];
    my $item2 =  $error_arrayref->[$i]->[1];

    if (!$item1){$item1 = "undef";}
    if (!$item2){$item2 = "undef";}

    printf "%s %s\n", $item1, $item2;
  }
  print "\n";
}

1;

__END__

=head1 SYNOPSIS



 ./scripts/migrate.pl [-h] [-i] [-a] [-d=<dir>] [-y=<year_regex>] [-c=<country_trigraph_regex>] [-f=<file_regex>] 

 Options:
   -h, --help       brief help message
   -d, --directory  specifies the working directory where the year directories are stored 
   -y, --year       specifies the year regex for which tournament files to migrate
                    (for example -y 2... would migrate all tournament data from years starting with 2
   -c, --country    specifies the country regex for which tournament files to migrate
                    (for example -c ..A would migrate all tournament data from country trigraphs that end in A
   -f, --file       specifies the filename regex for which tournament files to migrate
                    (for example -f atlanta16.tou would migrate tournament data from files
                    with "atlant16.tou" in the filename and their corresponding .STS/.STA files)
   -i, --initialize flag to initialize the database with empty tables
   -a, --add        flag to add tournaments to an initialized database
=cut


