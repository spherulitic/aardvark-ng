#!/usr/bin/perl

package Constants;

use warnings;
use strict;
use version; our $VERSION = qv('1');
use base 'Exporter';
use Readonly;

Readonly our $EMPTY_STRING => q{};

Readonly our $LOCALTIME_YEAR_INDEX      => 5;
Readonly our $LOCALTIME_MONTH_INDEX     => 4;
Readonly our $LOCALTIME_DAY_INDEX       => 3;
Readonly our $LOCALTIME_YEAR_BASE       => 1900;
Readonly our $COUNTRY_IN_FILENAME_INDEX => -2;
Readonly our $NEGATIVE_ONE              => -1;
Readonly our $FULL_WIDTH                => 100;
Readonly our $WESPA_START_RATING        => 500;

Readonly our $DEV_ENV_KEYWORD => 'dev';

Readonly our $TEST_DIRECTORY    => 'test';
Readonly our $MODULES_DIRECTORY => 'modules';
Readonly our $OBJECTS_DIRECTORY => 'objects';
Readonly our $CGIBIN_DIR        => 'cgi-bin';

Readonly our $TEST_TITLE_WIDTH      => 50;
Readonly our $TEST_TOU_PATH         => '/aardvark/2020/USA/';
Readonly our $TEST_TOU_DIRECTORY    => 'tou';
Readonly our $TEST_STDOUT_DIRECTORY => 'stdout';
Readonly our $TEST_JSON_DIRECTORY   => 'json';

Readonly our $JSON_FAILURE_TYPE   => 'JSON';
Readonly our $KEYS_FAILURE_TYPE   => 'KEYS';
Readonly our $STDOUT_FAILURE_TYPE => 'STDOUT';

Readonly our $UNDEFINED_STRING => 'undef';

Readonly our $PERL_DIRECTORIES =>
  [ $TEST_DIRECTORY, $MODULES_DIRECTORY, $OBJECTS_DIRECTORY ];

Readonly our $FAILURE_REASON           => 'FAILURE';
Readonly our $FAILURE_TYPE             => 'Result Type';
Readonly our $FAILURE_TRACEBACK        => 'Traceback';
Readonly our $FAILURE_EXPECTED_RESULTS => 'Expected Results';
Readonly our $FAILURE_ACTUAL_RESULTS   => 'Actual Results';
Readonly our $FAILURE_DIFF             => '              ';

Readonly our $FAILURE_FIELDS => [
  $FAILURE_REASON,         $FAILURE_TYPE,
  $FAILURE_TRACEBACK,      $FAILURE_EXPECTED_RESULTS,
  $FAILURE_ACTUAL_RESULTS, $FAILURE_DIFF
];

Readonly our $TOU_DBH              => 'TOU Database Handler';
Readonly our $TOU_PLAYER_NAMES     => 'TOU Player Names';
Readonly our $TOU_CONVERSION_HASH  => 'TOU Player Name Conversion Hash';
Readonly our $TOU_STS_PLAYER_NAMES => 'TOU STS Player Names';
Readonly our $TOU_PLAYER_DATA      => 'TOU Player Data';
Readonly our $TOU_ERROR_REPORT     => 'TOU Error Report';
Readonly our $TOU_FILENAME         => 'TOU Filename';
Readonly our $TOU_LOADED           => 'TOU Loaded';
Readonly our $TOU_PROCESSED        => 'TOU Processed';
Readonly our $TOU_REWRITE_FILENAME => 'TOU Rewrite Filename';
Readonly our $TOU_REWRITE_NEEDED   => 'TOU Rewrite Needed';
Readonly our $TOU_VALID            => 'TOU Valid';
Readonly our $TOU_WARNING_REPORT   => 'TOU Warning Report';

Readonly our $TOU_EVENT         => 'TOU Event';
Readonly our $TOU_TOURNAMENT    => 'TOU Tournament';
Readonly our $TOU_DIVISION_DATA => 'TOU Division Data';

Readonly our $TOU_REWRITE_EXTENSION  => '.rewrite';
Readonly our $TOU_BASE_WINNING_SCORE => 2000;
Readonly our $TOU_BASE_TIE_SCORE     => 1000;
Readonly our $TOU_TIE_SCORE_RESULT   => 1350;
Readonly our $TOU_MINIMUM_WIN_SCORE  => 1950;
Readonly our $TOU_TIE_VALUE          => 0.5;
Readonly our $TOU_ZERO_PADDING       => 37;

Readonly our $UNBLESSED_IGNORE_KEYS => {
  $TOU_DBH             => 1,
  $TOU_PLAYER_DATA     => 1,
  $TOU_CONVERSION_HASH => 1,
  'lexicon_id'         => 1,
  'player_id'          => 1,
  'game_id'            => 1
};

Readonly our $DIVISION_TOUFILE             => 'Division Filename';
Readonly our $DIVISION_NAME                => 'Division Name';
Readonly our $DIVISION_NUMBER              => 'Division Number';
Readonly our $DIVISION_NUMBER_OF_ROUNDS    => 'Division Number of Rounds';
Readonly our $DIVISION_PLAYERS             => 'Division Players';
Readonly our $DIVISION_GAME_DATA           => 'Division Game Data';
Readonly our $DIVISION_MATRIX              => 'Division Matrix';
Readonly our $DIVISION_VALID               => 'Division Valid';
Readonly our $DIVISION_VERIFICATION_REPORT => 'Division Verification Report';
Readonly our $DIVISION_TOURNAMENT_RESULTS  => 'Division Tournament Results';
Readonly our $DIVISION_GAME_AND_PLAYER_RESULTS =>
  'Division Game and Player Results';

Readonly our $RESULT_SCORE           => 'Result Score';
Readonly our $RESULT_PLAYER_NUMBER   => 'Result Player Number';
Readonly our $RESULT_OPPONENT_NUMBER => 'Result Opponent Number';
Readonly our $RESULT_TOU_SCORE       => 'Result TOU Score';
Readonly our $RESULT_FIRST           => 'Result Player is First';
Readonly our $RESULT_WINS            => 'Result Wins';
Readonly our $RESULT_LOSSES          => 'Result Losses';
Readonly our $RESULT_BYES            => 'Result Byes';
Readonly our $RESULT_BYE_WINS        => 'Result Bye Wins';
Readonly our $RESULT_SPREAD          => 'Result Spread';
Readonly our $RESULT_ROUND           => 'Result Round';
Readonly our $RESULT_CODED           => 'Result Coded';
Readonly our $RESULT_PLAYER_IS_FIRST => 'Result Player is First';

Readonly our $RESULT_CODED_WIN  => 1;
Readonly our $RESULT_CODED_LOSS => -1;
Readonly our $RESULT_CODED_TIE  => 0;

Readonly our $INPUT_DIR           => 'inputs';
Readonly our $LOG_DIR             => 'logs';
Readonly our $MODULES_DIR         => 'modules';
Readonly our $SCRIPTS_DIR         => 'scripts';
Readonly our $HTML_DIR            => 'html';
Readonly our $HTML_STATIC_DIR     => 'html_static';
Readonly our $HTML_DATA_DIR       => 'html_data';
Readonly our $PLAYER_HTML_DIR     => 'players';
Readonly our $TOURNAMENT_HTML_DIR => 'tournaments';
Readonly our $RANKINGS_HTML_DIR   => 'rankings';
Readonly our $FULL_RANKINGS_NAME  => 'full_rankings';

Readonly our $PLAYER_SEARCH_DATA_FILENAME  => 'player_search_data.html';
Readonly our $COUNTRY_SEARCH_DATA_FILENAME => 'country_search_data.html';
Readonly our $FRONT_PAGE_RATINGS_DATA_FILENAME =>
  'front_page_ratings_data.html';
Readonly our $TOURNAMENT_FORM_DATA_FILENAME => 'tournament_form_data.html';
Readonly our $TOURNAMENT_CGI_FILENAME       => 'find_tournament.pl';
Readonly our $FRONT_PAGE_RATINGS_CUTOFF     => 10;

Readonly our $HTML_HEADER => "Content-type: text/html\n\n";

Readonly our $HTML_ID_PLAYER_TYPE       => 0;
Readonly our $HTML_ID_TOURNAMENT_TYPE   => 1;
Readonly our $HTML_ID_HEAD_TO_HEAD_TYPE => 2;
Readonly our $HTML_ID_BUTTON_TAG        => 'button';
Readonly our $HTML_ID_ENTRY_TAG         => 'entry';

Readonly our $HTML_PATH_TO_WORKING_DIR => '../..';

Readonly our $TOURNAMENT_DATA_DIR            => '/srv/dev/tournament_data';
Readonly our $DEFAULT_WORKING_DIR            => "/srv/dev/aardvark";
Readonly our $DEFAULT_SHORT_NAME_WORKING_DIR => "aardvark";
Readonly our $DEFAULT_YEAR_REGEX             => '^\d\d\d\d$';
Readonly our $DEFAULT_COUNTRY_TRIGRAPH_REGEX => '^\w\w\w$';
Readonly our $DEFAULT_FILE_REGEX             => '.tou';

Readonly our $DEFAULT_BACKUP_DIR =>
  '/home/jcastellano/aardvark-ng/backups/backup_original';

Readonly our $COUNTRY_FLAGS_DIR => 'flags';

Readonly our $PRODUCTION_DATABASE_NAME => 'wespaprod';
Readonly our $DATABASE_NAME            => 'wespa';
Readonly our $DATABASE_HOST_NAME       => 'localhost';
Readonly our $DATABASE_USER_NAME       => 'wespa';
Readonly our $DATABASE_PASSWORD        => 'nigeltheking';

Readonly our $TEXT_FILES_BACKUP_PREFIX => 'tournament_files';

Readonly our $TOU_FILE_EXTENSION => '.tou';
Readonly our $STS_FILE_EXTENSION => '.STS';
Readonly our $STA_FILE_EXTENSION => '.STA';

Readonly our $PLAYERS_TABLE_NAME            => 'players';
Readonly our $PLAYER_ALT_NAMES_TABLE_NAME   => 'player_alt_names';
Readonly our $TOURNAMENTS_TABLE_NAME        => 'tournaments';
Readonly our $EVENTS_TABLE_NAME             => 'events';
Readonly our $DIVISIONS_TABLE_NAME          => 'divisions';
Readonly our $GAMES_TABLE_NAME              => 'games';
Readonly our $TOURNAMENT_RESULTS_TABLE_NAME => 'tournament_results';
Readonly our $PLAYER_RESULTS_TABLE_NAME     => 'player_results';
Readonly our $LEXICONS_TABLE_NAME           => 'lexicons';
Readonly our $LOADED_TOURNAMENTS_TABLE_NAME => 'loaded_tournaments';

Readonly our $MASTER_RATINGS_LIST        => 'rating.dat';
Readonly our $NOT_IN_MASTER_RATINGS_LIST => 'not_in_ratings_list.log';

Readonly our $REMOVED_NAMES_FILE           => 'removed_names.log';
Readonly our $DUPLICATE_NAMES_FILE         => 'duplicate_names.log';
Readonly our $INCORRECT_NAME_MAPPINGS_FILE => 'incorrect_name_mappings.log';
Readonly our $INPUT_MERGE_FILE             => 'duplicates.txt';
Readonly our $DECEASED_PLAYERS             => 'removed_people.txt';

Readonly our $TRIGRAPH_LENGTH => 3;

Readonly our $WINS_COLUMN_COLOR   => '#bbffbb';
Readonly our $LOSSES_COLUMN_COLOR => '#ffdddd';
Readonly our $DRAWS_COLUMN_COLOR  => '#eeeeee';
Readonly our $BYES_COLUMN_COLOR   => '#eeeeee';

Readonly our $PROVISIONAL_GAMES_MAX => 50;
Readonly our $CURRENT_GAMES_MIN     => 40;
Readonly our $PHOTO_DIR             => 'icons';

Readonly our $DEFAULT_BYE_SCORE => 1350;

Readonly our $TWO_YEARS_IN_SECONDS => 24 * 60 * 60 * 365 * 2;

Readonly our $ROUNDING_PLACE => 2;

Readonly our $UPDATE_START_YEAR => 2019;
Readonly our $UPDATE_SOURCE_DIR => '/srv/iwi.wespa.org/aardvark';

Readonly our $TABLES => {
  $LOADED_TOURNAMENTS_TABLE_NAME => [
    'id                 INT NOT NULL AUTO_INCREMENT',
    'name               VARCHAR(255)',
    'filename           VARCHAR(255)',

    'PRIMARY KEY (id)'
  ],
  $PLAYERS_TABLE_NAME => [
    'id                 INT NOT NULL AUTO_INCREMENT',
    'name               VARCHAR(255)',
    'country            VARCHAR(3)',
    'photo              VARCHAR(255)',
    'suspended          BOOLEAN',
    'deceased           BOOLEAN',
    'current            BOOLEAN',
    'provisional        BOOLEAN',
    'total_games        INT',
    'last_played        DATE',
    'rating             INT',

    'PRIMARY KEY (id)'
  ],
  $TOURNAMENTS_TABLE_NAME => [
    'id         INT NOT NULL AUTO_INCREMENT',
    'event_id   INT NOT NULL',
    'td         VARCHAR(255)',
    'start_date DATE',
    'end_date   DATE',
    'name       VARCHAR(255)',
    'country    VARCHAR(3)',

    'PRIMARY KEY (id)',
    'FOREIGN KEY (event_id) REFERENCES events(id)'
  ],
  $EVENTS_TABLE_NAME => [
    'id         INT NOT NULL AUTO_INCREMENT',
    'start_date DATE',
    'end_date   DATE',
    'link       VARCHAR(255)',
    'sponsor    VARCHAR(255)',
    'country    VARCHAR(3)',
    'location   VARCHAR(255)',

    'PRIMARY KEY (id)'
  ],
  $DIVISIONS_TABLE_NAME => [
    'id              INT NOT NULL AUTO_INCREMENT',
    'tournament_id   INT NOT NULL',
    'name            VARCHAR(255)',
    'length          INT',
    'number          INT',

    'PRIMARY KEY (id)',
    'FOREIGN KEY (tournament_id) REFERENCES tournaments(id)'
  ],
  $GAMES_TABLE_NAME => [
    'id           INT NOT NULL AUTO_INCREMENT',
    'division_id  INT NOT NULL',
    'round        INT',
    'lexicon_id   INT NOT NULL',
    'gcg_filename VARCHAR(255)',

    'PRIMARY KEY (id)',
    'FOREIGN KEY (division_id) REFERENCES divisions(id)',
    'FOREIGN KEY (lexicon_id)  REFERENCES lexicons(id)'
  ],
  $TOURNAMENT_RESULTS_TABLE_NAME => [
    'id                INT NOT NULL AUTO_INCREMENT',
    'division_id       INT NOT NULL',
    'player_id         INT NOT NULL',
    'player_name       VARCHAR(255)',
    'position          INT',
    'wins              FLOAT',
    'losses            FLOAT',
    'byes              INT',
    'bye_wins          FLOAT',
    'spread            INT',
    'prize_money       INT',
    'prize_currency    VARCHAR(255)',
    'prize_ech_rate    VARCHAR(255)',
    'start_rating      INT',
    'end_rating        INT',
    'date              DATE',
    'tournament_name   VARCHAR(255)',

    'expected_wins     FLOAT',
    'old_world_rank    INT',
    'new_world_rank    INT',
    'old_national_rank INT',
    'new_national_rank INT',

    'PRIMARY KEY (id)',
    'FOREIGN KEY (division_id) REFERENCES divisions(id)',
    'FOREIGN KEY (player_id)   REFERENCES players(id)'
  ],
  $PLAYER_RESULTS_TABLE_NAME => [
    'id        INT NOT NULL AUTO_INCREMENT',
    'player_id INT NOT NULL',
    'game_id   INT NOT NULL',
    'score     INT',
    'result    INT',

    'PRIMARY KEY (id)',
    'FOREIGN KEY (player_id) REFERENCES players(id)',
    'FOREIGN KEY (game_id) REFERENCES games(id)'
  ],
  $LEXICONS_TABLE_NAME => [
    'id   INT NOT NULL AUTO_INCREMENT',
    'name VARCHAR(255)',

    'PRIMARY KEY (id)'
  ],
};

Readonly our $TABLE_CREATION_ORDER => [
  $EVENTS_TABLE_NAME,             $PLAYERS_TABLE_NAME,
  $LEXICONS_TABLE_NAME,           $TOURNAMENTS_TABLE_NAME,
  $DIVISIONS_TABLE_NAME,          $GAMES_TABLE_NAME,
  $TOURNAMENT_RESULTS_TABLE_NAME, $PLAYER_RESULTS_TABLE_NAME,
  $LOADED_TOURNAMENTS_TABLE_NAME
];

Readonly our $TABLE_DROP_EXCEPTIONS => { $PLAYERS_TABLE_NAME => 1 };

Readonly our $LEXICONS =>
  [ { 'name' => 'CSW07' }, { 'name' => 'CSW12' }, { 'name' => 'CSW15' }, ];

Readonly our $GAME_STATS_RANK_NAME => 'rank';
Readonly our $STAT_KEY_NAME        => 'stat';
Readonly our $ALLTIME_CUTOFF       => 60;

Readonly our $TOURNAMENT_STATS_ORDER =>
  [ 'High Win', 'High Loss', 'High Spread', 'High Combined', 'Upsets' ];

Readonly our $COUNTRY_TRIGRAPH_TO_COUNTRY_NAME_HASHREF => {
  'ABW' => 'Aruba',
  'ABB' => 'Asia',
  'ATG' => 'Antigua and Barbuda',
  'AFG' => 'Afghanistan',
  'DZA' => 'Algeria',
  'AZE' => 'Azerbaijan',
  'SSD' => 'South Sudan',
  'ALB' => 'Albania',
  'ARM' => 'Armenia',
  'AND' => 'Andorra',
  'AGO' => 'Angola',
  'ARG' => 'Argentina',
  'AUS' => 'Australia',
  'ACI' => 'Ashmore and Cartier Islands',
  'AUT' => 'Austria',
  'AIA' => 'Anguilla',
  'ATA' => 'Antarctica',
  'BHR' => 'Bahrain',
  'BRB' => 'Barbados',
  'BWA' => 'Botswana',
  'BMU' => 'Bermuda',
  'BEL' => 'Belgium',
  'BHS' => 'The Bahamas',
  'BGD' => 'Bangladesh',
  'BLZ' => 'Belize',
  'BIH' => 'Bosnia-Herzegovina',
  'BOL' => 'Bolivia',
  'MMR' => 'Myanmar',
  'BEN' => 'Benin',
  'BLR' => 'Belarus',
  'SLB' => 'Solomon Islands',
  'BRA' => 'Brazil',
  'BTN' => 'Bhutan',
  'BGR' => 'Bulgaria',
  'BVT' => 'Bouvet Island',
  'BRN' => 'Brunei',
  'BDI' => 'Burundi',
  'CAN' => 'Canada',
  'KHM' => 'Cambodia',
  'TCD' => 'Chad',
  'LKA' => 'Sri Lanka',
  'COG' => 'Republic of the Congo',
  'COD' => 'Democratic Republic of the Congo',
  'CHN' => 'China',
  'CHL' => 'Chile',
  'CYM' => 'Cayman Islands',
  'CCK' => 'Cocos (Keeling) Islands',
  'CMR' => 'Cameroon',
  'COM' => 'Comoros',
  'COL' => 'Colombia',
  'MNP' => 'Northern Mariana Islands',
  'CSI' => 'Coral Sea Islands',
  'CRI' => 'Costa Rica',
  'CAF' => 'Central African Republic',
  'CUB' => 'Cuba',
  'CPV' => 'Cape Verde',
  'COK' => 'Cook Islands',
  'CYP' => 'Cyprus',
  'CZE' => 'Czech Republic',
  'DNK' => 'Denmark',
  'DJI' => 'Djibouti',
  'DMA' => 'Dominica',
  'DOM' => 'Dominican Republic',
  'ECU' => 'Ecuador',
  'EEE' => 'Europe',
  'EGY' => 'Egypt',
  'IRL' => 'Ireland',
  'GNQ' => 'Equatorial Guinea',
  'EST' => 'Estonia',
  'ERI' => 'Eritrea',
  'ESP' => 'Spain',
  'ETH' => 'Ethiopia',
  'FFF' => 'Africa',
  'GUF' => 'French Guiana',
  'FIN' => 'Finland',
  'FJI' => 'Fiji',
  'FLK' => 'Falkland Islands',
  'FSM' => 'Federated States of Micronesia',
  'FRO' => 'Faroe Islands',
  'PYF' => 'French Polynesia',
  'FRA' => 'France',
  'ATF' => 'French Southern Territories',
  'FYR' => 'Macedonia',
  'GMB' => 'Gambia',
  'GAB' => 'Gabon',
  'DEU' => 'Germany',
  'GEO' => 'Georgia',
  'GHA' => 'Ghana',
  'GIB' => 'Gibraltar',
  'GRD' => 'Grenada',
  'GRL' => 'Greenland',
  'GLP' => 'Guadeloupe',
  'GUM' => 'Guam',
  'GRC' => 'Greece',
  'GTM' => 'Guatemala',
  'GIN' => 'Guinea',
  'GUY' => 'Guyana',
  'HTI' => 'Haiti',
  'HKG' => 'Hong Kong',
  'HMD' => 'Heard and McDonald Islands',
  'HND' => 'Honduras',
  'HQI' => 'Howland Island',
  'HRV' => 'Croatia',
  'HUN' => 'Hungary',
  'ISL' => 'Iceland',
  'IMN' => 'Isle of Man',
  'IDN' => 'Indonesia',
  'IND' => 'India',
  'IOT' => 'British Indian Ocean Territory',
  'UMI' => 'U.S. Minor Outlying Islands',
  'IRN' => 'Iran',
  'ISR' => 'Israel',
  'ITA' => 'Italy',
  'CIV' => 'Côte d\'Ivoire',
  'IRQ' => 'Iraq',
  'JPN' => 'Japan',
  'JAM' => 'Jamaica',
  'JNM' => 'Jan Mayen Island',
  'JOR' => 'Jordan',
  'JQA' => 'Johnston Atoll',
  'KEN' => 'Kenya',
  'KGZ' => 'Kyrgyzstan',
  'PRK' => 'Democratic People\'s Republic of Korea',
  'KIR' => 'Kiribati',
  'KOR' => 'Republic of Korea',
  'CXR' => 'Christmas Island',
  'KWT' => 'Kuwait',
  'KAZ' => 'Kazakhstan',
  'LAO' => 'Laos',
  'LBN' => 'Lebanon',
  'LVA' => 'Latvia',
  'LTU' => 'Lithuania',
  'LBR' => 'Liberia',
  'SVK' => 'Slovakia',
  'LIE' => 'Liechtenstein',
  'LSO' => 'Lesotho',
  'LUX' => 'Luxembourg',
  'LBY' => 'Libya',
  'MDG' => 'Madagascar',
  'MTQ' => 'Martinique',
  'MAC' => 'Macau',
  'MDA' => 'Republic of Moldova',
  'MNE' => 'Montenegro',
  'MNG' => 'Mongolia',
  'MSR' => 'Montserrat',
  'MWI' => 'Malawi',
  'MLI' => 'Mali',
  'MCO' => 'Monaco',
  'MAR' => 'Morocco',
  'MUS' => 'Mauritius',
  'MRT' => 'Mauritania',
  'MLT' => 'Malta',
  'OMN' => 'Oman',
  'MDV' => 'The Maldives',
  'MEX' => 'Mexico',
  'MYS' => 'Malaysia',
  'MOZ' => 'Mozambique',
  'ANT' => 'Netherlands Antilles',
  'NCL' => 'New Caledonia',
  'NIU' => 'Niue',
  'NFK' => 'Norfolk Island',
  'NER' => 'Niger',
  'VUT' => 'Vanuatu',
  'NGA' => 'Nigeria',
  'NLD' => 'Netherlands',
  'NNN' => 'North America',
  'NOR' => 'Norway',
  'NPL' => 'Nepal',
  'NRU' => 'Nauru',
  'SUR' => 'Suriname',
  'NTT' => 'NATO countries',
  'NIC' => 'Nicaragua',
  'NZL' => 'New Zealand',
  'PRY' => 'Paraguay',
  'PCN' => 'Pitcairn Islands',
  'PER' => 'Peru',
  'PFI' => 'Paracel Islands',
  'PAK' => 'Pakistan',
  'POL' => 'Poland',
  'PAN' => 'Panama',
  'PRT' => 'Portugal',
  'PNG' => 'Papua New Guinea',
  'PLW' => 'Palau',
  'PSE' => 'Palestinian Territory',
  'GNB' => 'Guinea-Bissau',
  'QAT' => 'Qatar',
  'REU' => 'Réunion',
  'MHL' => 'Marshall Islands',
  'ROU' => 'Romania',
  'PHL' => 'Philippines',
  'PRI' => 'Puerto Rico',
  'SRB' => 'Serbia',
  'RUS' => 'Russia',
  'RWA' => 'Rwanda',
  'SAU' => 'Saudi Arabia',
  'SPM' => 'Saint Pierre and Miquelon',
  'KNA' => 'Saint Kitts and Nevis',
  'SYC' => 'Seychelles',
  'ZAF' => 'South Africa',
  'SEN' => 'Senegal',
  'SHN' => 'Saint Helena',
  'SVN' => 'Slovenia',
  'SJM' => 'Svalbard and Jan Mayen Islands',
  'SLE' => 'Sierra Leone',
  'SMR' => 'San Marino',
  'SGP' => 'Singapore',
  'SOM' => 'Somalia',
  'SRR' => 'South America',
  'ASM' => 'American Samoa',
  'WSM' => 'Samoa',
  'LCA' => 'Saint Lucia',
  'SDN' => 'Sudan',
  'SLV' => 'El Salvador',
  'SWE' => 'Sweden',
  'SGS' => 'South Georgia and South Sandwich Islands',
  'SYR' => 'Syria',
  'CHE' => 'Switzerland',
  'ARE' => 'United Arab Emirates',
  'TTO' => 'Trinidad and Tobago',
  'THA' => 'Thailand',
  'TJK' => 'Tajikistan',
  'TCA' => 'Turks and Caicos Islands',
  'TKL' => 'Tokelau',
  'TLS' => 'Timor-Leste',
  'TON' => 'Tonga',
  'TGO' => 'Togo',
  'STP' => 'São Tomé and Príncipe',
  'TUN' => 'Tunisia',
  'TUR' => 'Turkey',
  'TUV' => 'Tuvalu',
  'TWN' => 'Taiwan',
  'TKM' => 'Turkmenistan',
  'TZA' => 'Tanzania',
  'UGA' => 'Uganda',
  'GBR' => 'United Kingdom',
  'UKR' => 'Ukraine',
  'USA' => 'United States',
  'UUU' => 'Oceania',
  'BFA' => 'Burkina Faso',
  'URY' => 'Uruguay',
  'UZB' => 'Uzbekistan',
  'VCT' => 'Saint Vincent and the Grenadines',
  'VEN' => 'Venezuela',
  'VIR' => 'U.S. Virgin Islands',
  'VNM' => 'Vietnam',
  'VGB' => 'British Virgin Islands',
  'VAT' => 'Vatican City (Holy See)',
  'NAM' => 'Namibia',
  'WLF' => 'Wallis and Futuna Islands',
  'ESH' => 'Western Sahara',
  'SWZ' => 'Swaziland',
  'YEM' => 'Yemen',
  'YUG' => 'Yugoslavia',
  'ZMB' => 'Zambia',
  'ZWE' => 'Zimbabwe',

  # Not actually country codes but
  # we wanted each country in the UK
  # to be distinct

  'SCO' => 'Scotland',
  'ENG' => 'England',
  'WAL' => 'Wales',
  'NIR' => 'Northern Ireland'
};

Readonly our $COUNTRY_TRIGRAPH_CONVERSION => {

  # IRE is incorrectly assumed to be Ireland
  # in the old system. The country code for
  # Ireland is IRL.

  'IRE' => 'IRL',

  # There are no codes for Wales, Scotland,
  # England, or Northern Ireland as they
  # all share the code for the United Kingdom
  # (GBR)
  #
  # Comment the following lines to treat
  # each country of the United Kingdom
  # distinctly in the HTML. Note that
  # the codes for each country of the
  # United Kingdom are made up by the developers
  # and are not part of ISO 3166.

  # 'NIR' => 'GBR',
  # 'ENG' => 'GBR',
  # 'SCO' => 'GBR',
  # 'WAL' => 'GBR',

  'KUW' => 'KWT',
  'BAR' => 'BRB',
  'ZIM' => 'ZWE',
  'MLE' => 'MDV',
  'MLV' => 'MDV',
  'SWI' => 'CHE',
  'NIG' => 'NGA',
  'KYR' => 'KGZ',
  'ROK' => 'KOR',
  'MYM' => 'MMR',
  'INR' => 'IDN',
  'GER' => 'DEU',
  'UAE' => 'ARE',
  'NED' => 'NLD',
  'ZAM' => 'ZMB',
  'SIN' => 'SGP',
  'SUI' => 'CHE',
  'SPA' => 'ESP',
  'SRI' => 'LKA'
};

Readonly our $TEMPLATE_DOCTYPE =>

  <<'DOCTYPE'
<!DOCTYPE html>
DOCTYPE

  ;

Readonly our $TEMPLATE_META => <<'META'

META
  ;

Readonly our $TEMPLATE_LANG =>

  <<'LANG'
lang="en"
LANG
  ;

Readonly our $TEMPLATE_WESPA_IMAGE =>

  <<'WESPA_IMG'
    <div class="container-topper">
      <div style="margin: auto;width: 80px;">
        <img class="img-responsive" src="/wespafb.jpg" width="80" height="80" alt="WESPA">
      </div>
    </div>
WESPA_IMG

  ;

Readonly our $TEMPLATE_SOURCES =>

  <<'SOURCES'

<script  src="/aardvark/js/tabber.js"></script>
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="stylesheet" type="text/css" href="/aardvark/aardvark.css">
<link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/css/bootstrap.min.css">
<link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/font-awesome/4.7.0/css/font-awesome.min.css">
<script src="https://ajax.googleapis.com/ajax/libs/jquery/3.2.0/jquery.min.js"></script>
<script src="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/js/bootstrap.min.js"></script>


SOURCES
  ;

Readonly our $TEMPLATE_STYLE =>

  <<'STYLE'

<style >

        .navbar {margin-bottom: 0px;}
        .federation-row { padding-top:10px;
                                          padding-bottom:10px;
                                         
        }
        .navbar-nav>li>a {
                color: black ;
        }
        td
        {
                padding: 0px;
        }

</style>  
STYLE
  ;

Readonly our $TEMPLATE_SCRIPTS =>

  <<'SCRIPTS'

      $(document).ready(function () {
      
        $('.collapse').on('shown.bs.collapse', function (e) {
        
          var id = e.target.id;
      
          id = id.replace('entry', 'button'); 
          var el = document.getElementById(id);
          el.innerHTML = '&#8722';
        
        });
        
        $('.collapse').on('hidden.bs.collapse', function (e) {
      
          var id = e.target.id;
      
          id = id.replace('entry', 'button'); 
          var el = document.getElementById(id);
          el.innerHTML = '+';
         
        });
      });

      function showContent(evt, id, content_classname, links_classname)
      {
        var i, tabcontent, tablinks;
        tabcontent = document.getElementsByClassName(content_classname);
        for (i = 0; i < tabcontent.length; i++)
        {
          tabcontent[i].style.display = "none";
        }
        tablinks = document.getElementsByClassName(links_classname);
        for (i = 0; i < tablinks.length; i++)
        {
          tablinks[i].className = tablinks[i].className.replace(" active", "");
        }
        document.getElementById(id).style.display = "block";
        evt.currentTarget.className += " active";
      }
SCRIPTS
  ;

Readonly our $TEMPLATE_NAV =>

  <<'NAV'
<div class="navbar navbar-default" style="background:#e8e6e6;">
  <div class="container-fluid">
    <div class="navbar-header">
      <button type="button" class="navbar-toggle" data-toggle="collapse" data-target="#myNavbar">
        <span class="icon-bar"></span>
        <span class="icon-bar"></span>
        <span class="icon-bar"></span>
        <span class="icon-bar"></span>
        <span class="icon-bar"></span>   
        <span class="icon-bar"></span>   
        <span class="icon-bar"></span>                  
      </button>
    </div>
    <div class="collapse navbar-collapse" id="myNavbar">
      <ul class="nav navbar-nav">
        <li><a href="/index.shtml">Home</a></li>
        <li class="dropdown">
          <a class="dropdown-toggle" data-toggle="dropdown" href="#">About Us <span class="caret"></span></a>
          <ul class="dropdown-menu">
            <li><a href="/associations.shtml">Associations</a></li>
            <li><a href="/committees.shtml">Committees</a></li>
            <li><a href="/joinwespa.shtml">Join Us</a></li>
            <li><a href="/credits.shtml">Credits</a></li>
          </ul>
        </li>
        <li><a href="/news.shtml">News</a></li>
        <li class="dropdown">
          <a class="dropdown-toggle" data-toggle="dropdown" href="#">Tournaments <span class="caret"></span></a>
          <ul class="dropdown-menu">
            <li><a href="/tournaments/index.shtml">Calendar</a></li>
            <li><a href="/ratings.shtml">Ratings</a></li>
          </ul>
        </li>
        <li><a href="/resources.shtml">Resources</a></li>
        <li><a href="/youth.shtml">Youth Scrabble</a></li>
        <li><a href="/products.shtml">Products</a></li>
      </ul>
      <ul class="nav navbar-nav navbar-right">
        <li><a href="/contactus.shtml"><span class="glyphicon glyphicon-envelope"></span></a></li>
      </ul>
    </div>
  </div>
</div>
NAV
  ;

Readonly our $TEMPLATE_FOOTER =>

  <<'FOOTER'
<div class="container-fluid" style="background-color:white;">
     
        <p class="small">&copy; WESPA <br><br>SCRABBLE&reg; is a registered trademark. All intellectual property rights in and to the game are owned in the US by Hasbro Inc, in Canada by Hasbro Canada Inc and throughout the rest of the world by JW Spear &amp; Sons Ltd of Maidenhead, SL6 4UB, England, a subsidiary of Mattel Inc. Mattel and Spear are not affiliated with Hasbro or Hasbro Canada.</p>
     
</div>
FOOTER
  ;

# BEGIN EXPORT
our @EXPORT = qw(
  $RESULT_CODED_WIN
  $RESULT_CODED_LOSS
  $RESULT_CODED_TIE
  $TOU_REWRITE_EXTENSION
  $TOU_BASE_WINNING_SCORE
  $TOU_BASE_TIE_SCORE
  $TOU_TIE_SCORE_RESULT
  $TOU_MINIMUM_WIN_SCORE
  $TOU_TIE_VALUE
  $TOU_ZERO_PADDING
  $EMPTY_STRING
  $LOCALTIME_YEAR_INDEX
  $LOCALTIME_MONTH_INDEX
  $LOCALTIME_DAY_INDEX
  $LOCALTIME_YEAR_BASE
  $COUNTRY_IN_FILENAME_INDEX
  $NEGATIVE_ONE
  $FULL_WIDTH
  $WESPA_START_RATING
  $DEV_ENV_KEYWORD
  $TEST_DIRECTORY
  $MODULES_DIRECTORY
  $OBJECTS_DIRECTORY
  $CGIBIN_DIR
  $TEST_TITLE_WIDTH
  $TEST_TOU_PATH
  $TEST_TOU_DIRECTORY
  $TEST_STDOUT_DIRECTORY
  $TEST_JSON_DIRECTORY
  $JSON_FAILURE_TYPE
  $KEYS_FAILURE_TYPE
  $STDOUT_FAILURE_TYPE
  $UNDEFINED_STRING
  $PERL_DIRECTORIES
  $FAILURE_REASON
  $FAILURE_TYPE
  $FAILURE_TRACEBACK
  $FAILURE_EXPECTED_RESULTS
  $FAILURE_ACTUAL_RESULTS
  $FAILURE_DIFF
  $FAILURE_FIELDS
  $TOU_DBH
  $TOU_PLAYER_NAMES
  $TOU_CONVERSION_HASH
  $TOU_STS_PLAYER_NAMES
  $TOU_PLAYER_DATA
  $TOU_ERROR_REPORT
  $TOU_FILENAME
  $TOU_LOADED
  $TOU_PROCESSED
  $TOU_REWRITE_FILENAME
  $TOU_REWRITE_NEEDED
  $TOU_VALID
  $TOU_WARNING_REPORT
  $TOU_EVENT
  $TOU_TOURNAMENT
  $TOU_DIVISION_DATA
  $UNBLESSED_IGNORE_KEYS
  $DIVISION_TOUFILE
  $DIVISION_NAME
  $DIVISION_NUMBER
  $DIVISION_NUMBER_OF_ROUNDS
  $DIVISION_PLAYERS
  $DIVISION_GAME_DATA
  $DIVISION_MATRIX
  $DIVISION_VALID
  $DIVISION_VERIFICATION_REPORT
  $DIVISION_TOURNAMENT_RESULTS
  $DIVISION_GAME_AND_PLAYER_RESULTS
  $RESULT_SCORE
  $RESULT_PLAYER_NUMBER
  $RESULT_OPPONENT_NUMBER
  $RESULT_TOU_SCORE
  $RESULT_FIRST
  $RESULT_WINS
  $RESULT_LOSSES
  $RESULT_BYES
  $RESULT_BYE_WINS
  $RESULT_SPREAD
  $RESULT_ROUND
  $RESULT_CODED
  $RESULT_PLAYER_IS_FIRST
  $INPUT_DIR
  $LOG_DIR
  $MODULES_DIR
  $SCRIPTS_DIR
  $HTML_DIR
  $HTML_STATIC_DIR
  $HTML_DATA_DIR
  $PLAYER_HTML_DIR
  $TOURNAMENT_HTML_DIR
  $RANKINGS_HTML_DIR
  $FULL_RANKINGS_NAME
  $PLAYER_SEARCH_DATA_FILENAME
  $COUNTRY_SEARCH_DATA_FILENAME
  $FRONT_PAGE_RATINGS_DATA_FILENAME
  $TOURNAMENT_FORM_DATA_FILENAME
  $TOURNAMENT_CGI_FILENAME
  $FRONT_PAGE_RATINGS_CUTOFF
  $HTML_HEADER
  $HTML_ID_PLAYER_TYPE
  $HTML_ID_TOURNAMENT_TYPE
  $HTML_ID_HEAD_TO_HEAD_TYPE
  $HTML_ID_BUTTON_TAG
  $HTML_ID_ENTRY_TAG
  $HTML_PATH_TO_WORKING_DIR
  $TOURNAMENT_DATA_DIR
  $DEFAULT_WORKING_DIR
  $DEFAULT_SHORT_NAME_WORKING_DIR
  $DEFAULT_YEAR_REGEX
  $DEFAULT_COUNTRY_TRIGRAPH_REGEX
  $DEFAULT_FILE_REGEX
  $DEFAULT_BACKUP_DIR
  $COUNTRY_FLAGS_DIR
  $PRODUCTION_DATABASE_NAME
  $DATABASE_NAME
  $DATABASE_HOST_NAME
  $DATABASE_USER_NAME
  $DATABASE_PASSWORD
  $TEXT_FILES_BACKUP_PREFIX
  $TOU_FILE_EXTENSION
  $STS_FILE_EXTENSION
  $STA_FILE_EXTENSION
  $PLAYERS_TABLE_NAME
  $PLAYER_ALT_NAMES_TABLE_NAME
  $TOURNAMENTS_TABLE_NAME
  $EVENTS_TABLE_NAME
  $DIVISIONS_TABLE_NAME
  $GAMES_TABLE_NAME
  $TOURNAMENT_RESULTS_TABLE_NAME
  $PLAYER_RESULTS_TABLE_NAME
  $LEXICONS_TABLE_NAME
  $LOADED_TOURNAMENTS_TABLE_NAME
  $MASTER_RATINGS_LIST
  $NOT_IN_MASTER_RATINGS_LIST
  $REMOVED_NAMES_FILE
  $DUPLICATE_NAMES_FILE
  $INCORRECT_NAME_MAPPINGS_FILE
  $INPUT_MERGE_FILE
  $DECEASED_PLAYERS
  $TRIGRAPH_LENGTH
  $WINS_COLUMN_COLOR
  $LOSSES_COLUMN_COLOR
  $DRAWS_COLUMN_COLOR
  $BYES_COLUMN_COLOR
  $PROVISIONAL_GAMES_MAX
  $CURRENT_GAMES_MIN
  $PHOTO_DIR
  $DEFAULT_BYE_SCORE
  $TWO_YEARS_IN_SECONDS
  $ROUNDING_PLACE
  $UPDATE_START_YEAR
  $UPDATE_SOURCE_DIR
  $TABLES
  $TABLE_CREATION_ORDER
  $TABLE_DROP_EXCEPTIONS
  $LEXICONS
  $GAME_STATS_RANK_NAME
  $STAT_KEY_NAME
  $ALLTIME_CUTOFF
  $TOURNAMENT_STATS_ORDER
  $COUNTRY_TRIGRAPH_TO_COUNTRY_NAME_HASHREF
  $COUNTRY_TRIGRAPH_CONVERSION
  $TEMPLATE_DOCTYPE
  $TEMPLATE_META
  $TEMPLATE_LANG
  $TEMPLATE_WESPA_IMAGE
  $TEMPLATE_SOURCES
  $TEMPLATE_STYLE
  $TEMPLATE_SCRIPTS
  $TEMPLATE_NAV
  $TEMPLATE_FOOTER
);

1;
