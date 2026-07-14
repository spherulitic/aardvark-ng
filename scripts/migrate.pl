#!/usr/bin/perl

# This script uses tournament files to build a database of tournament data.

use strict;
use warnings;
use Getopt::Long;
use Pod::Usage qw(pod2usage);
use DBI;
use Data::Dumper;
use Devel::Timer;

use lib './modules';
use Constants;

require './scripts/correct_and_verify.pl';

require './scripts/update_current_players.pl';
require './scripts/utils.pl';
require './scripts/drop_all_wespa_tables.pl';
require './scripts/record_db.pl';
require './scripts/update_player_titles.pl';

my $tou_file_extension = Constants::TOU_FILE_EXTENSION;
my $sts_file_extension = Constants::STS_FILE_EXTENSION;
my $sta_file_extension = Constants::STA_FILE_EXTENSION;
my $st4_file_extension = Constants::ST4_FILE_EXTENSION;

my $provisional_games_max = Constants::PROVISIONAL_GAMES_MAX;

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

my $tou_data_directory     = get_environment_name(Constants::TOURNAMENT_DATA_DIR);
my $working_directory      = get_environment_name(Constants::DEFAULT_WORKING_DIR);
my $year_regex             = Constants::DEFAULT_YEAR_REGEX;
my $country_trigraph_regex = Constants::DEFAULT_COUNTRY_TRIGRAPH_REGEX;
my $file_regex             = Constants::DEFAULT_FILE_REGEX;
my $create_html            = '';
my $help                   = '';

my %deceased_players_hash = ();

my %alt_names_hash = ();

my $photo_dir = Constants::PHOTO_DIR;

unless (caller)
{
  main();
}


sub main
{
  
  my $timer = Devel::Timer->new();

  GetOptions (
               'directory:s' => \$working_directory,
               'year:s'      => \$year_regex,
               'country:s'   => \$country_trigraph_regex,
               'file:s'      => \$file_regex,
               'html'        => \$create_html,
               'help|?'      => \$help,
             ); 

  $timer->mark("option parsing");
  pod2usage(1) if $help;  

  # This hash is used to consolidate the names that are considered duplciates
  populate_alt_names_hash();
  populate_deceased_players_hash();
  $timer->mark("name hashes populated");

  drop_all_wespa_tables(\%alt_names_hash);
  $timer->mark("wespa tables dropped");

  # take a backup of the players and print the player id numbers

  record_database();
  $timer->mark("record database - backup players");

  my $dbh = initialize_database($tables, $creation_order);
  $timer->mark("database initialized");
  
  my $lexicon_ids = insert_hash_list_into_table($dbh, $lexicons_tn, $lexicons,
                                                "name");
  $timer->mark("lexicons inserted");
  
  my $filenames_array_ref = get_tournament_data_filenames($tou_data_directory,
                            $year_regex, $country_trigraph_regex, $file_regex);
  
  $timer->mark("file list gathered");
  printf "Filenames found: %s\n\n", scalar @{$filenames_array_ref};

  # print Dumper($filenames_array_ref);

  # check_for_duplicate_files($filenames_array_ref);

  # print Dumper(\%alt_names_hash);


  my $tournament_ids_to_create = load_tournament_files($dbh, $filenames_array_ref);
  $timer->mark("tournament files processed (BIG ONE)");


  populate_player_alt_names($dbh);
  $timer->mark("player alt names populated from duplicates.txt");

  update_current_players();
  $timer->mark("current players updated");

  update_player_titles();
  $timer->mark("player titles updated");

  copy_database_to_production();
  $timer->mark("database copied to production");

  $timer->report();
}

 sub populate_deceased_players_hash
 {
   my $deceased_players_filename = Constants::INPUT_DIR . "/" .
                                   Constants::DECEASED_PLAYERS;
   
   # Initialize a counter
   my $deceased_count = 0;
   my @deceased_list;
   
   open(DECEASED, "<", $deceased_players_filename) 
       or die "ERROR: Cannot open deceased players file: $!";
   
   while(<DECEASED>)
   {
     chomp $_;
     $_ =~ s/^\s+|\s+$//g;
     
     # Skip empty lines
     next unless $_;
     
     my $true_name = $_;
     my $sanitized_name = sanitize($_);
     my $alt_name  = $alt_names_hash{$sanitized_name};
     
     if ($alt_name)
     {
       $true_name = $alt_name;
     }
     
     $deceased_players_hash{$_} = 1;
     $deceased_count++;
     push @deceased_list, $true_name;
   }
   
   close(DECEASED);
   
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
      my $sanitized_alt = sanitize($alt_name);
      my $existing_canonical = $alt_names_hash{$sanitized_alt};
      if ($existing_canonical)
      {
        if ($existing_canonical eq $true_name)
        {
          # Same alt-to-canonical mapping already exists; silently skip
          next;
        }
        else
        {
          print "ERROR:    alt name mapped to multiple canonical names\n";
          print "Alt name:              $alt_name (sanitized: $sanitized_alt)\n";
          print "Existing canonical:    $existing_canonical\n";
          print "New canonical:         $true_name\n";
          die;
        }
      }
      $alt_names_hash{$sanitized_alt} = $true_name;
    }
  }
}

sub populate_player_alt_names
{
  my $dbh = shift;

  # Truncate the table first
  $dbh->do("TRUNCATE TABLE $player_alt_names_tn", {"RaiseError" => 1});

  # Read duplicates.txt and insert each alt_name mapped to its canonical player_id
  my $dup_filename = Constants::INPUT_DIR . "/" . Constants::INPUT_MERGE_FILE;

  open(my $dup_fh, "<", $dup_filename) or die "ERROR: Cannot open $dup_filename: $!";

  my $sth = $dbh->prepare("SELECT id FROM $players_tn WHERE BINARY name=?");
  my $insert_sth = $dbh->prepare("INSERT INTO $player_alt_names_tn (alt_name, player_id) VALUES (?, ?)");

  while (<$dup_fh>)
  {
    chomp;
    s/^\s+|\s+$//g;
    next if /^#/ || !$_;

    my @names = split /,/, $_;
    @names = map { s/^\s+|\s+$//gr } @names;
    next if !@names;

    my $canonical_name = shift @names;

    $sth->execute($canonical_name);
    my ($player_id) = $sth->fetchrow_array();
    if (!$player_id)
    {
      print "WARNING: canonical name '$canonical_name' not found in players table, skipping\n";
      next;
    }

    foreach my $alt_name (@names)
    {
      my $sanitized_name = sanitize($alt_name);
      $insert_sth->execute($sanitized_name, $player_id);
    }
  }

  close($dup_fh);
}

sub convert_name
{
  my $name = shift;

  $name =~ s/^\s+|\s+$//g;

  my $sanitized_name = sanitize($name);
  my $true_name = $alt_names_hash{$sanitized_name};

  if ($true_name)
  {
    return $true_name;
  }
  return $name;
}

sub convert_trigraph
{
  my ($trigraph, $context) = @_;  # $context is a hashref with any additional info
  my $trigraph_hash = Constants::COUNTRY_TRIGRAPH_TO_COUNTRY_NAME_HASHREF;
  my $trigraph_correction_hash = Constants::COUNTRY_TRIGRAPH_CONVERSION;
 
  # Trigraph is correct
  if ($trigraph_hash->{$trigraph})
  {
    return $trigraph;
  }
  # Trigraph is the empty string
  if (!$trigraph)
  {
    return undef;
  }
  # Trigraph is incorrect but has correction mapping
  my $correct_trigraph = $trigraph_correction_hash->{$trigraph};
  if ($correct_trigraph)
  {
    return $correct_trigraph;
  }
  # Check for a length of 3 because there are numerous
  # tournaments where players with no country are denoted
  # by 'OS' and we don't want to clog up the logs
  if (length $trigraph == 3)
  {
    my @error_details = (['WARNING:  ', 'Uncorrected country trigraph'],
                         ['Trigraph: ', $trigraph]);
    
    # Add any context that was provided
    if ($context) {
      # Player context
      push @error_details, ['Player:   ', $context->{player_name}] if $context->{player_name};
      push @error_details, ['Tournament:', $context->{tournament_name}] if $context->{tournament_name};
      
      # File context
      push @error_details, ['File:     ', $context->{filename}] if $context->{filename};
      push @error_details, ['Line:     ', $context->{line}] if $context->{line};
      
      # Location context
      push @error_details, ['Country:  ', $context->{country}] if $context->{country};
      push @error_details, ['Division: ', $context->{division}] if $context->{division};
      
      # Generic additional info
      push @error_details, ['Info:     ', $context->{info}] if $context->{info};
    }
    
    format_error(\@error_details);
  }
  return undef;
}

sub initialize_database
{
  my $tables_ref         = shift;
  my $creation_order_ref = shift;

  my %tables = %{$tables_ref};
  my @creation_order = @{$creation_order_ref};

  # Connect to the database
  my $dbh = connect_to_database();
 

  for(my $i = 0; $i < scalar @creation_order; $i++)
  {
    my $key = $creation_order[$i];
    my @columns = @{$tables{$key}};
    
    my $columns_string = join ", ", @columns;
    
    my $statement = "CREATE TABLE IF NOT EXISTS $key ($columns_string)";
    
    $dbh->do($statement);
  }

  return $dbh;
}


sub load_tournament_files
{
  my $dbh = shift;
  my $filenames_array_ref = shift;

  my @filenames_array = @{$filenames_array_ref};

  my $player_names_to_ids = {};

  my @tournament_ids_to_convert_to_html = ();

  my %player_cache;

  filename: foreach my $filename (@filenames_array)
  {
    if($dbh->{AutoCommit}) {
      # Start transaction for this file
      $dbh->begin_work();
    } else {
      # Already in a transaction
      print "DEBUG: Already in transaction for $filename\n";
    }

    # Wrap file processing in an eval for error handling
    eval {

    my $tou_file = $filename;

    $filename =~ s/\.(.*)$//;

    my @filename_items = split /\//, $filename;

    my $tournament_country = $filename_items[-2];

    my $sts_file = $filename . $sts_file_extension;
    my $sta_file = $filename . $sta_file_extension;
    my $st4_file = $filename . $st4_file_extension;

    if (!( -e $tou_file))
    {
      format_error([
                     ["ERROR: ", "Missing .tou file"],
                     ["File:  ", $tou_file]
                   ]);
      die "SKIP: $filename";
    }

    my $loaded_tournaments_tn = Constants::LOADED_TOURNAMENTS_TABLE_NAME;
    my $tou_query = "SELECT * FROM $loaded_tournaments_tn WHERE filename=\"$tou_file\"";

    my @tou_query_result = $dbh->selectrow_array($tou_query, {"RaiseError" => 1});

    if (@tou_query_result)
    {
      # print "Tournament already processed: $tou_file (Skipping)\n";
      die "SKIP: $filename";
    }

    # First validate and maybe correct the .tou file
    my $reports = correct_and_verify_tournament($tou_file, $tou_file);

    my $parse  = parse_reports($reports, $tou_file, $tou_file);  
    if ($parse)
    { 
      print $parse."\n";
    }

    if (!( -e $sts_file || -e $sta_file))
    {
      format_error([
                     ["ERROR: ", "Missing .STS file and .STA file and .ST4 file"],
                     ["File:  ", $filename]
                   ]);
      die "SKIP: $filename";
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
      format_error([
                     ["ERROR:", "malformed .tou header"],
                     ["File: ", $tou_file],
                   ]);
      die "SKIP: $filename";
    }

    # These hashes of .STS/.STA names and .tou names will be used to check
    # for discrepancies between the two

    # Names for either STS or STA file
    my %st_names  = ();
    # Names for the ST4 file
    my %st4_names  = ();
    # Names for the TOU file
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
      "country"    => convert_trigraph($tournament_country, {tournament_name => $tournament_name,
                                                             filename => $tou_file,
                                                             info => "$date"} ), 
      # "td"         => "director of tournament",
    };
    my @divisions = ();
    my $tournament_results = {};

    my $switch_world_and_nation = 0;
    my $no_world                = 1;
    my $begin_player_captures   = 0;
    my $sts_has_rds = 0;

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
      # Rating deviations
      my $old_rating_dev = undef;
      my $new_rating_dev = undef;

      # Player info must be extracted differently if the file is .STS as
      # opposed to .STA
      my $player_items_length = -1;
      if ($is_sts)
      {
        my @player_items = split /,/, $_;
	if ($player_items_length < 0)
	{
	  $player_items_length = scalar @player_items;
	  if ($player_items_length != 14 && $player_items_length != 16)
	  {
	    format_error([
                           ["ERROR: ", "invalid number of items in STS file"], 
                           ["File:  ", $sts_or_sta_file], 
                           ["Line:  ", $_],
                         ]);
            die "SKIP: $filename";  
  
	  }
	} elsif ($player_items_length != scalar @player_items)
	{
	    format_error([
                           ["ERROR: ", "inconsistent number of items in STS file"], 
                           ["File:  ", $sts_or_sta_file], 
                           ["Line:  ", $_],
                         ]);
            die "SKIP: $filename";  
	}
        $player_country    = $player_items[1];
        $player_name       = $player_items[2];
        $expected_wins     = $player_items[4];
        $start_rating      = $player_items[8];
        $end_rating        = $player_items[9];
        $old_world_rank    = $player_items[10];
        $new_world_rank    = $player_items[11];
        $old_national_rank = $player_items[12];
        $new_national_rank = $player_items[13];
	if ($player_items_length == 16)
	{
	  $old_rating_dev = $player_items[14];
	  $new_rating_dev = $player_items[15];
	  $sts_has_rds = 1;
	}
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
            format_error([
                           ["ERROR: ", "invalid number of items in STA first rank column"], 
                           ["File:  ", $sts_or_sta_file], 
                           ["Line:  ", $_],
                         ]);
            die "SKIP: $filename";
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
            format_error([
                           ["ERROR: ", "invalid number of items in STA second rank column"], 
                           ["File:  ", $sts_or_sta_file], 
                           ["Line:  ", $_],
                         ]);
            die "SKIP: $filename";
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
            format_error([
                           ["ERROR: ", "invalid number of items in STA wins column"], 
                           ["File:  ", $sts_or_sta_file], 
                           ["Line:  ", $_],
                         ]);
            die "SKIP: $filename";
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
            format_error([
                           ["ERROR: ", "invalid number of items in STA ratings column"], 
                           ["File:  ", $sts_or_sta_file], 
                           ["Line:  ", $_],
                         ]);
            die "SKIP: $filename";
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
      if (player_name_is_bye($player_name))
      {
        next;
      }

      $expected_wins     = negative_one_if_false($expected_wins);
      $start_rating      = negative_one_if_false($start_rating);
      $old_world_rank    = negative_one_if_false($old_world_rank);
      $new_world_rank    = negative_one_if_false($new_world_rank);
      $old_national_rank = negative_one_if_false($old_national_rank);
      $new_national_rank = negative_one_if_false($new_national_rank);
      $old_rating_dev    = negative_one_if_false($old_rating_dev);
      $new_rating_dev    = negative_one_if_false($new_rating_dev);
 
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
        format_error([
                       ["ERROR: ", "required values are uncaptured"], 
                       ["File:  ", $sts_or_sta_file], 
                       ["Name:  ", $player_name],
                       ["Array: ", Dumper(\@required_captures)]
                     ]);
        die "SKIP: $filename";
      }

      # Convert possible alt name to correct name

      $player_name = convert_name($player_name);
      my $pretty_player_name = make_pretty($player_name);
      $player_name = sanitize($player_name);

      # Some country trigraphs in the old aardvark are incorrect
      # and need to be converted to valid ISO 3166 trigraphs
      $player_country = convert_trigraph($player_country, {
                                                player_name => $pretty_player_name,
                                                filename => $sts_or_sta_file,
                                                line => $_,
                                                info => "Processing player in tournament $tournament_name on $date"});      

      # Error with name appears twice, can happen if a player switches divisions midtournament
#      if ($st_names{$player_name})
#      {
#        format_error([
#                       ["ERROR:  ", "player name appears more than once"],
#                       ["File:   ", $sts_or_sta_file],
#                       ["Player: ", $player_name]
#                     ]);
#        die "SKIP: $filename";
#      }
 
      $st_names{$player_name} = 1;

      # Search for this player in the players table
      # If this player already exists in the database, we will need their
      # id for the table to add them properly

#      my $player_query = "SELECT id, country, last_played FROM $players_tn WHERE BINARY name=\"$pretty_player_name\"";

#      my @player_query_result = $dbh->selectrow_array($player_query, {"RaiseError" => 1});

      my @player_query_result;
      if (exists $player_cache{$pretty_player_name}) {
         # Found in cache
         my $cached = $player_cache{$pretty_player_name};
         @player_query_result = ($cached->{id}, $cached->{country}, $cached->{last_played});
     } else {
         # Not in cache, query database
         my $player_query = "SELECT id, country, last_played FROM $players_tn WHERE BINARY name=?";
         my $sth = $dbh->prepare($player_query);
         $sth->execute($pretty_player_name);
         @player_query_result = $sth->fetchrow_array();

         # Store in cache for next time
         if (@player_query_result) {
           $player_cache{$pretty_player_name} = {
             id => $player_query_result[0],
             country => $player_query_result[1],
             last_played => $player_query_result[2]
           };
         }
       }

      my $player_id;

      if (!@player_query_result) # Player does not exist
      {
        # Check if there's an orphan stub (0 total_games) with this name
        # that can be resurrected instead of creating a new ID.
        # This preserves player_id across spelling/name changes.
        my $stub_query = "SELECT id FROM $players_tn WHERE BINARY name=? AND total_games=0";
        my $sth_stub = $dbh->prepare($stub_query);
        $sth_stub->execute($pretty_player_name);
        my ($stub_id) = $sth_stub->fetchrow_array();

        if ($stub_id) {
          $player_id = $stub_id;
          update_record_by_id($dbh, $players_tn, $player_id, {
            "country"     => $player_country,
            "photo"       => get_player_photo($player_name),
            "suspended"   => 0,
            "deceased"    => exists $deceased_players_hash{$player_name} ? 1 : 0,
            "provisional" => -1,
            "total_games" => 0,
            "last_played" => $date,
            "rating"      => $end_rating
          });
          $player_cache{$pretty_player_name} = {
            id => $player_id,
            country => $player_country,
            last_played => $date
          };
        } else {
          $player_id = insert_hash_into_table
          (
            $dbh,
            $players_tn,
            {
              "name"        => $pretty_player_name,
              "country"     => $player_country,
              "photo"       => get_player_photo($player_name),
              "suspended"   => 0,  # Updated later
              "deceased"    => exists $deceased_players_hash{$player_name} ? 1 : 0,
              "provisional" => -1, # Updated later
              "total_games" => 0,   # Updated later
              "last_played" => $date,
              "rating"      => $end_rating
            }
          );
        }
        $player_names_to_ids->{$player_name} = $player_id;
      }
      else
      {
        # If the player already exists, the last_played and country fields
        # may need to be updated

        my $player_id = shift @player_query_result;
        my $existing_country = shift @player_query_result;
        my $player_last_played = shift @player_query_result;

        # Handle undef values
        if (!defined $player_last_played) {
          $player_last_played = '0000-00-00';
        }

        $player_last_played =~ s/\D//g;

        $player_names_to_ids->{$player_name} = $player_id;
      } 

      # Keep an mapping of the names to ids in memory
      # so we don't have to query the database more than necessary 
      $player_id = $player_names_to_ids->{$player_name};

      if (!$player_id)
      {
        format_error([
                       ["ERROR: ", "player name does not have id"], 
                       ["File:  ", $sts_or_sta_file], 
                       ["Name:  ", $player_name] 
                     ]);
        die "SKIP: $filename";
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
	"old_rating_dev"    => $old_rating_dev,
	"new_rating_dev"    => $new_rating_dev,
      };
    }

    # If the STS file did not have rating deviations, try to
    # get the rating deviations from the .ST4 file, if one exists
    my $used_st4_file = 0;
    if (!$sts_has_rds && -f $st4_file)
    {
      $used_st4_file = 1;
      my $begin_rd_captures = 0;
      open my $st4_fh, '<', $st4_file or die "Could not open file '$st4_file': $!";
      my %player_rds;
      while (my $line = <$st4_fh>)
      {
        if ($line =~ /\+-/)
        {
          $begin_rd_captures++;
        }
        if ($begin_rd_captures >= 2 && $line =~ /^\|.\w+\s+([^\|]+)\|[^\|]*\|[^\|]*\|[^\|]*\|([^\|]*)\|/)
	{
	  my $player_name = sanitize(convert_name($1));

	  my $old_rating_dev;
	  my $new_rating_dev;
          my $rds_string = $2;
          my @rd_values = split /\s+/, $rds_string;
          @rd_values = grep {$_} @rd_values;
          if (scalar @rd_values == 2)
          {
            $old_rating_dev = $rd_values[0];
            $new_rating_dev = $rd_values[1];
          }
	  else 
	  {
            format_error([
                           ["ERROR: ", "invalid number of rating deviation values"], 
                           ["File:  ", $st4_file], 
                           ["Name:  ", $player_name],
                           ["Line:  ", $line]
                         ]);
            die "SKIP: $filename";
	  }
	  $tournament_results->{$player_name}->{'old_rating_dev'} = $old_rating_dev;
	  $tournament_results->{$player_name}->{'new_rating_dev'} = $new_rating_dev;
          $st4_names{$player_name} = 1;
	}	
      }

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
          format_error([
                         ["ERROR:", "Missing division name"],
                         ["File: ", $tou_file],
                       ]);
          die "SKIP: $filename";
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
             format_error( [
                           ["ERROR:    ", "inconsistent number of tournament games"],
                           ["File:     ", $tou_file],
                           ["Division: ", $current_division_name],
                           ["Line:     ", $_]
                         ]);
            die "SKIP: $filename";         
        }

        for(my $i = 0; $i < $games_played; $i++)
        {
          my $opp_number  = pop @player_game_data;
          $opp_number =~ s/\D//g;
          my $score       = pop @player_game_data;
          my $real_score = $score;

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
            die "SKIP: $filename";
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
          unshift @games, [$score, $opp_number, $real_score];
        }

        my $player_name = join " ", @player_game_data;
        $player_name =~ s/^\s+|\s+$//g;

        # Convert possible alt name to real name

        $player_name = convert_name($player_name);
        my $pretty_player_name = make_pretty($player_name);
        $player_name = sanitize($player_name);
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
          die "SKIP: $filename";
        }

        if ($tou_names{$player_name})
        {
          # A player has switched divisions mid tournament
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

        if (!player_name_is_bye($player_name) && !$tournament_results->{$player_name})
        {
          format_error([
                         ["ERROR:", "Player name does not appear in corresponding .STS file"], 
                         ["Name: ", $player_name], 
                         ["File: ", $tou_file], 
                         ["Line: ", $_],
                       ]);
          die "SKIP: $filename";                
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
       die "SKIP: $filename";
     }
     
     if ($used_st4_file)
     {
       $failure_comp = compare_names(\%tou_names, \%st4_names);
       
       if ($failure_comp)
       {
       my $not_in_tou = $failure_comp->[0];
       my $not_in_st4  = $failure_comp->[1];
       
         format_error([
                        ["ERROR:                ", "names in the .tou and .ST4 files do not match" ],
                        ["File:                 ", $filename],
                        ["Missing in .tou:      ", $not_in_tou],
                        ["Missing in .ST4:      ", $not_in_st4]
                      ]);
         die "SKIP: $filename";
       }
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
        my $player_real_score = $player_games[$i]->[2];

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
          die "SKIP: $filename";
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
#          die "SKIP: $filename";
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
          die "SKIP: $filename";
        } 

        my $is_bye = player_name_is_bye($opp_name) || $opp_number == $player_number;



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
            $opp_score    = 0;
            if ($player_real_score > 2000)
            {
              $tournament_results->{$player_name}->{'byes'} += 1;
              $player_score = 1;
            }
            elsif ($player_real_score < 1000)
            {
              $player_score = -1;
            }
            else
            {
              $tournament_results->{$player_name}->{'byes'} += 0.5;
              $player_score = 0;
            }
          }
          else
          {
            $player_spreads->{$opp_name}    += $opp_score    - $player_score;
          }

          

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

          if ($is_bye)
          {
            $player_score = 0;
          }

          $player_spreads->{$player_name} += $player_score - $opp_score;

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
      die "SKIP: $filename";  
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
      die "SKIP: $filename";  
    }


    push @tournament_ids_to_convert_to_html, $tournament_id;

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
    # Position must be derived at this point
    my $failure = rank_tournament_results($tournament_results);
    if ($failure)
    {
      unshift @$failure, ["Files:  ", $filename];
      unshift @$failure, ["ERROR:  ", "Ranking tournament results failed"];
      format_error($failure);
      die "SKIP: $filename";
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
   
    foreach my $key (keys %$game_and_player_results_hashref)
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


    my $loaded_tournaments_table_name = Constants::LOADED_TOURNAMENTS_TABLE_NAME;
    $tournament_name =~ s/"//g;

    my $insert_processed_tou =
    "
      INSERT INTO $loaded_tournaments_table_name
      (name, filename)
      VALUES (\"$tournament_name\", \"$tou_file\")
    ";

    $dbh->do($insert_processed_tou, {"RaiseError" => 1});

  $dbh->commit();
  # end eval block
   };

   if ($@) {
    # Something went wrong parsing a tournament
    my $error = $@;
    $dbh->rollback();
    if ($error =~ /^SKIP: (.*)/) {
      # Planned skip (previously next filename)
      print "Skipping file $1 due to $error\n";
    } else {
    # Real error
    format_error([
      ["ERROR: ", "Transaction failed for file"],
      ["File: ", $filename],
      ["Error: ", $error]
    ]); 
    }
    next filename;
   }
  }

  # Update ratings for all players
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

  # Update p.rating to match the most recent tournament end_rating for each player.
  # Tournaments are not processed in chronological order, so the per-tournament
  # inline update may set p.rating to a stale value.  This bulk pass fixes that.
  my $update_ratings =
  "
  UPDATE $players_tn AS p
  JOIN (
    SELECT tr.player_id, tr.end_rating
    FROM tournament_results tr
    INNER JOIN (
      SELECT player_id, MAX(date) AS max_date
      FROM tournament_results
      WHERE end_rating IS NOT NULL
      GROUP BY player_id
    ) latest ON tr.player_id = latest.player_id AND tr.date = latest.max_date
    WHERE tr.end_rating IS NOT NULL
  ) latest_rating ON p.id = latest_rating.player_id
  SET p.rating = latest_rating.end_rating
  ";
  $dbh->do($update_ratings, {"RaiseError" => 1});

  # Also update last_played to match the actual latest tournament date
  my $update_last_played_bulk =
  "
  UPDATE $players_tn AS p
  JOIN (
    SELECT tr.player_id, MAX(tr.date) AS max_date
    FROM tournament_results tr
    GROUP BY tr.player_id
  ) latest ON p.id = latest.player_id
  SET p.last_played = latest.max_date
  ";
  $dbh->do($update_last_played_bulk, {"RaiseError" => 1});


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

  return \@tournament_ids_to_convert_to_html;
}

sub get_player_photo
{
  my $name = shift;

  $name =~ s/\s//g;

  $name = lc $name;

  my $filename = $photo_dir . "/" . $name . ".jpg";

  if (-e $filename)
  {
    return $name . ".jpg";
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

sub make_pretty
{
  my $name = shift;

  $name =~ s/_/ /g;

  return $name;
}

sub negative_one_if_false
{
  my $s = shift;
  if ($s)
  {
    return $s;
  }
  return -1;
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

    my $new_item = [$key, $tr->{'wins'}, $tr->{'spread'}, $tr->{'byes'}];

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
                           $b->[1] + $b->[3] <=> $a->[1] + $a->[3] ||
                           $b->[2] <=> $a->[2]
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
 
 foreach my $key (keys %{$hashref}) {
     my $val = defined $hashref->{$key} ? $hashref->{$key} : 'UNDEF';
 }

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
=cut


