#!/bin/bash

cd /app

LOGNAME=$(date --iso-8601)
LOGFULLNAME="/app/logs/daily-cronjob-$LOGNAME.log"

# Ensure log directory exists
mkdir -p /app/logs

echo "Processing Beginning " && date | tee -a "$LOGFULLNAME"
echo "Using mounted tournament data from /app/tournament_data" | tee -a "$LOGFULLNAME"

# Rename .STA to .ST4 files (now with write access to mounted volume)
python3 ./scripts/rename_sta_to_st4.py /app/tournament_data/ --execute 2>&1 | tee -a "$LOGFULLNAME"

# Run Perl scripts
perl ./scripts/migrate.pl --html 2>&1 | tee -a "$LOGFULLNAME"
perl ./scripts/deploy.pl 2>&1 | tee -a "$LOGFULLNAME"

echo "Processing Complete " && date | tee -a "$LOGFULLNAME"
