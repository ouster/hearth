#!/bin/bash
# Sub-key swap sidecar on 127.0.0.1:1236 (ADR 0049).
#
#   scripts/hearth-swapd.sh run      # foreground (launchd)
#   scripts/hearth-swapd.sh up       # ensure listening (kickstart or nohup)
#   scripts/hearth-swapd.sh down
#   scripts/hearth-swapd.sh status
#
# Exit 0 ok, 1 failed, 2 could not run.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"

LABEL="com.hearth.swap"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
LOG="$HOME/Library/Logs/hearth-swapd.log"
DOMAIN="gui/$(id -u)"
MODE="${1:-status}"
PY="${ROOT}/scripts/hearth-swapd.py"

listening() {
  if command -v nc >/dev/null 2>&1; then
    nc -z 127.0.0.1 "$HEARTH_SWAP_PORT" >/dev/null 2>&1
  else
    curl -s -m 2 -o /dev/null "http://127.0.0.1:${HEARTH_SWAP_PORT}/" >/dev/null 2>&1
  fi
}

run_env() {
  ai_load_env
  [ -n "${OMLX_HOST_TOKEN:-}" ] || { echo "could not run: OMLX_HOST_TOKEN missing" >&2; return 2; }
  export OMLX_HOST_TOKEN
  export HEARTH_ROOT="$ROOT"
  export ROOT
  export HEARTH_PORT
  export HEARTH_SWAP_PORT
  # Optional: GET /v1/hearth/agent needs it. demand-load.sh resolves roles itself.
  HEARTH_ROLES_TSV="$(hearth_resolved_roles 2>/dev/null)" || HEARTH_ROLES_TSV=""
  export HEARTH_ROLES_TSV
}

cmd_run() {
  run_env || exit $?
  exec /usr/bin/python3 -I "$PY"
}

cmd_status() {
  if listening; then
    echo "up 127.0.0.1:${HEARTH_SWAP_PORT}"
    return 0
  fi
  echo "down"
  return 1
}

cmd_down() {
  if [ "$(uname -s)" = "Darwin" ]; then
    launchctl bootout "${DOMAIN}/${LABEL}" >/dev/null 2>&1 || true
  fi
  # Manual nohup copy if any.
  pkill -f "python3 -I ${PY}" >/dev/null 2>&1 || true
  if listening; then
    echo "hearth-swapd: still listening on :${HEARTH_SWAP_PORT}" >&2
    return 1
  fi
  echo "hearth-swapd: stopped"
}

cmd_up() {
  if listening; then
    echo "hearth-swapd: already on 127.0.0.1:${HEARTH_SWAP_PORT}"
    return 0
  fi
  run_env || return $?
  if [ "$(uname -s)" = "Darwin" ] && [ -f "$PLIST" ]; then
    if ! launchctl print "${DOMAIN}/${LABEL}" >/dev/null 2>&1; then
      launchctl bootstrap "$DOMAIN" "$PLIST" || return 1
    fi
    launchctl kickstart -k "${DOMAIN}/${LABEL}" || return 1
  else
    mkdir -p "$(dirname "$LOG")"
    nohup /usr/bin/python3 -I "$PY" >>"$LOG" 2>&1 &
  fi
  _n=0
  while [ "$_n" -lt 30 ]; do
    listening && { echo "hearth-swapd: up 127.0.0.1:${HEARTH_SWAP_PORT}"; return 0; }
    sleep 0.2
    _n=$((_n + 1))
  done
  echo "hearth-swapd: did not bind :${HEARTH_SWAP_PORT} — see ${LOG}" >&2
  return 1
}

case "$MODE" in
  run) cmd_run ;;
  up) cmd_up ;;
  down) cmd_down ;;
  status) cmd_status ;;
  *) echo "usage: $0 run|up|down|status" >&2; exit 2 ;;
esac
