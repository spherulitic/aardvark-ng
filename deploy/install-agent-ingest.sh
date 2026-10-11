#!/bin/bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "must run as root" >&2
  exit 1
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

install -o root -g root -m 0755 \
  "$REPO_DIR/deploy/systemd/aardvark-ingest@.service" \
  /etc/systemd/system/aardvark-ingest@.service

install -o root -g root -m 0755 \
  "$REPO_DIR/deploy/aardvark-ingest-run" \
  /usr/local/sbin/aardvark-ingest-run

getent group aardvark-ingest >/dev/null || groupadd --system aardvark-ingest

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
install -m 0440 "$REPO_DIR/deploy/sudoers.d/aardvark-ingest" "$tmp"
visudo -cf "$tmp"
install -o root -g root -m 0440 "$tmp" /etc/sudoers.d/aardvark-ingest

systemctl daemon-reload

for u in "$@"; do
  usermod -aG aardvark-ingest "$u"
  echo "added $u to aardvark-ingest"
done

echo "installed aardvark-ingest unit, launcher and sudoers"
