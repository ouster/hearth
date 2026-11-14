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
# start oMLX, hearth-swapd, Podman + SearXNG. Log: ~/Library/Logs/hearth-boot.log
# com.hearth.swap (KeepAlive) serves sub-key load/unload on :1236 (ADR 0049).
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
SWAP_LABEL="com.hearth.swap"
SWAP_PLIST="$HOME/Library/LaunchAgents/${SWAP_LABEL}.plist"
SWAP_LOG="$HOME/Library/Logs/hearth-swapd.log"
DOMAIN="gui/$(id -u)"
MODE="${1:---check}"

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

write_swap_plist() {
  cat > "$SWAP_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${SWAP_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${ROOT}/scripts/hearth-swapd.sh</string>
    <string>run</string>
  </array>
  <key>KeepAlive</key>
  <true/>
  <key>RunAtLoad</key>
  <true/>
  <key>ThrottleInterval</key>
  <integer>10</integer>
  <key>StandardOutPath</key>
  <string>${SWAP_LOG}</string>
  <key>StandardErrorPath</key>
  <string>${SWAP_LOG}</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
</dict>
</plist>
EOF
}

load_swap() {
  mkdir -p "$(dirname "$SWAP_PLIST")" "$(dirname "$SWAP_LOG")"
  write_swap_plist
  plutil -lint "$SWAP_PLIST" >/dev/null || { echo "FAIL: swap plist does not lint"; return 1; }
  launchctl bootout "${DOMAIN}/${SWAP_LABEL}" >/dev/null 2>&1 || true
  launchctl bootstrap "$DOMAIN" "$SWAP_PLIST" || { echo "FAIL: launchctl bootstrap ${SWAP_LABEL}"; return 1; }
  echo "installed ${SWAP_LABEL} — sub-key swap on 127.0.0.1:1236 (ADR 0049)"
}

load_watch() {
  mkdir -p "$(dirname "$WATCH_PLIST")" "$(dirname "$WATCH_LOG")"
  write_watch_plist
  plutil -lint "$WATCH_PLIST" >/dev/null || { echo "FAIL: context-watch plist does not lint"; return 1; }
  launchctl bootout "${DOMAIN}/${WATCH_LABEL}" >/dev/null 2>&1 || true
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
    launchctl bootout "${DOMAIN}/${LABEL}" >/dev/null 2>&1 || true
    if launchctl bootstrap "$DOMAIN" "$PLIST"; then
      echo "installed ${LABEL} — runs scripts/boot.sh at login (and just now)"
    else
      echo "FAIL: launchctl bootstrap"; exit 1
    fi
    load_watch || exit 1
    load_swap || exit 1
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
    launchctl bootout "${DOMAIN}/${SWAP_LABEL}" >/dev/null 2>&1 || true
    rm -f "$PLIST" "$WATCH_PLIST" "$SWAP_PLIST"
    echo "removed ${LABEL}, ${WATCH_LABEL}, and ${SWAP_LABEL}"
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
    if [ -f "$SWAP_PLIST" ] && plutil -lint "$SWAP_PLIST" >/dev/null 2>&1 \
       && grep -q "${ROOT}/scripts/hearth-swapd.sh" "$SWAP_PLIST"; then
      echo "OK    plist ${SWAP_PLIST}"
    else
      echo "FAIL  no valid swap plist (--apply)"; rc=1
    fi
    if launchctl print "${DOMAIN}/${SWAP_LABEL}" >/dev/null 2>&1; then
      echo "OK    ${SWAP_LABEL} loaded"
    else
      echo "FAIL  ${SWAP_LABEL} not loaded"; rc=1
    fi
    [ -f "$LOG" ] && { echo "--- last lines of ${LOG}"; tail -5 "$LOG"; }
    exit "$rc"
    ;;
  *) echo "usage: $0 [--check|--apply|--watch|--remove]"; exit 2 ;;
esac
