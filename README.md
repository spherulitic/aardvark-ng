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
