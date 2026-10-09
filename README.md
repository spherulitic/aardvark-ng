Code and data to modernise Aardvark, the WESPA rating system.

Container intended to be executed with:

podman run --rm \
  --name aardvark-updater \
  --env-file aardvark.env \
  -v /srv/wespa/tournament_data:/app/tournament_data \
  -v /var/log/aardvark:/app/logs \
  --network host \
  aardvark-ng:latest


where /srv/wespa/tournament_data holds .tou, .sts. etc files
/var/log/aardvark exists on the host to store logs
MySQL is running on the host

## Running in incremental mode

By default, the migration script (`scripts/migrate.pl`) processes every tournament file found in the data directory, dropping and rebuilding the entire database (except player profiles). This is necessary when duplicate player profiles are discovered or when historical corrections are needed.

For routine updates (adding new tournament data), you can use the `--incremental` option to skip already‑loaded files and avoid dropping any tables:

```bash
perl scripts/migrate.pl --incremental
```

When `--incremental` is used:

- The `players`, `player_alt_names`, and `loaded_tournaments` tables are **not** dropped.
- The `lexicons` table is **not** re‑inserted (it already exists).
- Only tournament files that are **not** already recorded in the `loaded_tournaments` table are processed.
- The `duplicates.txt` file is **not** re‑read; any name‑mapping changes require a full (non‑incremental) run.

This mode is safe for daily or weekly updates and avoids reprocessing decades of historical data.

### Using environment variable in container

When running the container, set the environment variable `AARDVARK_INCREMENTAL=1` to enable incremental mode:

```bash
podman run --rm \
  --name aardvark-updater \
  --env-file aardvark.env \
  -e AARDVARK_INCREMENTAL=1 \
  -v /srv/wespa/tournament_data:/app/tournament_data \
  -v /var/log/aardvark:/app/logs \
  --network host \
  aardvark-ng:latest
```

If `AARDVARK_INCREMENTAL` is not set or is set to any value other than `1`, the container runs the full (whole‑hog) migration as before.

## Production updates (`deploy/update.sh`)

On the production host, `deploy/update.sh` builds into the staging schema, runs
the verification gates, snapshots production, and promotes staging →
production. Promotion is gated by:

- a **structural check** — every core table non-empty and no orphan rows; and
- a **drift check** — staging has not lost tournaments or more than 5% of games
  relative to production.

### The `last_good` baseline

`$SNAPSHOT_DIR/last_good.sha256` (default `/srv/snapshots/last_good.sha256`)
holds the normalized `mysqldump` checksum of the last successful full promote,
plus the timestamp it was written.

- It is written only by a successful `--full` promote; incremental runs do not
  touch it.
- A routine `--full` run **advances** it. When the rebuilt schema differs from
  the current baseline, the script logs a drift summary (staging vs production
  counts, plus tournament inputs newer than the baseline) and promotes anyway;
  the baseline is then rewritten. This is expected — a full run is how new data
  and historical corrections land.
- Because only full runs update the baseline, incremental additions are not in
  it, so it will legitimately differ after any incremental update. A full run
  with unchanged inputs since the last full run, however, should reproduce it.

### Determinism testing

`--require-baseline-match` (valid only with `--full`) turns that comparison back
into a hard assertion: the rebuilt staging checksum must equal the stored
baseline or the run aborts. Use it to verify a rebuild with **unchanged inputs**
is still byte-identical — a regression canary for the build, not part of the
routine update flow.

```bash
# rebuild without promoting, asserting the output is unchanged
deploy/update.sh --full --no-promote --require-baseline-match
```
