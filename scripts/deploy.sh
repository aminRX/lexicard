#!/usr/bin/env bash
# Copies Lexicard and its .env to a USB-mounted Kindle.
# Usage: scripts/deploy.sh [--eject]
set -euo pipefail
export COPYFILE_DISABLE=1
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KINDLE="${KINDLE:-/Volumes/Kindle}"
PLUGINS="$KINDLE/koreader/plugins"
DEST="$PLUGINS/lexicard.koplugin"

[ -d "$PLUGINS" ] || { echo "Kindle not mounted at $KINDLE" >&2; exit 1; }
[ -f "$ROOT/.env" ] || { echo "Missing $ROOT/.env (copy .env.example and fill it in)" >&2; exit 1; }
for f in "$ROOT"/lexicard.koplugin/*.lua; do
    luajit -e "assert(loadfile('$f'))" || { echo "Syntax error in $f" >&2; exit 1; }
done

mkdir -p "$DEST"
rsync -rt --delete --exclude '._*' --exclude '.DS_Store' "$ROOT/lexicard.koplugin/" "$DEST/"
cp "$ROOT/.env" "$DEST/.env"
find "$DEST" -name '._*' -delete
sync
echo "Deployed to $DEST"
if [ "${1:-}" = "--eject" ]; then diskutil eject "$KINDLE"; fi
