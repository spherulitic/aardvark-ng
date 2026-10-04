# Use a modern Debian base with both Perl and Python
FROM debian:bullseye-slim

# Install both Perl and Python from current repos, plus MySQL client
RUN apt-get update && apt-get install -y \
    perl \
    python3 \
    python3-pip \
    libdbd-mysql-perl \
    default-mysql-client \
    libtext-csv-xs-perl \
    && rm -rf /var/lib/apt/lists/*

RUN cpan -i Devel::Timer

WORKDIR /app
COPY . .
RUN ln -s /usr/bin/python3 /usr/bin/python
RUN mkdir -p /app/tournament_data /app/working /app/backups
RUN chmod +x /app/scripts/update_tournament_data.sh

CMD ["/app/scripts/update_tournament_data.sh"]
