Code and data to modernise Aardvark, the WESPA rating system.

Container intended to be executed with:

podman run --rm \
  --name aardvark-ng \
  -v /srv/wespa/tournament_data:/app/tournament_data \
  -v /var/www/html/aardvark:/app/html_data \
  -v /var/log/aardvark:/app/logs \
  --network host \
  aardvark-ng:latest

where /srv/wespa/tournament_data holds .tou, .sts. etc files
/var/www/html/aardvark is the directory to serve generated HTML files from
/var/log/aardvark exists on the host to store logs
MySQL is running on the host

