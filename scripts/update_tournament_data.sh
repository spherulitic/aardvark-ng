#!/bin/bash

cd /app

LOGNAME=$(date --iso-8601)
LOGFULLNAME="/app/logs/daily-cronjob-$LOGNAME.log"
DUMPFILE="/app/logs/wespadb-$LOGNAME.sql"

# Ensure log directory exists
mkdir -p /app/logs

echo "Processing Beginning " && date | tee -a "$LOGFULLNAME"
echo "Using mounted tournament data from /app/tournament_data" | tee -a "$LOGFULLNAME"

# Rename .STA to .ST4 files (now with write access to mounted volume)
python3 ./scripts/rename_sta_to_st4.py /app/tournament_data/ --execute 2>&1 | tee -a "$LOGFULLNAME"

# Run Perl scripts
if [ "$AARDVARK_INCREMENTAL" = "1" ]; then
    perl ./scripts/migrate.pl --incremental 2>&1 | tee -a "$LOGFULLNAME"
else
    perl ./scripts/migrate.pl 2>&1 | tee -a "$LOGFULLNAME"
fi

# Update player photos from all available sources (lowest priority first)
PHOTOS_FILE="/app/inputs/photos.txt"
CENTRESTAR_PHOTOS="/app/inputs/centrestar_photos.txt"
BIODATA_CSV="/app/inputs/wespa_biodata.csv"

# Priority order (each overwrites the previous):
#   1. photos.txt        (lowest) -> /pix/...
#   2. centrestar_photos.txt       -> /pix/centrestar/...
#   3. wespa_biodata.csv  (highest) -> absolute URL

if [ -f "$PHOTOS_FILE" ]; then
    echo "Updating player photos from $PHOTOS_FILE" | tee -a "$LOGFULLNAME"
    perl ./scripts/update_player_photos.pl "$PHOTOS_FILE" 2>&1 | tee -a "$LOGFULLNAME"
else
    echo "No photos.txt found at $PHOTOS_FILE, skipping" | tee -a "$LOGFULLNAME"
fi

if [ -f "$CENTRESTAR_PHOTOS" ]; then
    echo "Updating player photos from $CENTRESTAR_PHOTOS" | tee -a "$LOGFULLNAME"
    perl ./scripts/update_player_photos.pl "$CENTRESTAR_PHOTOS" 2>&1 | tee -a "$LOGFULLNAME"
else
    echo "No centrestar_photos.txt found at $CENTRESTAR_PHOTOS, skipping" | tee -a "$LOGFULLNAME"
fi

if [ -f "$BIODATA_CSV" ]; then
    echo "Updating player photos from $BIODATA_CSV (highest priority)" | tee -a "$LOGFULLNAME"
    perl ./scripts/update_player_photos.pl "$BIODATA_CSV" 2>&1 | tee -a "$LOGFULLNAME"
else
    echo "No wespa_biodata.csv found at $BIODATA_CSV, skipping photo update" | tee -a "$LOGFULLNAME"
fi

mysqldump -u $AARDVARK_DB_USER -p$AARDVARK_DB_PASSWORD $AARDVARK_DB_NAME > $DUMPFILE

echo "Processing Complete " && date | tee -a "$LOGFULLNAME"
