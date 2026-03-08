#!/bin/bash

# Ensure the script is called with at least two arguments
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <database_name> <names_file> [--execute]"
    exit 1
fi

# Parse arguments
db_name="$1"
names_file="$2"
execute_mode=false

if [ "$#" -eq 3 ] && [ "$3" == "--execute" ]; then
    execute_mode=true
fi

# Check if the names file exists
if [ ! -f "$names_file" ]; then
    echo "Error: File '$names_file' does not exist."
    exit 1
fi

# Read names from the file
mapfile -t names < "$names_file"

# MySQL credentials
mysql_user="wespa"
mysql_password="nigeltheking"

# Construct the queries
name_list="$(printf "%s','" "${names[@]}" | sed "s/','$//")"

# First delete from player_results
query_player_results="DELETE FROM player_results WHERE player_id IN (SELECT id FROM players WHERE name IN ('$name_list'));"

# Then delete from tournament_results
query_tournament_results="DELETE FROM tournament_results WHERE player_id IN (SELECT id FROM players WHERE name IN ('$name_list'));"

# Finally delete from players
query_players="DELETE FROM players WHERE name IN ('$name_list');"

# Dry run output
echo "Dry run: The following queries would be executed:"
echo "$query_player_results"
echo "$query_tournament_results"
echo "$query_players"

# Execute the queries if in execute mode
if [ "$execute_mode" = true ]; then
    echo "Executing queries..."
    mysql -u "$mysql_user" -p"$mysql_password" -D "$db_name" -e "$query_player_results"

    if [ $? -ne 0 ]; then
        echo "Failed to delete rows from player_results. Check your input or database connection."
        exit 1
    fi

    mysql -u "$mysql_user" -p"$mysql_password" -D "$db_name" -e "$query_tournament_results"

    if [ $? -ne 0 ]; then
        echo "Failed to delete rows from tournament_results. Check your input or database connection."
        exit 1
    fi

    mysql -u "$mysql_user" -p"$mysql_password" -D "$db_name" -e "$query_players"

    if [ $? -eq 0 ]; then
        echo "Rows successfully deleted."
    else
        echo "Failed to delete rows from players. Check your input or database connection."
        exit 1
    fi
else
    echo "Dry run mode: No changes were made to the database."
fi

