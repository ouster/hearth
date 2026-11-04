#!/bin/bash
# One glance at whether local inference is up. Read-only, fast, no model calls.
# For a real verdict run scripts/healthcheck.sh.
#
#   scripts/status.sh

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"
ai_load_env

g() { printf '  \033[32m●\033[0m %s\n' "$1"; }
r() { printf '  \033[31m●\033[0m %s\n' "$1"; }
y() { printf '  \033[33m●\033[0m %s\n' "$1"; }

echo "oMLX"
who=$(lsof -nP -iTCP:"$HEARTH_PORT" -sTCP:LISTEN 2>/dev/null | awk 'NR==2 {print $1}')
case "$who" in
  Python|python*|omlx) g "listening on ${HEARTH_URL} (${who})" ;;
  "")                   r "not listening — scripts/omlx.sh up" ;;
  *)                    r "port ${HEARTH_PORT} is held by ${who}" ;;
esac
code=$(hearth_http /models "${OMLX_HOST_TOKEN:-}")
case "$code" in
  200) g "server answering on ${HEARTH_URL}" ;;
  401) r "server refuses the host token" ;;
  000) r "server not answering on ${HEARTH_URL}" ;;
  *)   y "server answered ${code}" ;;
esac
bound=$(lsof -nP -iTCP:"$HEARTH_PORT" -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {print $9}' | sort -u | tr '\n' ' ')
case "$bound" in
  "127.0.0.1:${HEARTH_PORT} ") g "bound to 127.0.0.1 only" ;;
  "")                          : ;;
  *)                           y "bound to: ${bound}(not loopback-only — run scripts/omlx.sh up)" ;;
esac

echo
echo "Roles"
"${ROOT}/scripts/omlx.sh" status 2>/dev/null | sed 's/^/  /' || y "omlx status failed"

echo
echo "Containers"
if command -v podman >/dev/null 2>&1 && podman info >/dev/null 2>&1; then
  for kind in webui searxng; do
    c="$(ai_container "$kind")"
    s=$(podman inspect -f '{{.State.Status}}' "$c" 2>/dev/null || echo "not created")
    [ "$s" = "running" ] && g "${c}: running" || y "${c}: ${s}"
  done
else
  y "podman VM not running"
fi

echo
echo "Autostart"
"${ROOT}/scripts/install-autostart.sh" --check >/dev/null 2>&1 && g "login agents loaded" || y "autostart incomplete — scripts/install-autostart.sh --check"
last_trim="$HOME/Library/Logs/hearth-context-watch.log"
if [ -f "$last_trim" ] && [ -s "$last_trim" ]; then
  y "last context trim: $(tail -1 "$last_trim")"
fi
