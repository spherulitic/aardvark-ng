
cd /home/jcastellano/aardvark-ng

LOGNAME=$(date --iso-8601)
LOGFULLNAME="./logs/daily-cronjob-$LOGNAME.log"

echo "Processing Beginning " && date >> "$LOGFULLNAME" 2>&1

perl ./scripts/update_dev_data.pl >> "$LOGFULLNAME" 2>&1
perl ./scripts/migrate.pl --html  >> "$LOGFULLNAME" 2>&1
perl ./scripts/deploy.pl          >> "$LOGFULLNAME" 2>&1

echo "Processing Complete " && date >> "$LOGFULLNAME" 2>&1

