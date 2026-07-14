#!/bin/bash
set -e

if [ "$AARDVARK_INCREMENTAL" = "1" ]; then
    exec /app/scripts/migrate.pl --incremental
else
    exec /app/scripts/update_tournament_data.sh
fi
