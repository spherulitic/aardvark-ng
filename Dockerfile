# Use a supported Debian base with Perl and Python
FROM debian:bookworm-slim

# Install Perl, Python, and the MySQL/MariaDB client + DBD drivers
RUN apt-get update && apt-get install -y \
    perl \
    python3 \
    libdbd-mysql-perl \
    default-mysql-client \
    libtext-csv-xs-perl \
    libdevel-timer-perl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY . .
RUN ln -s /usr/bin/python3 /usr/bin/python
RUN mkdir -p /app/tournament_data /app/working /app/backups
RUN chmod +x /app/scripts/update_tournament_data.sh

CMD ["/app/scripts/update_tournament_data.sh"]
