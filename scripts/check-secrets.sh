#!/usr/bin/env bash
# Scans all of git history for secrets before publishing. Exits 1 if anything is found.
cd "$(git rev-parse --show-toplevel)" || exit 1
history=$(mktemp)
trap 'rm -f "$history"' EXIT
git log --all -p > "$history"
status=0
if grep -E 'AIza[0-9A-Za-z_-]{20,}|AQ\.[0-9A-Za-z_-]{20,}' "$history" >/dev/null; then
    echo "Something that looks like a Gemini key is in the history." >&2
    status=1
fi
if git log --all --name-only --format= | grep -E '(^|/)\.env$' >/dev/null; then
    echo "A .env file was committed at some point." >&2
    status=1
fi
if [ -f .env ]; then
    while IFS= read -r line; do
        key=${line%%=*}
        value=${line#*=}
        case "$key" in
            GEMINI_API_KEY|ANKICONNECT_API_KEY|ANKICONNECT_URLS)
                if [ -n "$value" ] && grep -F -- "$value" "$history" >/dev/null; then
                    echo "The value of $key from .env appears in the history." >&2
                    status=1
                fi
                ;;
        esac
    done < .env
fi
[ "$status" -eq 0 ] && echo "No secrets found in git history."
exit "$status"
