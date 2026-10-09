#!/usr/bin/env python3
"""Emit the static player-data JSON consumed by the web front end.

Reads tab-separated rows (playerid, name, country, cswrating) on stdin, as
produced by `mysql --batch --raw -N`, and writes {"players": [...]} to the
given temporary path. The file is re-read and the row count checked before the
script exits; the caller then renames it into place atomically.

This mirrors the payload of `GET /players.php?idsonly=1` so the front end can
fetch a build artifact instead of hammering the API on every page load.

Usage:
    emit_players_json.py <output-path> <expected-count> < rows.tsv
"""

import json
import os
import sys

NULL = "NULL"


def parse_int(value):
    if value == NULL or value == "":
        return None
    return int(value)


def remove(path):
    try:
        os.unlink(path)
    except OSError:
        pass


def main(argv):
    if len(argv) != 3:
        print("usage: emit_players_json.py <output-path> <expected-count>",
              file=sys.stderr)
        return 2

    out_path = argv[1]
    try:
        expected = int(argv[2])
    except ValueError:
        print(f"ERROR: expected count is not an integer: {argv[2]!r}",
              file=sys.stderr)
        return 2

    players = []
    for line in sys.stdin:
        line = line.rstrip("\n")
        if not line:
            continue
        fields = line.split("\t")
        if len(fields) != 4:
            print(f"ERROR: expected 4 tab-separated fields, got {len(fields)}",
                  file=sys.stderr)
            return 1
        playerid, name, country, cswrating = fields
        try:
            player = {
                "playerid": int(playerid),
                "name": name,
                "country": None if country == NULL else country,
                "cswrating": parse_int(cswrating),
            }
        except ValueError as exc:
            print(f"ERROR: bad numeric field in row {line!r}: {exc}",
                  file=sys.stderr)
            return 1
        players.append(player)

    if len(players) != expected:
        print(f"ERROR: read {len(players)} players, expected {expected}",
              file=sys.stderr)
        return 1

    document = {"players": players}
    with open(out_path, "w", encoding="utf-8") as handle:
        json.dump(document, handle, ensure_ascii=False, separators=(",", ":"))
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())

    try:
        with open(out_path, encoding="utf-8") as handle:
            check = json.load(handle)
    except (OSError, ValueError) as exc:
        print(f"ERROR: wrote invalid JSON to {out_path}: {exc}", file=sys.stderr)
        remove(out_path)
        return 1

    if len(check.get("players", [])) != expected:
        print(f"ERROR: {out_path} does not contain {expected} players",
              file=sys.stderr)
        remove(out_path)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
