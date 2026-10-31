#!/bin/bash
# Make local inference come back after login, and print (never run) the sleep
# settings a server-like Mac wants.
#
#   scripts/install-autostart.sh --check    # default: report, change nothing
#   scripts/install-autostart.sh --apply    # write + load the launchd agent
#   scripts/install-autostart.sh --remove
#
# The agent runs scripts/boot.sh once at login (RunAtLoad, no KeepAlive):
# open LM Studio hidden, start the server with an explicit --bind, load
# config/roles.tsv, start Podman + SearXNG + Open WebUI. Log:
# ~/Library/Logs/hearth-boot.log
#
# Exit 0 ok, 1 not installed / broken (--check), 2 could not run.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"

LABEL="$(ai_boot_label)"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
LOG="$HOME/Library/Logs/hearth-boot.log"
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
    print_sleep_advice
    exec "$0" --check
    ;;
  --remove)
    launchctl bootout "${DOMAIN}/${LABEL}" >/dev/null 2>&1 || true
    rm -f "$PLIST"
    echo "removed ${LABEL}"
    ;;
  --check)
    rc=0
    if [ -f "$PLIST" ] && plutil -lint "$PLIST" >/dev/null 2>&1; then
      echo "OK    plist ${PLIST}"
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
    [ -f "$LOG" ] && { echo "--- last lines of ${LOG}"; tail -5 "$LOG"; }
    exit "$rc"
    ;;
  *) echo "usage: $0 [--check|--apply|--remove]"; exit 2 ;;
esac
