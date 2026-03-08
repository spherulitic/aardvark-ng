
cd /home/jcastellano/aardvark-ng

LOGNAME=$(date --iso-8601)
LOGFULLNAME="./logs/daily-cronjob-$LOGNAME.log"

echo "Processing Beginning " && date >> "$LOGFULLNAME" 2>&1

python3 ./scripts/copy_tournament_files.py /var/www/html/wordpress/aardvark /srv/dev/tournament_data --execute
python3 ./scripts/rename_sta_to_st4.py /srv/dev/tournament_data/ --execute
perl ./scripts/migrate.pl --html  >> "$LOGFULLNAME" 2>&1
perl ./scripts/deploy.pl          >> "$LOGFULLNAME" 2>&1

echo "Processing Complete " && date >> "$LOGFULLNAME" 2>&1

