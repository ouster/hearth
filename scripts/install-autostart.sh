#!/bin/bash
# Make local inference come back after login, and print (never run) the sleep
# settings a server-like Mac wants.
#
#   scripts/install-autostart.sh --check    # default: report, change nothing
#   scripts/install-autostart.sh --apply    # write + load launchd agents
#   scripts/install-autostart.sh --watch    # load only the context-trim watcher
#   scripts/install-autostart.sh --remove
#
# The boot agent runs scripts/boot.sh once at login (RunAtLoad, no KeepAlive):
# start oMLX, Podman + SearXNG. Log: ~/Library/Logs/hearth-boot.log
# com.hearth.swap and com.hearth.model-proxy are retired (ADR 0052): --apply
# and --remove unload and delete them, --check fails while either remains.
#
# Exit 0 ok, 1 not installed / broken (--check), 2 could not run.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"

LABEL="$(ai_boot_label)"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
LOG="$HOME/Library/Logs/hearth-boot.log"
WATCH_LABEL="com.hearth.context-watch"
WATCH_PLIST="$HOME/Library/LaunchAgents/${WATCH_LABEL}.plist"
WATCH_LOG="$HOME/Library/Logs/hearth-context-watch.log"
RETIRED_LABELS="com.hearth.swap com.hearth.model-proxy"
RETIRED_PROCS="scripts/hearth-swapd.py scripts/model-proxy.py"
RETIRED_PORTS="1236 1238"
DOMAIN="gui/$(id -u)"
MODE="${1:---check}"

# These are user LaunchAgents. Under sudo the domain is gui/0, which does not
# exist ("125: Domain does not support specified action"), and the plists
# and logs written on the way end up owned by root.
if [ "$(id -u)" -eq 0 ]; then
  echo "could not run: do not use sudo — these agents load in your own login session"
  exit 2
fi

# Unload LABEL and wait until launchd has let go of it. bootout returns while
# a running job is still being torn down; a bootstrap in that window fails
# with "5: Input/output error".
bootout_wait() {
  local label="$1" i=0
  launchctl bootout "${DOMAIN}/${label}" >/dev/null 2>&1 || true
  while launchctl print "${DOMAIN}/${label}" >/dev/null 2>&1; do
    i=$((i + 1))
    [ "$i" -ge 50 ] && { echo "FAIL: ${label} still loaded 10 s after bootout"; return 1; }
    sleep 0.2
  done
  return 0
}

write_plist() {
  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${ROOT}/scripts/boot.sh</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <!-- boot.sh exits once things are up. Without this, launchd kills every
       process left in the job's process group at exit — which is the Podman
       VM (vfkit, gvproxy) that boot.sh started. Observed and reproduced
       2026-10-31. -->
  <key>AbandonProcessGroup</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${LOG}</string>
  <key>StandardErrorPath</key>
  <string>${LOG}</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
</dict>
</plist>
EOF
}

write_watch_plist() {
  cat > "$WATCH_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${WATCH_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${ROOT}/scripts/context-watch.sh</string>
  </array>
  <key>KeepAlive</key>
  <true/>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${WATCH_LOG}</string>
  <key>StandardErrorPath</key>
  <string>${WATCH_LOG}</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
</dict>
</plist>
EOF
}

# Unload and delete the agents ADR 0052 removed. Their scripts are gone, so a
# leftover KeepAlive job would only restart-loop. hearth-swapd.sh also started
# a nohup copy when no plist existed, which launchd never knew about: stop
# that by its command line. A running process keeps its script open after
# the file is deleted.
retire_stale() {
  local label proc
  for label in $RETIRED_LABELS; do
    bootout_wait "$label" || return 1
    if [ -f "$HOME/Library/LaunchAgents/${label}.plist" ]; then
      rm -f "$HOME/Library/LaunchAgents/${label}.plist"
      echo "removed retired ${label} (ADR 0052)"
    fi
  done
  for proc in $RETIRED_PROCS; do
    if pgrep -f "$proc" >/dev/null 2>&1; then
      pkill -f "$proc" >/dev/null 2>&1 || true
      echo "stopped a stray ${proc} process (ADR 0052)"
    fi
  done
  rm -f "$HOME/Library/Logs/hearth-swapd.log" "$HOME/Library/Logs/hearth-model-proxy.log"
  return 0
}

load_watch() {
  mkdir -p "$(dirname "$WATCH_PLIST")" "$(dirname "$WATCH_LOG")"
  write_watch_plist
  plutil -lint "$WATCH_PLIST" >/dev/null || { echo "FAIL: context-watch plist does not lint"; return 1; }
  bootout_wait "$WATCH_LABEL" || return 1
  launchctl bootstrap "$DOMAIN" "$WATCH_PLIST" || { echo "FAIL: launchctl bootstrap ${WATCH_LABEL}"; return 1; }
  echo "installed ${WATCH_LABEL} — notifies when a prompt is trimmed (the turn still runs)"
}

print_sleep_advice() {
  cat <<'EOF'

Sleep — a sleeping host means no inference for any client. Not run for you:
  sudo pmset -c sleep 0           # never sleep on AC
  sudo pmset -c disksleep 0
  sudo pmset -a womp 1            # wake on network access
  sudo pmset -c displaysleep 10   # displays can still sleep
Current:
EOF
  pmset -g 2>/dev/null | grep -E '^ *(sleep|disksleep|womp|displaysleep) ' || echo "  (pmset unavailable)"
}

case "$MODE" in
  --apply)
    mkdir -p "$(dirname "$PLIST")" "$(dirname "$LOG")"
    write_plist
    plutil -lint "$PLIST" >/dev/null || { echo "FAIL: plist does not lint"; exit 1; }
    bootout_wait "$LABEL" || exit 1
    if launchctl bootstrap "$DOMAIN" "$PLIST"; then
      echo "installed ${LABEL} — runs scripts/boot.sh at login (and just now)"
    else
      echo "FAIL: launchctl bootstrap"; exit 1
    fi
    load_watch || exit 1
    retire_stale || exit 1
    print_sleep_advice
    exec "$0" --check
    ;;
  --watch)
    load_watch || exit 1
    exec "$0" --check
    ;;
  --remove)
    launchctl bootout "${DOMAIN}/${LABEL}" >/dev/null 2>&1 || true
    launchctl bootout "${DOMAIN}/${WATCH_LABEL}" >/dev/null 2>&1 || true
    retire_stale || exit 1
    rm -f "$PLIST" "$WATCH_PLIST"
    echo "removed ${LABEL} and ${WATCH_LABEL}"
    ;;
  --check)
    rc=0
    if [ -f "$PLIST" ] && plutil -lint "$PLIST" >/dev/null 2>&1; then
      echo "OK    plist ${PLIST}"
      grep -q '<key>AbandonProcessGroup</key>' "$PLIST" \
        && echo "OK    AbandonProcessGroup set (the Podman VM survives boot.sh exiting)" \
        || { echo "FAIL  AbandonProcessGroup missing — launchd will kill the Podman VM when boot.sh exits (--apply)"; rc=1; }
      grep -q "${ROOT}/scripts/boot.sh" "$PLIST" \
        && echo "OK    points at ${ROOT}/scripts/boot.sh" \
        || { echo "FAIL  plist points somewhere else"; rc=1; }
    else
      echo "FAIL  no valid plist at ${PLIST} (--apply)"; rc=1
    fi
    if launchctl print "${DOMAIN}/${LABEL}" >/dev/null 2>&1; then
      last=$(launchctl print "${DOMAIN}/${LABEL}" | awk -F'= ' '/last exit code/ {print $2; exit}')
      echo "OK    loaded in ${DOMAIN} (last exit: ${last:-not run yet})"
      case "${last:-}" in ''|0|"(never exited)") ;; *) echo "WARN  last boot.sh run failed — see ${LOG}" ;; esac
    else
      echo "FAIL  not loaded"; rc=1
    fi
    if [ -f "$WATCH_PLIST" ] && plutil -lint "$WATCH_PLIST" >/dev/null 2>&1 \
       && grep -q "${ROOT}/scripts/context-watch.sh" "$WATCH_PLIST"; then
      echo "OK    plist ${WATCH_PLIST}"
    else
      echo "FAIL  no valid context-watch plist (--apply)"; rc=1
    fi
    if launchctl print "${DOMAIN}/${WATCH_LABEL}" >/dev/null 2>&1; then
      echo "OK    ${WATCH_LABEL} loaded"
    else
      echo "FAIL  ${WATCH_LABEL} not loaded"; rc=1
    fi
    for retired in $RETIRED_LABELS; do
      if [ -f "$HOME/Library/LaunchAgents/${retired}.plist" ] \
         || launchctl print "${DOMAIN}/${retired}" >/dev/null 2>&1; then
        echo "FAIL  ${retired} is retired (ADR 0052) but still installed or loaded (--apply)"; rc=1
      else
        echo "OK    ${retired} not installed (retired, ADR 0052)"
      fi
    done
    for port in $RETIRED_PORTS; do
      if nc -z 127.0.0.1 "$port" >/dev/null 2>&1; then
        echo "FAIL  something still listens on retired :${port} (ADR 0052) — lsof -nP -iTCP:${port} -sTCP:LISTEN; --apply stops a stray swapd or proxy"; rc=1
      fi
    done
    [ -f "$LOG" ] && { echo "--- last lines of ${LOG}"; tail -5 "$LOG"; }
    exit "$rc"
    ;;
  *) echo "usage: $0 [--check|--apply|--watch|--remove]"; exit 2 ;;
esac
