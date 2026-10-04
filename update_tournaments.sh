echo rsync tournament data
rsync -av --ignore-existing --progress aardvark:/srv/aardvark/2026/ /srv/tournament_data/2026/ | grep [tT][oO][uU]
echo get latest.txt
scp aardvark:/var/www/wespa/html/latest.txt inputs/latest.txt
echo get duplicates.txt
scp kyubey:/home/spherulitic/.hermes/wespa/duplicates.txt inputs/duplicates.txt
echo build container
podman build . -t aardvark-ng
podman run --rm   --name aardvark-updater   --env-file aardvark.env   -e AARDVARK_INCREMENTAL=0   -v /srv/tournament_data:/app/tournament_data -v /var/log/aardvark:/app/logs   --network host   aardvark-ng:latest
SQLNAME=wespa_$(date +%Y%m%d).sql
sudo mysqldump wespa > $SQLNAME
scp $SQLNAME xerafin3:$SQLNAME
echo SSH to xerafin3 
ssh xerafin3
