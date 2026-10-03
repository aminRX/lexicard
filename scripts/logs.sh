#!/usr/bin/env bash
# Prints Lexicard-related lines from KOReader's log on a USB-mounted Kindle.
# Usage: scripts/logs.sh [lines]
KINDLE="${KINDLE:-/Volumes/Kindle}"
LOG="$KINDLE/koreader/crash.log"
[ -f "$LOG" ] || { echo "No log at $LOG (is the Kindle mounted?)" >&2; exit 1; }
grep -n -i -E "lexicard|traceback|attempt to" "$LOG" | tail -n "${1:-60}"
