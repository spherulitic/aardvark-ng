#!/bin/bash
#
# Aardvark update wrapper (runs on the production host).
#
# Builds the tournament database into the staging schema, verifies it, takes a
# rollback snapshot of production, then promotes staging -> production.
#
# Usage:
#   deploy/update.sh [--full] [--no-promote] [--verify-only]
#
#   --full          full rebuild (AARDVARK_INCREMENTAL=0); default is incremental
#   --no-promote    build + verify only; do not snapshot or promote
#   --verify-only   skip build/run; only sanity-check the current staging schema
#
# Config (secrets) live outside the repo:
#   /etc/aardvark/aardvark.env   - AARDVARK_* env for the container
#   /etc/aardvark/mysql.cnf      - [client] host/port/user/password/ssl for the
#                                  host mysqldump/mysql client (host CA path)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${AARDVARK_ENV_FILE:-/etc/aardvark/aardvark.env}"
MYSQL_CNF="${AARDVARK_MYSQL_CNF:-/etc/aardvark/mysql.cnf}"
CA_HOST="${AARDVARK_CA_HOST:-/etc/aardvark/ca-certificate.crt}"
SNAPSHOT_DIR="${AARDVARK_SNAPSHOT_DIR:-/srv/snapshots}"
LOG_DIR="${AARDVARK_LOG_DIR:-/var/log/aardvark}"
TOURNAMENT_DATA="${AARDVARK_TOURNAMENT_DATA:-/srv/aardvark}"
FRESHNESS_DAYS="${AARDVARK_FRESHNESS_DAYS:-30}"
IMAGE="aardvark-ng:latest"

LAST_GOOD="$SNAPSHOT_DIR/last_good.sha256"
RUN_LOG="$LOG_DIR/update-$(date --iso-8601).log"
STAMP="$(date +%Y%m%d_%H%M%S)"

MODE=incremental
PROMOTE=1
VERIFY_ONLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --full)         MODE=full ;;
    --no-promote)   PROMOTE=0 ;;
    --verify-only)  VERIFY_ONLY=1 ;;
    --incremental)  MODE=incremental ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ "$MODE" = "full" ]; then INCREMENTAL=0; else INCREMENTAL=1; fi

mkdir -p "$LOG_DIR"

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "$RUN_LOG"; }

get_env() { awk -F= -v k="$1" '$1==k {sub(/^[^=]*=/,""); print}' "$ENV_FILE"; }

fail() { log "ERROR: $*"; exit 1; }

dump_checksum() {
  local db="$1"
  mysqldump --defaults-extra-file="$MYSQL_CNF" \
    --single-transaction --no-tablespaces --set-gtid-purged=OFF "$db" \
    | perl -ne 'next if /^-- (?:Dump completed on|Host:)/; s/AUTO_INCREMENT=\d+/AUTO_INCREMENT=0/; print' \
    | sha256sum | awk '{print $1}'
}

sanity_check() {
  local db="$1"
  local sql
  sql="SELECT (SELECT COUNT(*) FROM tournaments) AS tournaments,
               (SELECT COUNT(*) FROM players) AS players,
               (SELECT COUNT(*) FROM divisions) AS divisions,
               (SELECT COUNT(*) FROM games) AS games,
               (SELECT COUNT(*) FROM player_results) AS player_results,
               (SELECT COUNT(*) FROM tournament_results) AS tournament_results,
               (SELECT COUNT(*) FROM divisions d LEFT JOIN tournaments t ON d.tournament_id=t.id WHERE t.id IS NULL) AS orphan_divisions,
               (SELECT COUNT(*) FROM tournament_results tr LEFT JOIN divisions d ON tr.division_id=d.id WHERE d.id IS NULL) AS orphan_tr_div,
               (SELECT COUNT(*) FROM player_results pr LEFT JOIN games g ON pr.game_id=g.id WHERE g.id IS NULL) AS orphan_pr_game;"
  mysql --defaults-extra-file="$MYSQL_CNF" --batch --raw -N -e "$sql" "$db"
}

# --verify-only ------------------------------------------------------------
if [ "$VERIFY_ONLY" = "1" ]; then
  STAGING_DB="$(get_env AARDVARK_DB_NAME)"
  [ -n "$STAGING_DB" ] || fail "AARDVARK_DB_NAME not set in $ENV_FILE"
  log "verify-only: staging=$STAGING_DB"
  sanity_check "$STAGING_DB"
  log "staging checksum: $(dump_checksum "$STAGING_DB")"
  exit 0
fi

cd "$REPO_DIR"

# 1. Sync code -------------------------------------------------------------
log "pulling $REPO_DIR"
git pull --ff-only >/dev/null 2>>"$RUN_LOG" || fail "git pull failed"
log "HEAD: $(git rev-parse --short HEAD)"

# 1.5 Rename .STA -> .ST4 on the host (rootless podman does not pass through
#     the user's supplementary groups, so do this where permissions are right)
log "renaming .STA -> .ST4"
python3 "$REPO_DIR/scripts/rename_sta_to_st4.py" "$TOURNAMENT_DATA" --execute >>"$RUN_LOG" 2>&1 || log "WARN: rename step reported errors"

# 2. Input freshness (warning only) ----------------------------------------
DUP_FILE="/var/www/wespa/html/duplicates.txt"
if [ -f "$DUP_FILE" ]; then
  age_days=$(( ($(date +%s) - $(stat -c %Y "$DUP_FILE")) / 86400 ))
  if [ "$age_days" -gt "$FRESHNESS_DAYS" ]; then
    log "WARN: duplicates.txt is $age_days days old (> $FRESHNESS_DAYS)"
  fi
else
  log "WARN: duplicates.txt not found at $DUP_FILE"
fi

# 3. Build image -----------------------------------------------------------
log "building image $IMAGE"
podman build . -t "$IMAGE" >>"$RUN_LOG" 2>&1 || fail "podman build failed"

# 4. Build staging schema --------------------------------------------------
log "running migration (mode=$MODE)"
set +e
podman run --rm --name aardvark-updater \
  --env-file "$ENV_FILE" \
  -e AARDVARK_INCREMENTAL="$INCREMENTAL" \
  -v "$TOURNAMENT_DATA":/app/tournament_data \
  -v "$CA_HOST":/certs/ca-certificate.crt:ro \
  -v "$LOG_DIR":/app/logs \
  -v /var/www/wespa/html/latest.txt:/app/inputs/latest.txt:ro \
  -v /var/www/wespa/html/duplicates.txt:/app/inputs/duplicates.txt:ro \
  -v /srv/wespa/removed_people.txt:/app/inputs/removed_people.txt:ro \
  --network host "$IMAGE" >>"$RUN_LOG" 2>&1
RUN_RC=$?
set -e
[ "$RUN_RC" -eq 0 ] || fail "container run exited $RUN_RC"
grep -q "Processing Complete" "$RUN_LOG" || fail "build did not complete"

STAGING_DB="$(get_env AARDVARK_DB_NAME)"
PROD_DB="$(get_env AARDVARK_PROD_DB_NAME)"
[ -n "$STAGING_DB" ] && [ -n "$PROD_DB" ] || fail "DB names not set in $ENV_FILE"

# 5. Verify staging --------------------------------------------------------
log "verifying staging $STAGING_DB"
sanity_check "$STAGING_DB" | tee -a "$RUN_LOG"

if [ "$MODE" = "full" ]; then
  staging_sum="$(dump_checksum "$STAGING_DB")"
  if [ -f "$LAST_GOOD" ]; then
    want="$(awk '{print $1}' "$LAST_GOOD")"
    [ "$staging_sum" = "$want" ] || fail "staging checksum mismatch (got $staging_sum, want $want)"
    log "full-run checksum matches last_good"
  else
    log "no last_good yet; will bootstrap after promote"
  fi
fi

if [ "$PROMOTE" = "0" ]; then
  log "no-promote: skipping snapshot and promotion"
  exit 0
fi

# 6. Snapshot production ---------------------------------------------------
mkdir -p "$SNAPSHOT_DIR"
snap="$SNAPSHOT_DIR/wespa_$STAMP.sql"
log "snapshotting $PROD_DB -> $snap"
mysqldump --defaults-extra-file="$MYSQL_CNF" \
  --single-transaction --no-tablespaces --set-gtid-purged=OFF "$PROD_DB" > "$snap" \
  || fail "snapshot failed"

# 7. Promote ---------------------------------------------------------------
log "promoting $STAGING_DB -> $PROD_DB"
mysqldump --defaults-extra-file="$MYSQL_CNF" \
  --single-transaction --no-tablespaces --set-gtid-purged=OFF "$STAGING_DB" \
  | mysql --defaults-extra-file="$MYSQL_CNF" "$PROD_DB" || fail "promote failed"

# 8. Post-verify -----------------------------------------------------------
log "post-promote verification"
prod_sum="$(dump_checksum "$PROD_DB")"
[ "$prod_sum" = "$staging_sum" ] || fail "prod checksum != staging checksum"

if [ "$MODE" = "full" ]; then
  printf '%s  %s\n' "$staging_sum" "$(date -Iseconds)" > "$LAST_GOOD"
  log "bootstrapped/updated last_good: $staging_sum"
fi

# 9. Retention -------------------------------------------------------------
find "$SNAPSHOT_DIR" -name 'wespa_*.sql' -mtime +30 -delete 2>/dev/null || true

log "DONE"
