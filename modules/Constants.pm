#!/usr/bin/perl

package Constants;

use warnings;
use strict;

use constant INPUT_DIR           => 'inputs';
use constant LOG_DIR             => 'logs';

use constant TOURNAMENT_DATA_DIR            => '/app/tournament_data';
use constant DEFAULT_WORKING_DIR            => "/app/working";
use constant DEFAULT_YEAR_REGEX             => '^\d\d\d\d$';
use constant DEFAULT_COUNTRY_TRIGRAPH_REGEX => '^\w\w\w$';
use constant DEFAULT_FILE_REGEX             => '.tou';

use constant DEFAULT_BACKUP_DIR             => "/app/backups";

use constant PRODUCTION_DATABASE_NAME      => $ENV{AARDVARK_PROD_DB_NAME} // 'wespa';
use constant DATABASE_NAME                 => $ENV{AARDVARK_DB_NAME} // 'wespa_dev';
use constant DATABASE_HOST_NAME            => $ENV{AARDVARK_DB_HOST} // '127.0.0.1';
use constant DATABASE_PORT                 => $ENV{AARDVARK_DB_PORT} // 3306;
use constant DATABASE_USER_NAME            => $ENV{AARDVARK_DB_USER} // 'wespa';
use constant DATABASE_PASSWORD             => $ENV{AARDVARK_DB_PASSWORD} // 'xxx';
use constant DATABASE_SSL_MODE             => $ENV{AARDVARK_DB_SSL_MODE} // '';
use constant DATABASE_SSL_CA               => $ENV{AARDVARK_DB_SSL_CA} // '';

# Refuse to run if the staging and production database names are the same.
# A full run drops and rebuilds the staging database, so pointing both names
# at the same schema would destroy production data.
BEGIN
{
  if (DATABASE_NAME eq PRODUCTION_DATABASE_NAME)
  {
    die "FATAL: staging and production database names are identical ("
      . DATABASE_NAME . "); refusing to run\n";
  }
}

use constant TEXT_FILES_BACKUP_PREFIX => 'tournament_files';

use constant TOU_FILE_EXTENSION => '.tou';
use constant STS_FILE_EXTENSION => '.STS';
use constant STA_FILE_EXTENSION => '.STA';
use constant ST4_FILE_EXTENSION => '.ST4';

use constant PLAYERS_TABLE_NAME            => 'players';
use constant PLAYER_ALT_NAMES_TABLE_NAME   => 'player_alt_names';
use constant TOURNAMENTS_TABLE_NAME        => 'tournaments';
use constant EVENTS_TABLE_NAME             => 'events';
use constant DIVISIONS_TABLE_NAME          => 'divisions';
use constant GAMES_TABLE_NAME              => 'games';
use constant TOURNAMENT_RESULTS_TABLE_NAME => 'tournament_results';
use constant PLAYER_RESULTS_TABLE_NAME     => 'player_results';
use constant LEXICONS_TABLE_NAME           => 'lexicons';
use constant LOADED_TOURNAMENTS_TABLE_NAME => 'loaded_tournaments';

use constant MASTER_RATINGS_LIST        => 'rating.dat';

use constant REMOVED_NAMES_FILE           => 'removed_names.log';
use constant DUPLICATE_NAMES_FILE         => 'duplicate_names.log';
use constant INCORRECT_NAME_MAPPINGS_FILE => 'incorrect_name_mappings.log';
use constant INPUT_MERGE_FILE             => 'duplicates.txt';
use constant DECEASED_PLAYERS             => 'removed_people.txt';

use constant PROVISIONAL_GAMES_MAX      => 50;
use constant CURRENT_GAMES_MIN          => 40;
use constant PHOTO_DIR                  => '/var/www/html/wordpress/aardvark/icons';

use constant DEFAULT_BYE_SCORE          => 1350;

use constant ROUNDING_PLACE             => 2;

use constant TABLES =>
{
  Constants::LOADED_TOURNAMENTS_TABLE_NAME =>
  [
   "id                 INT NOT NULL AUTO_INCREMENT",
   "name               VARCHAR(255)",
   "filename           VARCHAR(255)",

   "PRIMARY KEY (id)"
  ],
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
			    "title		VARCHAR(3)",
			    "norms		VARCHAR(3)",

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
                            "name       VARCHAR(255)",
                            "country    VARCHAR(3)",
                            "filename   VARCHAR(255)",

                            "PRIMARY KEY (id)",
                            "FOREIGN KEY (event_id) REFERENCES events(id)",
                            "INDEX idx_tournaments_filename (filename)"
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
                            "id                INT NOT NULL AUTO_INCREMENT",
                            "division_id       INT NOT NULL",
                            "player_id         INT NOT NULL",
                            "player_name       VARCHAR(255)",
                            "position          INT",
                            "wins              FLOAT",
                            "losses            FLOAT",
                            "byes              INT",
                            "spread            INT",
                            "prize_money       INT",
                            "prize_currency    VARCHAR(255)",
                            "prize_ech_rate    VARCHAR(255)",
                            "start_rating      INT",
                            "end_rating        INT",
                            "date              DATE",
                            "tournament_name   VARCHAR(255)",

                            "expected_wins     FLOAT",
                            "old_world_rank    INT",
                            "new_world_rank    INT",
                            "old_national_rank INT",
                            "new_national_rank INT",
                            "old_rating_dev    INT",
                            "new_rating_dev    INT",

                            "PRIMARY KEY (id)",
                            "FOREIGN KEY (division_id) REFERENCES divisions(id)",
                            "FOREIGN KEY (player_id)   REFERENCES players(id)",
                            "INDEX idx_tr_player_date (player_id, date)"
                          ],
  Constants::PLAYER_RESULTS_TABLE_NAME     => [
                            "id        INT NOT NULL AUTO_INCREMENT",
                            "player_id INT NOT NULL",
                            "game_id   INT NOT NULL",
                            "score     INT",
                            "result    INT",

                            "PRIMARY KEY (id)",
                            "FOREIGN KEY (player_id) REFERENCES players(id)",
                            "FOREIGN KEY (game_id) REFERENCES games(id)",
                            "INDEX idx_pr_player_score_result_game (player_id, score, result, game_id)",
                            "INDEX idx_pr_game_player_score (game_id, player_id, score)"
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
                       Constants::PLAYER_RESULTS_TABLE_NAME,
                       Constants::LOADED_TOURNAMENTS_TABLE_NAME
                     ];

use constant TABLE_DROP_EXCEPTIONS =>
{
  Constants::PLAYERS_TABLE_NAME             => 1,
  Constants::PLAYER_ALT_NAMES_TABLE_NAME    => 1,
  Constants::EVENTS_TABLE_NAME              => 1,
  Constants::TOURNAMENTS_TABLE_NAME         => 1,
  Constants::DIVISIONS_TABLE_NAME           => 1,
  Constants::GAMES_TABLE_NAME               => 1,
  Constants::TOURNAMENT_RESULTS_TABLE_NAME  => 1,
  Constants::PLAYER_RESULTS_TABLE_NAME      => 1,
  Constants::LEXICONS_TABLE_NAME            => 1
};

use constant LEXICONS => [
                 {"name" => "CSW07"},
                 {"name" => "CSW12"},
                 {"name" => "CSW15"},
               ];


use constant GAME_STATS_RANK_NAME => 'rank';
use constant STAT_KEY_NAME        => 'stat';
use constant ALLTIME_CUTOFF       => 60;

use constant TOURNAMENT_STATS_ORDER => ['High Win', 'High Loss', 'High Spread', 'High Combined', 'Upsets'];

use constant COUNTRY_TRIGRAPH_TO_COUNTRY_NAME_HASHREF =>
{
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
  'IDN' => 'Indonesia',
  'IND' => 'India',
  'IOT' => 'British Indian Ocean Territory',
  'UMI' => 'U.S. Minor Outlying Islands',
  'IRN' => 'Iran',
  'IMN' => 'Isle of Man',
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

use constant COUNTRY_TRIGRAPH_CONVERSION =>
{
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
  # distinctly in the data. Note that
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
  'SUI' => 'CHE',
  'SPA' => 'ESP',
  'SRI' => 'LKA'
};

1;


