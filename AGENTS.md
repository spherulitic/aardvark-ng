# AGENTS.md

Aardvark is the WESPA Scrabble rating system. It parses tournament files
(`.tou` + `.STS`/`.STA`/`.ST4`) into a MySQL database. Reports are served by an
API on top of the production database.

## Codebase layout

- **Pipeline:** `scripts/migrate.pl` and the helpers it `require`s
  (`correct_and_verify.pl`, `utils.pl`, `drop_all_wespa_tables.pl`,
  `record_db.pl`, `update_current_players.pl`, `update_player_titles.pl`),
  plus `scripts/update_tournament_data.sh` (Dockerfile CMD entrypoint).
- `modules/Constants.pm` holds the shared schema and configuration constants.
- The old Perl HTML-report harness (`modules/HTML.pm`, `Update.pm`,
  `Executive.pm`, `Utils.pm`, `objects/`, `test/`, the `./aardvark` symlink,
  `html_static/`, `css/`, `flags/`, `cgi-bin/`) has been removed — that
  capability is OBE now that reports come from the API.

## Running

Everything runs inside the `aardvark-ng` container image (podman/docker) — the
host Perl lacks `DBI`, `Devel::Timer`, `Perl::Critic`, etc. MySQL runs on the
host and the container uses `--network host` (see README.md run command). DB
config comes from `AARDVARK_*` env vars (gitignored `aardvark.env`):
`AARDVARK_DB_NAME` (staging, default `wespa_dev`), `AARDVARK_PROD_DB_NAME`
(production, default `wespa`), `AARDVARK_DB_HOST`/`_PORT`,
`AARDVARK_DB_USER`/`_PASSWORD`, and optional `AARDVARK_DB_SSL_MODE`
(e.g. `VERIFY_CA`) + `AARDVARK_DB_SSL_CA`. `Constants.pm` refuses to run if the
staging and production database names are identical.

Entry points:
- `scripts/update_tournament_data.sh` — full daily flow: rename `.STA`→`.ST4`
  (`rename_sta_to_st4.py`), `migrate.pl` (runs `--incremental` only when
  `AARDVARK_INCREMENTAL=1`), photo updates, then `mysqldump` backup to `/app/logs`.
- `scripts/migrate.pl [--incremental]` — main DB build. Options also include
  `-d/--directory`, `-y/--year`, `-c/--country`, `-f/--file` regex filters
  (pod docs at end of file).
- `scripts/correct_and_verify.pl --input=X.tou --output=Y.tou` — standalone
  `.tou` validator/corrector.

The `.tou` file format (game/score/bye/forfeit encoding) is documented in
`TOU_spec.md` at the repo root.

## Database connection

All scripts connect through `connect_to_database()` (`scripts/utils.pl`), which
reads the `AARDVARK_DB_*` vars and supports TLS (`AARDVARK_DB_SSL_MODE` +
`AARDVARK_DB_SSL_CA`). Shelled-out `mysqldump`/`mysql` calls use
`database_cli_options()` for the same host/port/TLS settings. The old
cwd-based `get_environment_name()` dev-suffix magic has been removed; database
names are explicit in the environment.

## Database flow

`migrate.pl` builds tables (schema in `Constants::TABLES`, creation order in
`Constants::TABLE_CREATION_ORDER`) into the staging DB (`AARDVARK_DB_NAME`).
Promotion to production (`AARDVARK_PROD_DB_NAME`) is done outside the container
by the host-side update wrapper (`mysqldump … | mysql …`), not by `migrate.pl`.
The API serves reports read-only from production.

`--incremental` mode: does NOT drop tables, does NOT re-read
`inputs/duplicates.txt` into `player_alt_names`, does NOT re-insert lexicons;
skips any `.tou` already recorded in the `loaded_tournaments` table. Any
duplicates.txt/name-mapping change requires a full (non-incremental) run.

Promotion on the production host is driven by `deploy/update.sh`, gated by a
structural check (non-empty core tables, no orphans) and a drift check (no lost
tournaments, no >5% loss of games vs production). `$SNAPSHOT_DIR/last_good.sha256`
holds the normalized-dump checksum of the last successful **full** promote; a
routine `--full` run advances it rather than being blocked by it. The
`--require-baseline-match` flag (full only) asserts a byte-identical rebuild and
is a determinism test for unchanged inputs, not part of the routine flow. See
README.md for details.

After each successful promote, `deploy/update.sh` also regenerates the static
player list served by the front end (`$PLAYERS_JSON_DIR/players.json`, default
`/var/www/wespa/html/players.json`) via `scripts/emit_players_json.py`, keeping
the previous file as `players.json.prev` and a gzip as `players.json.gz`. It is
written atomically and validated (JSON parses, row count matches the DB) before
the swap; this retires the per-page-load `players.php?idsonly=1` API call.

## Input data

- Tournament files live at `/app/tournament_data/<year>/<country-trigraph>/<name>.tou`
  with sibling `.STS` (preferred) or `.STA`/`.ST4`. This directory is a host
  mount, not present in the repo.
- `inputs/duplicates.txt` — name merges, one per line, comma-separated,
  canonical name first; `#` comments. Read only in full runs.
- `inputs/removed_people.txt` — deceased players. `inputs/tou_ignore_errors.txt`
  — per-file error-suppression list. `inputs/titles.csv`, `inputs/latest.txt`,
  `inputs/*.txt`/`.csv` photo sources also feed updates.
- Names are normalized by `sanitize()` (uppercase, strip non-A-Z) and
  `make_pretty()`; a name containing `BYE` (except RUSSELLBYERS) is treated as a bye.

## Repo hygiene

- The root-level `wespa_*.sql` dumps (~57MB each) and `output.log` are untracked
  artifacts — never commit them.
- `*.env` is gitignored; `aardvark.env` holds live DB credentials and is
  untracked.
- No CI config and no lint/test command for the `scripts/` pipeline exists.
