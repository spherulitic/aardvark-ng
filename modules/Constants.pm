#!/usr/bin/perl

package Constants;

use warnings;
use strict;

use constant INPUT_DIR           => 'inputs';
use constant LOG_DIR             => 'logs';
use constant MODULES_DIR         => 'modules';
use constant SCRIPTS_DIR         => 'scripts';
use constant HTML_DIR            => 'html';
use constant PLAYER_HTML_DIR     => 'players';
use constant TOURNAMENT_HTML_DIR => 'tournaments';
use constant RANKINGS_HTML_DIR   => 'rankings';
use constant FULL_RANKINGS_NAME  => 'full_rankings';

use constant HTML_HEADER => "Content-type: text/html\n\n";

use constant DEFAULT_WORKING_DIR            => "/srv/dev/aardvark";
use constant DEFAULT_YEAR_REGEX             => '^\d\d\d\d$';
use constant DEFAULT_COUNTRY_TRIGRAPH_REGEX => '^\w\w\w$';
use constant DEFAULT_FILE_REGEX             => '.tou';

use constant DEFAULT_BACKUP_DIR             => "/home/jcastellano/aardvark-ng/backups/backup_original";

use constant DATABASE_NAME      => 'wespa';
use constant DATABASE_HOST_NAME => 'localhost';
use constant DATABASE_USER_NAME => 'wespa';
use constant DATABASE_PASSWORD  => 'nigeltheking';

use constant TOU_FILE_EXTENSION => '.tou';
use constant STS_FILE_EXTENSION => '.STS';
use constant STA_FILE_EXTENSION => '.STA';

use constant PLAYERS_TABLE_NAME            => 'players';
use constant PLAYER_ALT_NAMES_TABLE_NAME   => 'player_alt_names';
use constant TOURNAMENTS_TABLE_NAME        => 'tournaments';
use constant EVENTS_TABLE_NAME             => 'events';
use constant DIVISIONS_TABLE_NAME          => 'divisions';
use constant GAMES_TABLE_NAME              => 'games';
use constant TOURNAMENT_RESULTS_TABLE_NAME => 'tournament_results';
use constant PLAYER_RESULTS_TABLE_NAME     => 'player_results';
use constant LEXICONS_TABLE_NAME           => 'lexicons';

use constant MASTER_RATINGS_LIST        => 'rating.dat';
use constant NOT_IN_MASTER_RATINGS_LIST => 'not_in_ratings_list.log';

use constant REMOVED_NAMES_FILE           => 'removed_names.log';
use constant DUPLICATE_NAMES_FILE         => 'duplicate_names.log';
use constant INCORRECT_NAME_MAPPINGS_FILE => 'incorrect_name_mappings.log';
use constant INPUT_MERGE_FILE             => 'duplicates.txt';
use constant DECEASED_PLAYERS             => 'removed_people.txt';

use constant PROVISIONAL_GAMES_MAX      => 50;
use constant CURRENT_GAMES_MIN          => 40;
use constant PHOTO_DIR                  => 'icons';

use constant DEFAULT_BYE_SCORE          => 1350;

use constant TABLES =>
{
  Constants::PLAYERS_TABLE_NAME   => [
                            "id                 INT NOT NULL AUTO_INCREMENT",
                            "name               VARCHAR(255)",
                            "country            VARCHAR(3)",
                            "photo              VARCHAR(255)",
                            "suspended          BOOLEAN",
                            "deceased           BOOLEAN",
                            "current            BOOLEAN",
                            "provisional        BOOLEAN",
                            "total_games        INT",
                            "last_played        DATE",
                            "rating             INT",

                            "PRIMARY KEY (id)"
                          ],
  Constants::PLAYER_ALT_NAMES_TABLE_NAME   => [
                            "id                 INT NOT NULL AUTO_INCREMENT",
                            "alt_name           VARCHAR(255)",
                            "player_id          INT NOT NULL",

                            "PRIMARY KEY (id)",
                            "FOREIGN KEY (player_id) REFERENCES players(id)"
                          ],
  Constants::TOURNAMENTS_TABLE_NAME => [
                            "id         INT NOT NULL AUTO_INCREMENT",
                            "event_id   INT NOT NULL",
                            "td         VARCHAR(255)",
                            "start_date DATE",
                            "end_date   DATE",

                            "PRIMARY KEY (id)",
                            "FOREIGN KEY (event_id) REFERENCES events(id)"
                          ],
  Constants::EVENTS_TABLE_NAME   => [
                            "id         INT NOT NULL AUTO_INCREMENT",
                            "start_date DATE",
                            "end_date   DATE",
                            "link       VARCHAR(255)",
                            "sponsor    VARCHAR(255)",
                            "country    VARCHAR(3)",
                            "location   VARCHAR(255)",

                            "PRIMARY KEY (id)"
                          ],
  Constants::DIVISIONS_TABLE_NAME =>          [
                            "id              INT NOT NULL AUTO_INCREMENT",
                            "tournament_id   INT NOT NULL",
                            "name            VARCHAR(255)",
                            "length          INT",
                            "number          INT",

                            "PRIMARY KEY (id)",
                            "FOREIGN KEY (tournament_id) REFERENCES tournaments(id)"
                          ],
  Constants::GAMES_TABLE_NAME     => [
                            "id           INT NOT NULL AUTO_INCREMENT",
                            "division_id  INT NOT NULL",
                            "round        INT",
                            "lexicon_id   INT NOT NULL",
                            "gcg_filename VARCHAR(255)",

                            "PRIMARY KEY (id)",
                            "FOREIGN KEY (division_id) REFERENCES divisions(id)",
                            "FOREIGN KEY (lexicon_id)  REFERENCES lexicons(id)"
                          ],
  Constants::TOURNAMENT_RESULTS_TABLE_NAME => [
                            "id             INT NOT NULL AUTO_INCREMENT",
                            "division_id    INT NOT NULL",
                            "player_id      INT NOT NULL",
                            "player_name    VARCHAR(255)",
                            "position       INT",
                            "wins           FLOAT",
                            "losses         FLOAT",
                            "byes           INT",
                            "spread         INT",
                            "prize_money    INT",
                            "prize_currency VARCHAR(255)",
                            "prize_ech_rate VARCHAR(255)",
                            "start_rating   INT",
                            "end_rating     INT",
                            "date           DATE",

                            "PRIMARY KEY (id)",
                            "FOREIGN KEY (division_id) REFERENCES divisions(id)",
                            "FOREIGN KEY (player_id)   REFERENCES players(id)"
                          ],
  Constants::PLAYER_RESULTS_TABLE_NAME     => [
                            "id        INT NOT NULL AUTO_INCREMENT",
                            "player_id INT NOT NULL",
                            "game_id   INT NOT NULL",
                            "score     INT",
                            "result    INT",

                            "PRIMARY KEY (id)",
                            "FOREIGN KEY (player_id) REFERENCES players(id)",
                            "FOREIGN KEY (game_id) REFERENCES games(id)"
                          ],
  Constants::LEXICONS_TABLE_NAME  => [
                            "id   INT NOT NULL AUTO_INCREMENT",
                            "name VARCHAR(255)",

                            "PRIMARY KEY (id)"
                          ],
};


use constant TABLE_CREATION_ORDER => 
                     [
                       Constants::EVENTS_TABLE_NAME,
                       Constants::PLAYERS_TABLE_NAME,
                       Constants::PLAYER_ALT_NAMES_TABLE_NAME,
                       Constants::LEXICONS_TABLE_NAME,
                       Constants::TOURNAMENTS_TABLE_NAME,
                       Constants::DIVISIONS_TABLE_NAME,
                       Constants::GAMES_TABLE_NAME,
                       Constants::TOURNAMENT_RESULTS_TABLE_NAME,
                       Constants::PLAYER_RESULTS_TABLE_NAME
                     ];

use constant LEXICONS => [
                 {"name" => "CSW07"},
                 {"name" => "CSW12"},
                 {"name" => "CSW15"},
               ];
1;

