LOGNAME=$(date --iso-8601)
LOGFULLNAME="./logs/daily-cronjob-$LOGNAME.log"

cd /home/jcastellano/aardvark-ng

./scripts/update_dev_data.pl >> "$LOGFULLNAME" 2>&1
./scripts/migrate.pl --html  >> "$LOGFULLNAME" 2>&1

