#!/bin/bash
# Tell the operator when the server trims a prompt to fit the context window.
# The request still runs. This only notifies.
#
# Watches ~/Library/Logs/hearth-omlx.log. It notifies on a trim line of the
# form "pre-processing the 'N' token prompt by removing 'M' tokens". oMLX does
# not emit that line today, so the watcher stays quiet until the log does.
#
#   scripts/context-watch.sh
#
# Stays running under launchd (KeepAlive): scripts/install-autostart.sh --apply
# Log of notifications: ~/Library/Logs/hearth-context-watch.log
#
# Exit 0 on SIGTERM.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"

LOG_FILE="${HEARTH_SERVER_LOG:-$HOME/Library/Logs/hearth-omlx.log}"
POLL="${HEARTH_CONTEXT_WATCH_POLL:-1}"
SINK="${HEARTH_CONTEXT_WATCH_LOG:-$HOME/Library/Logs/hearth-context-watch.log}"
ROLE=""
MSGS=""

newest_log() {
  [ -f "$LOG_FILE" ] && printf '%s' "$LOG_FILE"
}

notify() {
  local msg="$1"
  mkdir -p "$(dirname "$SINK")"
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$msg" >> "$SINK"
  [ "${HEARTH_CONTEXT_WATCH_NO_NOTIFY:-}" = "1" ] && return 0
  /usr/bin/osascript - "$msg" >/dev/null 2>&1 <<'APPLESCRIPT' || true
on run argv
  display notification (item 1 of argv) with title "Hearth" subtitle "Context trimmed"
end run
APPLESCRIPT
}

handle_line() {
  local line="$1" prompt dropped who n
  if [[ $line =~ \]\[([^]]+)\]\ Running\ chat\ completion\ on\ conversation\ with\ ([0-9]+)\ messages ]]; then
    ROLE="${BASH_REMATCH[1]}"
    MSGS="${BASH_REMATCH[2]}"
    return 0
  fi
  if [[ $line =~ pre-processing\ the\ \'([0-9]+)\'\ token\ prompt\ by\ removing\ \'([0-9]+)\'\ tokens ]]; then
    prompt="${BASH_REMATCH[1]}"
    dropped="${BASH_REMATCH[2]}"
    who="${ROLE:-unknown}"
    n=""
    [ -n "$MSGS" ] && n=" (${MSGS} messages)"
    notify "${who}: ${prompt} token prompt, ${dropped} dropped${n}. The turn still runs."
  fi
}

scratch="$(mktemp)"
trap 'rm -f "$scratch"; exit 0' TERM INT
trap 'rm -f "$scratch"' EXIT

file=""
offset=0
while true; do
  cur="$(newest_log)"
  if [ -z "$cur" ]; then
    sleep "$POLL"
    continue
  fi
  if [ "$cur" != "$file" ]; then
    file=$cur
    offset=$(wc -c < "$file" | tr -d ' ')
  fi
  size=$(wc -c < "$file" | tr -d ' ')
  if [ "$size" -lt "$offset" ]; then
    offset=0
  fi
  if [ "$size" -gt "$offset" ]; then
    tail -c +$((offset + 1)) "$file" > "$scratch" || true
    bytes=$(wc -c < "$scratch" | tr -d ' ')
    # A command substitution would strip the trailing newline and the line
    # would never look finished. Wait until the write has one.
    [ "$bytes" -gt 0 ] || { sleep "$POLL"; continue; }
    last=$(od -An -tu1 -j $((bytes - 1)) -N 1 "$scratch" 2>/dev/null | tr -d ' ')
    if [ "$last" = "10" ]; then
      while IFS= read -r line; do
        handle_line "$line"
      done < "$scratch"
      offset=$((offset + bytes))
    fi
  fi
  sleep "$POLL"
done
