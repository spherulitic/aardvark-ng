package TOU;

use strict;
use warnings;
use version; our $VERSION = qv('1');
use DBI;
use Data::Dumper;
use List::Util qw(max);
use Clone 'clone';
use Carp;
use English qw( -no_match_vars );

use lib './modules';
use lib './objects';

use Constants;
use Division;
use HTML;
use Result;
use Utils;

sub compare_sts_and_tou_names
{
  my $this = shift;

  my $tou_names = $this->{$TOU_PLAYER_NAMES};
  my $sts_names = $this->{$TOU_STS_PLAYER_NAMES};

  foreach my $key ( keys %{$sts_names} )
  {
    $tou_names->{$key} = 0;
  }

  my @nonbye_names
    = grep { !Utils::player_name_is_bye($_) } keys %{$tou_names};
  my $missing_from_sts = join q{,},
    sort grep { $tou_names->{$_} } @nonbye_names;

  if ($missing_from_sts)
  {
    # Covered by TC 9
    $this->set_error_report(
      Utils::format_error(
        [ [ 'ERROR',            'Names missing in the STS/STA file' ],
          [ 'File',             $this->{$TOU_FILENAME} ],
          [ 'Missing from STS', $missing_from_sts ]
        ]
      )
    );
  }
  return 1;
}

sub get_report
{
  my $this = shift;

  my $warning_report = $this->{$TOU_WARNING_REPORT};
  my $error_report   = $this->{$TOU_ERROR_REPORT};
  my $separator      = $EMPTY_STRING;

  if ( $warning_report && $error_report )
  {
    $separator = $NEWLINE;
  }

  return $warning_report . $separator . $error_report;
}

sub get_unblessed_ref
{
  my $obj = shift;

  my $ref_name = ref $obj;
  my $unblessed;

  if ( $ref_name eq 'ARRAY' )
  {
    $unblessed = [];
    for my $i ( 0 .. scalar @{$obj} - 1 )
    {
      $unblessed->[$i] = get_unblessed_ref( $obj->[$i] );
    }
  }
  elsif ($ref_name)
  {
    $unblessed = {};
    my @keys = keys %{$obj};

    if ( $ref_name eq 'TOU' )
    {
      @keys = @{$TOU_COMPARE_ORDER};
    }

    foreach my $i ( 0 .. scalar @keys - 1 )
    {
      my $key = $keys[$i];
      if ( !$UNBLESSED_IGNORE_KEYS->{$key} )
      {
        $unblessed->{$key} = get_unblessed_ref( $obj->{$key} );
      }
    }
  }
  else
  {
    $unblessed = $obj;
  }
  return $unblessed;
}

sub initialize
{
  my ( $this, $arg_ref ) = @_;

  my $dbh             = $arg_ref->{dbh};
  my $filename        = $arg_ref->{filename};
  my $player_data     = $arg_ref->{player_data};
  my $conversion_hash = $arg_ref->{conversion_hash};
  my $correct         = $arg_ref->{correct};

  my $tou = {};

  $tou->{$TOU_DBH}              = $dbh;
  $tou->{$TOU_FILENAME}         = $filename;
  $tou->{$TOU_REWRITE_FILENAME} = $filename . $TOU_REWRITE_EXTENSION;
  $tou->{$TOU_PLAYER_DATA}      = $player_data;
  $tou->{$TOU_CONVERSION_HASH}  = $conversion_hash;
  $tou->{$TOU_CORRECT}          = $correct;

  $tou->{$TOU_PLAYER_NAMES}     = {};
  $tou->{$TOU_STS_PLAYER_NAMES} = {};
  $tou->{$TOU_DIVISION_DATA}    = {};
  $tou->{$TOU_ERROR_REPORT}     = $EMPTY_STRING;
  $tou->{$TOU_LOADED}           = 0;
  $tou->{$TOU_PROCESSED}        = 0;
  $tou->{$TOU_REWRITE_NEEDED}   = 0;
  $tou->{$TOU_VALID}            = 1;
  $tou->{$TOU_WARNING_REPORT}   = $EMPTY_STRING;

  my $self = bless $tou, $this;
  return $self;
}

sub insert_as_processed
{
  my $this = shift;

  my $dbh             = $this->{$TOU_DBH};
  my $filename        = $this->{$TOU_FILENAME};
  my $tournament_name = $this->{$TOU_TOURNAMENT}->{name};

  my $loaded_tournaments_table_name = $LOADED_TOURNAMENTS_TABLE_NAME;
  $tournament_name =~ s/"//gxms;

  my $insert_processed_tou
    = "INSERT INTO $loaded_tournaments_table_name "
    . '(name, filename) '
    . "VALUES (\"$tournament_name\", \"$filename\")";

  $dbh->do( $insert_processed_tou, { RaiseError => 1 } );
  $this->{$TOU_LOADED} = 1;
  return 1;
}

sub is_loaded
{
  my $this = shift;
  return $this->{$TOU_LOADED};
}

sub is_processed
{
  my $this = shift;
  return $this->{$TOU_PROCESSED};
}

sub is_valid
{
  my $this = shift;
  return $this->{$TOU_VALID};
}

sub load
{
  my $this        = shift;
  my $player_data = shift;

  my $filename = $this->{$TOU_FILENAME};

  if ( !$this->is_valid() || $this->is_loaded() )
  {
    return 1;
  }

  my $dbh = $this->{$TOU_DBH};

  my $event      = $this->{$TOU_EVENT};
  my $tournament = $this->{$TOU_TOURNAMENT};
  my $divisions  = $this->{$TOU_DIVISION_DATA};

  my $players_tn            = $PLAYERS_TABLE_NAME;
  my $player_alt_names_tn   = $PLAYER_ALT_NAMES_TABLE_NAME;
  my $tournaments_tn        = $TOURNAMENTS_TABLE_NAME;
  my $events_tn             = $EVENTS_TABLE_NAME;
  my $divisions_tn          = $DIVISIONS_TABLE_NAME;
  my $games_tn              = $GAMES_TABLE_NAME;
  my $tournament_results_tn = $TOURNAMENT_RESULTS_TABLE_NAME;
  my $player_results_tn     = $PLAYER_RESULTS_TABLE_NAME;

  # Add to database top down so we can link up the foreign keys
  my $event_id = Utils::insert_hash_into_table( $dbh, $events_tn, $event );

  $tournament->{event_id} = $event_id;

  my $tournament_name = $tournament->{name};
  my $tournament_id
    = Utils::insert_hash_into_table( $dbh, $tournaments_tn, $tournament );

  my @division_keys = sort {
    $divisions->{$a}->{$DIVISION_NUMBER}
      <=> $divisions->{$b}->{$DIVISION_NUMBER}
  } keys %{$divisions};

  my $division_id = Utils::get_max_id_from_table( $dbh, $divisions_tn ) + 1;
  my $game_id     = Utils::get_max_id_from_table( $dbh, $games_tn ) + 1;

  my @division_list           = ();
  my @tournament_results_list = ();
  my @games_list              = ();
  my @results_list            = ();

  for my $i ( 0 .. scalar @division_keys - 1 )
  {
    my $key      = $division_keys[$i];
    my $division = $divisions->{$key};

    my $division_name = $division->{$DIVISION_NAME};

    push @division_list,
      {
      id            => $division_id,
      tournament_id => $tournament_id,
      name          => $division_name,
      length        => $divisions->{$key}->{$DIVISION_NUMBER_OF_ROUNDS},
      number        => $divisions->{$key}->{$DIVISION_NUMBER}
      };

    my $tournament_results = $division->{$DIVISION_TOURNAMENT_RESULTS};

    foreach my $tr ( @{$tournament_results} )
    {
      my $total_games = $tr->{wins} + $tr->{losses};
      Utils::add_games_to_existing_player( $dbh, $tr->{player_id},
        $total_games );
      $tr->{division_id} = $division_id;
      push @tournament_results_list, $tr;
    }

    my $gprs = $division->{$DIVISION_GAME_AND_PLAYER_RESULTS};

    # Sorting the keys has no effect on the final operational result,
    # but it makes testing easier
    foreach my $key ( sort keys %{$gprs} )
    {
      my $gpr     = $gprs->{$key};
      my $game    = $gpr->{game};
      my @results = @{ $gpr->{results} };

      $game->{division_id} = $division_id;
      $game->{id}          = $game_id;
      push @games_list, $game;

      foreach my $result (@results)
      {
        $result->{game_id} = $game_id;
        push @results_list, $result;
      }
      $game_id++;
    }
    $division_id++;
  }

  Utils::insert_hash_list_into_table( $dbh, $divisions_tn, \@division_list );
  Utils::insert_hash_list_into_table( $dbh, $tournament_results_tn,
    \@tournament_results_list );
  Utils::insert_hash_list_into_table( $dbh, $games_tn, \@games_list );
  Utils::insert_hash_list_into_table( $dbh, $player_results_tn,
    \@results_list );
  $this->insert_as_processed();

  return 1;
}

sub new
{
  my ( $tou_type, $arg_ref ) = @_;

  my $dbh                   = $arg_ref->{dbh};
  my $filename              = $arg_ref->{filename};
  my $alt_names_hash        = $arg_ref->{alt_names_hash};
  my $deceased_players_hash = $arg_ref->{deceased_players_hash};
  my $player_data           = $arg_ref->{player_data};
  my $correct               = $arg_ref->{correct};

  my $this = $tou_type->initialize(
    { dbh             => $dbh,
      filename        => $filename,
      player_data     => $player_data,
      conversion_hash => $alt_names_hash,
      correct         => $correct,
    }
  );

  my $tou_file_extension = $TOU_FILE_EXTENSION;
  my $sts_file_extension = $STS_FILE_EXTENSION;
  my $sta_file_extension = $STA_FILE_EXTENSION;

  my $player_names_to_ids = {};

  my @tournament_ids_to_convert_to_html = ();

  if ( !-e $filename )
  {
    # Covered by TC 1
    $this->set_error_report(
      Utils::format_error(
        [ [ 'ERROR', 'Missing .tou file' ], [ 'File', $filename ] ]
      )
    );
    return $this;
  }

  if ( Utils::tou_is_loaded( $dbh, $filename ) )
  {
    $this->{$TOU_WARNING_REPORT} .= Utils::format_error(
      [ [ 'WARNING', 'TOU file was already loaded' ], [ 'File', $filename ],
      ]
    );
    $this->{$TOU_LOADED} = 1;
    return $this;
  }

  my $noext_filename = $filename;
  $noext_filename =~ s/[.](.*)$//xms;

  my $sts_file = $noext_filename . $sts_file_extension;
  my $sta_file = $noext_filename . $sta_file_extension;

  if ( !( -e $sts_file || -e $sta_file ) )
  {
    # Covered by TC 2
    $this->set_error_report(
      Utils::format_error(
        [ [ 'ERROR', 'Missing .STS or .STA file' ], [ 'File', $filename ] ]
      )
    );
    return $this;
  }

  my ( $date, $tournament_name ) = Utils::parse_tou_header($filename);

  if ( !$date || !$tournament_name )
  {
    # Covered by TC 3
    $this->set_error_report(
      Utils::format_error(
        [ [ 'ERROR', 'Malformed .tou header' ], [ 'File', $filename ], ]
      )
    );
    return $this;
  }

  my $event = {
    start_date => $date,
    end_date   => $date,

    # "link"       => "link to event",
    # "sponsor"    => "sponsor of event",
    # "country"    => "AAA",
    # "location"   => "location of event",
  };

  my ( $trigraph, $trigraph_warnings )
    = Utils::convert_trigraph( Utils::get_country_from_filename($filename) );

  $this->{$TOU_WARNING_REPORT} .= $trigraph_warnings;

  my $tournament = {
    start_date => $date,              # This is changed later
    end_date   => $date,              # This is changed later
    name       => $tournament_name,
    country    => $trigraph,

    # "td"     => "director of tournament",
  };

  $this->{$TOU_EVENT}      = $event;
  $this->{$TOU_TOURNAMENT} = $tournament;

  my $stsa_data = $this->process_sts(
    { dbh                   => $dbh,
      date                  => $date,
      sts_file              => $noext_filename . $sts_file_extension,
      sta_file              => $noext_filename . $sta_file_extension,
      deceased_players_hash => $deceased_players_hash
    }
  );
  $this->process($stsa_data);
  return $this;
}

sub new_division
{
  my ( $this, $arg_ref ) = @_;

  my $filename                = $this->{$TOU_FILENAME};
  my $current_division_name   = $arg_ref->{current_division_name};
  my $current_division_number = $arg_ref->{current_division_number};
  my $players                 = $arg_ref->{players};
  my $game_data               = $arg_ref->{game_data};
  my $stsa_data               = $arg_ref->{stsa_data};

  my $division = Division->new(
    { filename        => $filename,
      division_name   => $current_division_name,
      division_number => $current_division_number++,
      players         => $players,
      game_data       => $game_data
    }
  );

  $division->process( $this->{$TOU_CORRECT} );
  return $this->process_division( $division, $stsa_data );
}

sub parse_sts_line
{
  my ( $this, $arg_ref ) = @_;

  my $is_sts       = $arg_ref->{is_sts};
  my $sts_line     = $arg_ref->{sts_line};
  my $sts_metadata = $arg_ref->{sts_metadata};

  my $filename = $this->{$TOU_FILENAME};

  # These are common between both .STS and .STA files
  my $player_country;
  my $player_name;
  my $start_rating;
  my $end_rating;

  my $expected_wins;
  my $old_world_rank;
  my $new_world_rank;
  my $old_national_rank;
  my $new_national_rank;

  # Player info must be extracted differently if the file is .STS as
  # opposed to .STA
  if ($is_sts)
  {
    my @player_items = split /,/xms, $sts_line;
    $player_country    = $player_items[$STS_PLAYER_COUNTRY_INDEX];
    $player_name       = $player_items[$STS_PLAYER_NAME_INDEX];
    $expected_wins     = $player_items[$STS_EXPECTED_WINS_INDEX];
    $start_rating      = $player_items[$STS_START_RATING_INDEX];
    $end_rating        = $player_items[$STS_END_RATING_INDEX];
    $old_world_rank    = $player_items[$STS_OLD_WORLD_RANK_INDEX];
    $new_world_rank    = $player_items[$STS_NEW_WORLD_RANK_INDEX];
    $old_national_rank = $player_items[$STS_OLD_NATIONAL_RANK_INDEX];
    $new_national_rank = $player_items[$STS_NEW_NATIONAL_RANK_INDEX];
  }
  else
  {
    if ( $sts_line =~ /[+]-/xms )
    {
      $sts_metadata->{begin_player_captures}++;
    }

    # Remove parentheses from the line because
    # they were causing problems
    $sts_line =~ s/[(]|[)]/[ ]/gxms;

    my $is_new_player_pattern  = '(.)';
    my $player_country_pattern = '(\\w+)';
    my $player_name_pattern    = '([^|]+)';
    my $world_ranks_pattern    = '([^|]*)';
    my $national_ranks_pattern = '([^|]*)';
    my $wins_pattern           = '([^|]*)';
    my $ratings_pattern        = '([^|]*)';

    if (
         $sts_metadata->{begin_player_captures} >= 2
      && $sts_line =~ m{^[|]$is_new_player_pattern
              $player_country_pattern\s+
              $player_name_pattern[|]
              $world_ranks_pattern[|]
              $national_ranks_pattern[|]
              $wins_pattern[|]
              $ratings_pattern[|]
         }xms
      )
    {
      $sts_metadata->{is_valid} = 1;

      my $is_new_player = $1;    # Unused for now
      $player_country = $2;
      $player_name    = $3;
      my $world_ranks_string    = $4;
      my $national_ranks_string = $5;
      my $wins_string           = $6;
      my $ratings_change_string = $7;

      $is_new_player =~ s/^\s+|\s+$//gxms;
      $player_country =~ s/^\s+|\s+$//gxms;
      $player_name =~ s/^\s+|\s+$//gxms;
      $world_ranks_string =~ s/^\s+|\s+$//gxms;
      $national_ranks_string =~ s/^\s+|\s+$//gxms;
      $wins_string =~ s/^\s+|\s+$//gxms;
      $ratings_change_string =~ s/^\s+|\s+$//gxms;

      my @nranks = split /\s+/xms, $national_ranks_string;
      @nranks = grep {$_} @nranks;
      my $nranks_length = scalar @nranks;

      if ( $nranks_length > 2 )
      {
        # Covered by TC 4
        $this->set_error_report(
          Utils::format_error(
            [ [ 'ERROR', 'Invalid number of items in STA first rank column' ],
              [ 'TOU File', $filename ],
              [ 'Line',     $sts_line ],
            ]
          )
        );
        return { parse_failed => 1 };
      }

      my %nrank_changes = (
        0 => [ undef,      undef ],
        1 => [ undef,      $nranks[0] ],
        2 => [ $nranks[0], $nranks[1] ],
      );

      $old_national_rank = $nrank_changes{$nranks_length}->[0];
      $new_national_rank = $nrank_changes{$nranks_length}->[1];

      my @wranks = split /\s+/xms, $world_ranks_string;
      @wranks = grep {$_} @wranks;
      my $wranks_length = scalar @wranks;

      if ( scalar @wranks > 2 )
      {
        # Covered by TC 5
        $this->set_error_report(
          Utils::format_error(
            [ [ 'ERROR', 'Invalid number of items in STA second rank column'
              ],
              [ 'TOU File', $filename ],
              [ 'Line',     $sts_line ],
            ]
          )
        );
        return { parse_failed => 1 };
      }

      my %wrank_changes = (
        0 => [ undef,      undef ],
        1 => [ undef,      $wranks[0] ],
        2 => [ $wranks[0], $wranks[1] ],
      );

      $old_world_rank = $wrank_changes{$wranks_length}->[0];
      $new_world_rank = $wrank_changes{$wranks_length}->[1];

      my @ewins = split /\s+/xms, $wins_string;
      @ewins = grep {$_} @ewins;
      my $ewins_length = scalar @ewins;
      if ( $ewins_length > 2 )
      {
        # Covered by TC 6
        $this->set_error_report(
          Utils::format_error(
            [ [ 'ERROR',    'Invalid number of items in STA wins column' ],
              [ 'TOU File', $filename ],
              [ 'Line',     $sts_line ],
            ]
          )
        );
        return { parse_failed => 1 };
      }

      my @ewins_possibilities = ( undef, undef, $ewins[0] );

      $expected_wins = $ewins_possibilities[$ewins_length];

      my @rchanges = split /\D+/xms, $ratings_change_string;
      @rchanges = grep {$_} @rchanges;
      my $num_rchange_items = scalar @rchanges;

      if ( $num_rchange_items > $STA_MAX_RATING_ITEMS )
      {
        # Covered by TC 7
        $this->set_error_report(
          Utils::format_error(
            [ [ 'ERROR',
                'Invalid number of items in STA ratings column: '
                  . $num_rchange_items
              ],
              [ 'TOU File', $filename ],
              [ 'Line',     $sts_line ],
            ]
          )
        );
        return { parse_failed => 1 };
      }

      my %rating_changes = (
        0                     => [ undef,        undef ],
        1                     => [ undef,        $rchanges[0] ],
        2                     => [ $rchanges[0], $rchanges[1] ],
        $STA_MAX_RATING_ITEMS => [ $rchanges[0], $rchanges[2] ],
      );

      $start_rating = $rating_changes{$num_rchange_items}->[0];
      $end_rating   = $rating_changes{$num_rchange_items}->[1];
    }
    else
    {
      $sts_metadata->{is_valid} = 0;
    }
  }
  return {
    player_country    => $player_country,
    player_name       => $player_name,
    start_rating      => $start_rating,
    end_rating        => $end_rating,
    expected_wins     => $expected_wins,
    old_world_rank    => $old_world_rank,
    new_world_rank    => $new_world_rank,
    old_national_rank => $old_national_rank,
    new_national_rank => $new_national_rank,
  };
}

sub process
{
  my $this      = shift;
  my $stsa_data = shift;

  if ( !$this->{$TOU_VALID} )
  {
    return;
  }

  my $filename                = $this->{$TOU_FILENAME};
  my @players                 = ();
  my @game_data               = ();
  my $current_division_number = 1;
  my $current_division_name   = $EMPTY_STRING;

  my $at_end = 0;

  my @tou_lines = Utils::write_file_to_array($filename);

  # Ignore the header line because it has already
  # been processed
  shift @tou_lines;

  while (@tou_lines)
  {
    my $tou_line = shift @tou_lines;
    $at_end = $tou_line =~ /END OF FILE/ms;
    if ( $tou_line =~ /^[*](.*)/xms || $at_end )
    {
      # If this is the end of the division, verify the division
      if (@players)
      {
        if (
          !$this->new_division(
            { current_division_name   => $current_division_name,
              current_division_number => $current_division_number++,
              players                 => Clone::clone( \@players ),
              game_data               => Clone::clone( \@game_data ),
              stsa_data               => $stsa_data,
            }
          )
          )
        {
          return;
        }
      }

      # Prepare loop for a new division
      if ( !$at_end )
      {
        @players               = ();
        @game_data             = ();
        $current_division_name = $1;
        $current_division_name =~ s/^\s+|\s+$//gxms;
      }
    }
    elsif ( $tou_line =~ /\w\s+(\d+\s+[+]?\d+(\s+|$))+/xms )
    {
      if ( !$current_division_number || !$current_division_name )
      {
        # Covered by TC 10
        $this->set_error_report(
          Utils::format_error(
            [ [ 'ERROR', 'Missing division name' ], [ 'File', $filename ], ]
          )
        );
        return;
      }

      # If a winning negative score is listed, correct it by adding 2000
      # to ensure compliance with the .tou format
      if ( $tou_line =~ /\s2\s?([-]\d+)/xms )
      {
        $this->{$TOU_WARNING_REPORT} .= Utils::format_error(
          [ [ 'WARNING',      'Converting negative winning score' ],
            [ 'File',         $filename ],
            [ 'Line',         $tou_line . $NEWLINE ],
            [ 'Rewritten to', $this->{$TOU_REWRITE_FILENAME} ]
          ]
        );
        my $neg_score = $1 + $TOU_BASE_WINNING_SCORE;
        $tou_line =~ s/2\s?[-]\d+/$neg_score/gxms;
        $this->{$TOU_REWRITE_NEEDED} = 1;
      }

      my @player_game_data = split /\s+/xms, $tou_line;
      my $games_played = () = $tou_line =~ /([-]?\d+\s+[+]?\d+(?:\s+|$))/gxms;
      my @games = ();

      for my $i ( 0 .. $games_played - 1 )
      {
        my $opp_number      = pop @player_game_data;
        my $player_is_first = 0;
        if ( substr( $opp_number, 0, 1 ) eq q{+} )
        {
          $player_is_first = 1;
        }
        $opp_number =~ s/\D//gxms;
        my $score = pop @player_game_data;

        if ( $opp_number =~ /\D/xms || $score !~ /^[-]?\d+$/xms )
        {
          # Covered by TC 11
          $this->set_error_report(
            Utils::format_error(
              [ [ 'ERROR', 'Malformed opponent number or player score' ],
                [ 'File',  $filename ],
                [ 'Opponent number', $opp_number ],
                [ 'Player score',    $score ],
                [ 'Line',            $tou_line ]
              ]
            )
          );
          return;
        }

        # Convert the 1-indexed opp number in the TOU to the
        # 0-indexed opp number in the Division and Result objects
        unshift @games,
          Result->new( $score, $opp_number - 1, $player_is_first );
      }

      my $player_name = join q{ }, @player_game_data;
      $player_name =~ s/^\s+|\s+$//gxms;
      $player_name
        = Utils::convert_name( $player_name, $this->{$TOU_CONVERSION_HASH} );

      if ( Utils::player_name_is_bye($player_name) )
      {
        # Covered by TC 17
        $this->{$TOU_WARNING_REPORT} .= Utils::format_error(
          [ [ 'WARNING', 'Player as bye detected in TOU file' ],
            [ 'File',    $filename ],
            [ 'Line',    $tou_line ]
          ]
        );
      }

      push @players,   $player_name;
      push @game_data, \@games;
    }
  }

  $this->compare_sts_and_tou_names();
  $this->{$TOU_PROCESSED} = 1;
  $this->rewrite();
  return 1;
}

sub process_division
{
  my $this      = shift;
  my $division  = shift;
  my $stsa_data = shift;

  my $verification_report = $division->{$DIVISION_VERIFICATION_REPORT};

  if ( !$division->is_valid() )
  {
    $this->{$TOU_ERROR_REPORT} = $verification_report;
    $this->{$TOU_VALID}        = 0;
    return;
  }

  if ( $division->{$DIVISION_CORRECTED} )
  {
    $this->{$TOU_REWRITE_NEEDED} = 1;
  }

  $this->{$TOU_WARNING_REPORT}
    .= $verification_report ? $verification_report : $EMPTY_STRING;

  my $number_of_rounds = $division->{$DIVISION_NUMBER_OF_ROUNDS};
  my @players          = @{ $division->{$DIVISION_PLAYERS} };
  my $number_of_rows   = scalar @players;

  my @tournament_results      = ();
  my $game_and_player_results = {};
  my $player_data_hash        = $this->{$TOU_PLAYER_DATA};

  my $spread   = 0;
  my $wins     = 0;
  my $losses   = 0;
  my $byes     = 0;
  my $bye_wins = 0;

  for my $row ( 0 .. $number_of_rows - 1 )
  {
    my $player_data
      = $player_data_hash->{ Utils::sanitize( $players[$row] ) };
    my $player_name           = $players[$row];
    my $sanitized_player_name = Utils::sanitize($player_name);
    my $player_id             = $player_data->[1];

    $this->{$TOU_PLAYER_NAMES}->{$sanitized_player_name} = 1;

    if ( !$player_id )
    {
      # In this case a player is missing from the STS/STA
      # file and the error will have already been caught
      next;
    }

    my $tournament_result = {
      player_id         => $player_id,
      player_name       => $player_name,
      position          => 0,
      wins              => 0,
      losses            => 0,
      byes              => 0,
      bye_wins          => 0,
      spread            => 0,
      new_world_rank    => $stsa_data->{$player_id}->{new_world_rank},
      old_world_rank    => $stsa_data->{$player_id}->{old_world_rank},
      old_national_rank => $stsa_data->{$player_id}->{old_national_rank},
      new_national_rank => $stsa_data->{$player_id}->{new_national_rank},
      expected_wins     => $stsa_data->{$player_id}->{expected_wins},
      start_rating      => $stsa_data->{$player_id}->{start_rating},
      end_rating        => $stsa_data->{$player_id}->{end_rating},
      date              => $this->{$TOU_TOURNAMENT}->{start_date},
      tournament_name   => $this->{$TOU_TOURNAMENT}->{name}
    };

    for my $round ( 0 .. $number_of_rounds - 1 )
    {
      my $player_result = $division->get_matrix_index( $row, $round );
      my $opponent_number = $player_result->{$RESULT_OPPONENT_NUMBER};
      $tournament_result->{wins}     += $player_result->{$RESULT_WINS};
      $tournament_result->{losses}   += $player_result->{$RESULT_LOSSES};
      $tournament_result->{byes}     += $player_result->{$RESULT_BYES};
      $tournament_result->{bye_wins} += $player_result->{$RESULT_BYE_WINS};
      $tournament_result->{spread}   += $player_result->{$RESULT_SPREAD};
      $player_result->add_to_gpr( $game_and_player_results, $player_id,
        $player_name );
    }
    push @tournament_results, $tournament_result;
  }

  @tournament_results
    = Utils::rank_tournament_results( \@tournament_results );

  $division->{$DIVISION_TOURNAMENT_RESULTS}      = \@tournament_results;
  $division->{$DIVISION_GAME_AND_PLAYER_RESULTS} = $game_and_player_results;
  $this->{$TOU_DIVISION_DATA}->{ $division->{$DIVISION_NAME} } = $division;

  return 1;
}

sub process_sts
{
  my ( $this, $arg_ref ) = @_;

  my $dbh                   = $arg_ref->{dbh};
  my $date                  = $arg_ref->{date};
  my $sts_file              = $arg_ref->{sts_file};
  my $sta_file              = $arg_ref->{sta_file};
  my $deceased_players_hash = $arg_ref->{deceased_players_hash};

  my $player_data    = $this->{$TOU_PLAYER_DATA};
  my $alt_names_hash = $this->{$TOU_CONVERSION_HASH};

  # This code prefers to use the .STS file

  my $sts_or_sta_file = $sts_file;
  my $is_sts          = 1;
  if ( !-e $sts_file )
  {
    $sts_or_sta_file = $sta_file;
    $is_sts          = 0;
  }

  my $sts_metadata = { begin_player_captures => 0, };

  my $stsa_data = {};

  # Read the .STS file
  my @sts_lines = Utils::write_file_to_array($sts_or_sta_file);
  while (@sts_lines)
  {
    my $sts_line = shift @sts_lines;
    chomp $sts_line;

    # Remove trailing and leading whitespace from line
    $sts_line =~ s/^\s+|\s+$//gxms;

    if ( !$sts_line ) { next; }

    my $sts_line_extraction = $this->parse_sts_line(
      { is_sts       => $is_sts,
        sts_line     => $sts_line,
        sts_metadata => $sts_metadata,
      }
    );
    if ( $sts_line_extraction->{parse_failed} )
    {
      return;
    }

    # If the file is an STA file and the line is
    # not a player line then skip it
    if ( !$is_sts && !$sts_metadata->{is_valid} )
    {
      next;
    }

    my $player_name = $sts_line_extraction->{player_name};

    if ( Utils::player_name_is_bye($player_name) )
    {
      # Not covered by any TC
      $this->{$TOU_WARNING_REPORT} .= Utils::format_error(
        [ [ 'WARNING', 'Player as bye detected in STS/STA file' ],
          [ 'File',    $sts_or_sta_file ],
          [ 'Line',    $sts_line ]
        ]
      );
      next;
    }

    # These are common between both .STS and .STA files
    my $player_country    = $sts_line_extraction->{player_country};
    my $start_rating      = $sts_line_extraction->{start_rating};
    my $end_rating        = $sts_line_extraction->{end_rating};
    my $expected_wins     = $sts_line_extraction->{expected_wins};
    my $old_world_rank    = $sts_line_extraction->{old_world_rank};
    my $new_world_rank    = $sts_line_extraction->{new_world_rank};
    my $old_national_rank = $sts_line_extraction->{old_national_rank};
    my $new_national_rank = $sts_line_extraction->{new_national_rank};

    $expected_wins     = Utils::negative_one_if_false($expected_wins);
    $start_rating      = Utils::negative_one_if_false($start_rating);
    $old_world_rank    = Utils::negative_one_if_false($old_world_rank);
    $new_world_rank    = Utils::negative_one_if_false($new_world_rank);
    $old_national_rank = Utils::negative_one_if_false($old_national_rank);
    $new_national_rank = Utils::negative_one_if_false($new_national_rank);

    $player_country =~ s/^\s+|\s+$//gxms;
    $player_name =~ s/^\s+|\s+$//gxms;
    $new_world_rank =~ s/^\s+|\s+$//gxms;
    $old_world_rank =~ s/^\s+|\s+$//gxms;
    $old_national_rank =~ s/^\s+|\s+$//gxms;
    $new_national_rank =~ s/^\s+|\s+$//gxms;
    $expected_wins =~ s/^\s+|\s+$//gxms;
    $start_rating =~ s/^\s+|\s+$//gxms;
    $end_rating =~ s/^\s+|\s+$//gxms;

    my @required_captures = grep { !$_ }
      ( $player_country, $player_name, $start_rating, $end_rating );

    if (@required_captures)
    {
      # Covered by TC 8
      $this->set_error_report(
        Utils::format_error(
          [ [ 'ERROR', 'Required values are uncaptured' ],
            [ 'File',  $sts_or_sta_file ],
            [ 'Line',  $sts_line ]
          ]
        )
      );
      return $this;
    }

    # Some country trigraphs in the old aardvark are incorrect
    # and need to be converted to valid ISO 3166 trigraphs
    my $trigraph_warnings;
    ( $player_country, $trigraph_warnings )
      = Utils::convert_trigraph($player_country);

    $this->{$TOU_WARNING_REPORT} .= $trigraph_warnings;

    # Convert possible alt name to correct name
    $player_name = Utils::convert_name( $player_name, $alt_names_hash );
    my $pretty_player_name = Utils::make_pretty($player_name);
    $player_name = Utils::sanitize($player_name);

    $this->{$TOU_STS_PLAYER_NAMES}->{$player_name} = 1;

    # Search for this player in the players table
    # If this player already exists in the database, we will need their
    # id for the table to add them properly

    my $player_query
      = 'SELECT id, country, last_played '
      . "FROM $PLAYERS_TABLE_NAME "
      . "WHERE BINARY name=\"$pretty_player_name\"";

    my @player_query_result
      = $dbh->selectrow_array( $player_query, { RaiseError => 1 } );

    my $player_id;

    my $deceased_status
      = $deceased_players_hash->{$pretty_player_name} ? 1 : 0;

    my $player_photo = Utils::get_player_photo($player_name);

    if ( !@player_query_result )    # Player does not exist
    {
      $player_id = Utils::insert_hash_into_table(
        $dbh,
        $PLAYERS_TABLE_NAME,
        { name        => $pretty_player_name,
          country     => $player_country,
          photo       => $player_photo,
          suspended   => 0,
          deceased    => $deceased_status,
          total_games => 0,
          last_played => $date,
          rating      => $end_rating
        }
      );
    }
    else
    {

      $player_id = shift @player_query_result;
      my $existing_country   = shift @player_query_result;
      my $player_last_played = shift @player_query_result;

      TOU::update_rating_and_country(
        { dbh                => $dbh,
          player_id          => $player_id,
          existing_country   => $existing_country,
          player_last_played => $player_last_played,
          date               => $date,
          player_country     => $player_country,
          end_rating         => $end_rating,
        }

      );
    }
    $player_data->{$player_name} = [ $pretty_player_name, $player_id ];
    $stsa_data->{$player_id} = {
      new_world_rank    => $new_world_rank,
      old_world_rank    => $old_world_rank,
      old_national_rank => $old_national_rank,
      new_national_rank => $new_national_rank,
      expected_wins     => $expected_wins,
      start_rating      => $start_rating,
      end_rating        => $end_rating,
    };
  }
  return $stsa_data;
}

sub rewrite
{
  my $this = shift;
  if ( $this->is_valid() && $this->rewrite_needed() && $this->is_processed() )
  {
    Utils::write_string_to_file( $this->to_string(),
      $this->{$TOU_REWRITE_FILENAME} );
  }
  return 1;
}

sub rewrite_needed
{
  my $this = shift;
  return $this->{$TOU_REWRITE_NEEDED};
}

sub set_error_report
{
  my $this         = shift;
  my $error_report = shift;
  $this->{$TOU_ERROR_REPORT} = $error_report;
  $this->{$TOU_VALID}        = 0;
  return 1;
}

sub to_string
{
  my $this = shift;

  my $event      = $this->{$TOU_EVENT};
  my $tournament = $this->{$TOU_TOURNAMENT};
  my $divisions  = $this->{$TOU_DIVISION_DATA};

  my $tournament_name = $tournament->{name};
  my $tournament_date = $tournament->{start_date};

  $tournament_date =~ /(\d\d\d\d)(\d\d)(\d\d)/xms;

  my $tou_date_format = "$3.$2.$1";

  my $tou_string = "*M$tou_date_format $tournament_name$NEWLINE";

  my @division_keys = sort {
    $divisions->{$a}->{$DIVISION_NUMBER}
      <=> $divisions->{$b}->{$DIVISION_NUMBER}
  } keys %{$divisions};

  for my $i ( 0 .. scalar @division_keys - 1 )
  {
    $tou_string .= $divisions->{ $division_keys[$i] }->to_string();
  }

  $tou_string .= '*** END OF FILE ***';
  return $tou_string;
}

sub update_rating_and_country
{
  my $arg_ref = shift;

  my $dbh                = $arg_ref->{dbh};
  my $player_id          = $arg_ref->{player_id};
  my $existing_country   = $arg_ref->{existing_country};
  my $player_last_played = $arg_ref->{player_last_played};
  my $date               = $arg_ref->{date};
  my $player_country     = $arg_ref->{player_country};
  my $end_rating         = $arg_ref->{end_rating};

  my $player_query_result_ref = shift;

  $player_last_played =~ s/\D//gxms;

  my $newer_tourney_cond = $player_last_played < $date;

  my $no_country_cond = !$existing_country
    && $player_country;

  my $changed_to_newer_country_cond
    = $existing_country
    && $player_country
    && $existing_country ne $player_country
    && $player_last_played < $date;

  my $changed_country_cond
    = $existing_country
    && $player_country
    && $existing_country ne $player_country;

  if ($newer_tourney_cond)
  {
    Utils::update_record_by_id( $dbh, $PLAYERS_TABLE_NAME, $player_id,
      { last_played => $date, rating => $end_rating } );
  }
  if ( $no_country_cond || $changed_to_newer_country_cond )
  {
    Utils::update_record_by_id( $dbh, $PLAYERS_TABLE_NAME, $player_id,
      { country => $player_country } );
  }
  return 1;
}

1;
