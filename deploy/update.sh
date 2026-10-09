#!/bin/bash
#
# Aardvark update wrapper (runs on the production host).
#
# Builds the tournament database into the staging schema, verifies it, takes a
# rollback snapshot of production, then promotes staging -> production.
#
# Safety: the promote step is gated on several checks. A structurally broken
# staging schema (empty/zero tables or orphan rows) or one that has lost data
# relative to the current production baseline will abort BEFORE promotion, so
# production can never be overwritten by a failed build.
#
# After each successful promote it also writes the static player-data JSON that
# the web front end serves (scripts/emit_players_json.py), keeping the old
# generation as players.json.prev for rollback.
#
# Usage:
#   deploy/update.sh [--full] [--no-promote] [--verify-only] [--require-baseline-match]
#
#   --full                    full rebuild (AARDVARK_INCREMENTAL=0); default is incremental
#   --no-promote              build + verify only; do not snapshot or promote
#   --verify-only             skip build/run; only run the verification gates on staging
#   --require-baseline-match  (--full only) assert that the rebuilt schema's checksum
#                             equals $SNAPSHOT_DIR/last_good.sha256. This is a
#                             determinism test for rebuilds with unchanged inputs,
#                             NOT a routine promotion gate.
#
# A routine --full run advances last_good.sha256 (the normalized-dump checksum of
# the last successful full promote) instead of being blocked by it. It is gated
# only by the structural and drift checks above.
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
PLAYERS_JSON_DIR="${AARDVARK_PLAYERS_JSON_DIR:-/var/www/wespa/html}"
IMAGE="aardvark-ng:latest"

PLAYERS_JSON="$PLAYERS_JSON_DIR/players.json"
PLAYER_IDS_QUERY="SELECT id AS playerid, name, country, rating AS cswrating
                    FROM players WHERE COALESCE(total_games,0) > 0 ORDER BY id"
PLAYER_COUNT_QUERY="SELECT COUNT(*) FROM players WHERE COALESCE(total_games,0) > 0"

LAST_GOOD="$SNAPSHOT_DIR/last_good.sha256"
RUN_LOG="$LOG_DIR/update-$(date --iso-8601).log"
STAMP="$(date +%Y%m%d_%H%M%S)"

MODE=incremental
PROMOTE=1
VERIFY_ONLY=0
REQUIRE_BASELINE_MATCH=0

while [ $# -gt 0 ]; do
  case "$1" in
    --full)                    MODE=full ;;
    --no-promote)              PROMOTE=0 ;;
    --verify-only)             VERIFY_ONLY=1 ;;
    --incremental)             MODE=incremental ;;
    --require-baseline-match)  REQUIRE_BASELINE_MATCH=1 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ "$MODE" = "full" ]; then INCREMENTAL=0; else INCREMENTAL=1; fi

if [ "$REQUIRE_BASELINE_MATCH" = "1" ]; then
  [ "$MODE" = "full" ] || { echo "--require-baseline-match requires --full" >&2; exit 2; }
  [ -f "$LAST_GOOD" ] || { echo "--require-baseline-match: no baseline at $LAST_GOOD" >&2; exit 2; }
fi

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

# One line of 9 tab-separated counts:
# tournaments players divisions games player_results tournament_results
# orphan_divisions orphan_tr_div orphan_pr_game
sanity_check() {
  local db="$1"
  mysql --defaults-extra-file="$MYSQL_CNF" --batch --raw -N -e \
    "SELECT (SELECT COUNT(*) FROM tournaments),
            (SELECT COUNT(*) FROM players),
            (SELECT COUNT(*) FROM divisions),
            (SELECT COUNT(*) FROM games),
            (SELECT COUNT(*) FROM player_results),
            (SELECT COUNT(*) FROM tournament_results),
            (SELECT COUNT(*) FROM divisions d LEFT JOIN tournaments t ON d.tournament_id=t.id WHERE t.id IS NULL),
            (SELECT COUNT(*) FROM tournament_results tr LEFT JOIN divisions d ON tr.division_id=d.id WHERE d.id IS NULL),
            (SELECT COUNT(*) FROM player_results pr LEFT JOIN games g ON pr.game_id=g.id WHERE g.id IS NULL);" \
    "$db"
}

counts()  { sanity_check "$1" | awk '{print $1, $2, $3, $4, $5, $6}'; }
orphans() { sanity_check "$1" | awk '{print $7, $8, $9}'; }

# Explain a full-run baseline mismatch: staging vs the pre-build production
# counts, plus tournament inputs newer than the recorded baseline timestamp.
baseline_drift_summary() {
  local baseline_ts="$1" prod="$2" staging="$3"
  local pt pp pd pg ppr ptr t p d g pr tr
  read -r pt pp pd pg ppr ptr <<< "$prod"
  read -r t p d g pr tr <<< "$staging"
  log "baseline drift summary (production -> staging):"
  log "  tournaments        $pt -> $t"
  log "  players            $pp -> $p"
  log "  divisions          $pd -> $d"
  log "  games              $pg -> $g"
  log "  player_results     $ppr -> $pr"
  log "  tournament_results $ptr -> $tr"
  if [ -n "$baseline_ts" ] && [ -d "$TOURNAMENT_DATA" ]; then
    log "  tournament inputs newer than baseline ($baseline_ts):"
    find "$TOURNAMENT_DATA" \
      \( -iname '*.tou' -o -iname '*.sts' -o -iname '*.sta' -o -iname '*.st4' \) \
      -newermt "$baseline_ts" -printf '%TY-%Tm-%Td %TH:%TM %p\n' 2>/dev/null \
      | sort | sed 's/^/    /' | tee -a "$RUN_LOG" || true
  fi
}

# Structural gate: every core table must be non-empty and have no orphans.
verify_struct() {
  local db="$1"
  local c o
  c="$(counts "$db")" || return 1
  o="$(orphans "$db")" || return 1
  local t p d g pr tr odiv otrd oprg
  read -r t p d g pr tr <<< "$c"
  read -r odiv otrd oprg <<< "$o"
  log "  $db: tournaments=$t players=$p divisions=$d games=$g player_results=$pr tournament_results=$tr orphans=$odiv/$otrd/$oprg"

  local bad=0
  [ "${t:-0}"  -gt 0 ] || { log "  ERROR: tournaments=$t"; bad=1; }
  [ "${p:-0}"  -gt 0 ] || { log "  ERROR: players=$p"; bad=1; }
  [ "${d:-0}"  -gt 0 ] || { log "  ERROR: divisions=$d"; bad=1; }
  [ "${g:-0}"  -gt 0 ] || { log "  ERROR: games=$g"; bad=1; }
  [ "${pr:-0}" -gt 0 ] || { log "  ERROR: player_results=$pr"; bad=1; }
  [ "${tr:-0}" -gt 0 ] || { log "  ERROR: tournament_results=$tr"; bad=1; }
  [ "${odiv:-0}" -eq 0 ] || { log "  ERROR: orphan divisions=$odiv"; bad=1; }
  [ "${otrd:-0}" -eq 0 ] || { log "  ERROR: orphan tournament_results=$otrd"; bad=1; }
  [ "${oprg:-0}" -eq 0 ] || { log "  ERROR: orphan player_results=$oprg"; bad=1; }
  return "$bad"
}

STAGING_DB="$(get_env AARDVARK_DB_NAME)"
PROD_DB="$(get_env AARDVARK_PROD_DB_NAME)"
[ -n "$STAGING_DB" ] && [ -n "$PROD_DB" ] || fail "DB names not set in $ENV_FILE"

# --verify-only ------------------------------------------------------------
if [ "$VERIFY_ONLY" = "1" ]; then
  log "verify-only: staging=$STAGING_DB prod=$PROD_DB"
  PROD_BASE="$(counts "$PROD_DB")"
  verify_struct "$PROD_DB" || fail "production schema is broken"
  verify_struct "$STAGING_DB" || log "staging schema is broken (expected if no build yet)"
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

# Capture the current production baseline BEFORE the build, for drift checks.
log "production baseline (t p d g pr tr):"
PROD_BASE="$(counts "$PROD_DB")"

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

# 5. Verify staging (structural + drift gates) -----------------------------
log "verifying staging $STAGING_DB"
verify_struct "$STAGING_DB" || fail "staging schema failed structural checks -- NOT promoting"

read -r pt pp pd pg ppr ptr <<< "$PROD_BASE"
read -r t p d g pr tr <<< "$(counts "$STAGING_DB")"

# Drift gate: staging must not have lost tournaments or a large share of games
# relative to the production baseline it is about to replace.
[ "${t:-0}" -ge "${pt:-0}" ] \
  || fail "staging tournaments $t < production $pt -- NOT promoting"
min_games=$(( ${pg:-0} * 95 / 100 ))
[ "${g:-0}" -ge "$min_games" ] \
  || fail "staging games $g < 95% of production ($min_games) -- NOT promoting"

staging_sum="$(dump_checksum "$STAGING_DB")"
log "staging checksum: $staging_sum"

if [ "$MODE" = "full" ] && [ -f "$LAST_GOOD" ]; then
  want="$(awk '{print $1}' "$LAST_GOOD")"
  baseline_ts="$(awk '{print $2}' "$LAST_GOOD")"
  if [ "$staging_sum" = "$want" ]; then
    log "full-run checksum matches last_good"
  else
    baseline_drift_summary "$baseline_ts" "$PROD_BASE" "$t $p $d $g $pr $tr"
    if [ "$REQUIRE_BASELINE_MATCH" = "1" ]; then
      fail "staging checksum mismatch (got $staging_sum, want $want)"
    fi
    log "accepting baseline drift on full run; last_good advances after a successful promote"
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
log "prod checksum matches staging"

if [ "$MODE" = "full" ]; then
  prev_sum=""
  if [ -f "$LAST_GOOD" ]; then
    prev_sum="$(awk '{print $1}' "$LAST_GOOD")"
  fi
  printf '%s  %s\n' "$staging_sum" "$(date -Iseconds)" > "$LAST_GOOD"
  if [ -n "$prev_sum" ] && [ "$prev_sum" != "$staging_sum" ]; then
    log "last_good advanced: $prev_sum -> $staging_sum"
  else
    log "last_good unchanged: $staging_sum"
  fi
fi

# 8b. Publish static player JSON (retires players.php?idsonly=1) -----------
# The front end fetches this build artifact instead of hitting the API on every
# page load. Because it is written by the promote it cannot go stale; the old
# generation is kept as players.json.prev for a one-command rollback.
log "publishing static player JSON"
[ -d "$PLAYERS_JSON_DIR" ] || fail "player JSON dir $PLAYERS_JSON_DIR does not exist"

expected="$(mysql --defaults-extra-file="$MYSQL_CNF" --batch --raw -N \
  -e "$PLAYER_COUNT_QUERY" "$PROD_DB")" \
  || fail "could not count players in $PROD_DB"

mysql --defaults-extra-file="$MYSQL_CNF" --default-character-set=utf8mb4 \
  --batch --raw -N -e "$PLAYER_IDS_QUERY" "$PROD_DB" \
  | python3 "$REPO_DIR/scripts/emit_players_json.py" "$PLAYERS_JSON.tmp" "$expected" \
  || fail "player JSON generation failed"

if [ -f "$PLAYERS_JSON" ]; then
  mv -f "$PLAYERS_JSON" "$PLAYERS_JSON.prev"
fi
mv -f "$PLAYERS_JSON.tmp" "$PLAYERS_JSON"

if gzip -c "$PLAYERS_JSON" > "$PLAYERS_JSON.gz.tmp"; then
  mv -f "$PLAYERS_JSON.gz.tmp" "$PLAYERS_JSON.gz"
else
  rm -f "$PLAYERS_JSON.gz.tmp"
  log "WARN: gzip of $PLAYERS_JSON failed; serving uncompressed only"
fi

log "player JSON published: $PLAYERS_JSON ($expected players)"

# 9. Retention -------------------------------------------------------------
find "$SNAPSHOT_DIR" -name 'wespa_*.sql' -mtime +30 -delete 2>/dev/null || true

log "DONE"
