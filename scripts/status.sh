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

echo "LM Studio"
case "$(hearth_daemon_owner)" in
  app)     g "app owns the daemon" ;;
  llmster) y "llmster owns the daemon (D6 is the app)" ;;
  *)       r "not running — scripts/boot.sh" ;;
esac
code=$(hearth_http /models "${LMSTUDIO_HOST_TOKEN:-}")
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
  *)                           y "bound to: ${bound}(not loopback-only — run scripts/boot.sh)" ;;
esac

echo
echo "Roles"
if hearth_lms_ok; then
  "${ROOT}/scripts/lms-load.sh" --check 2>/dev/null | sed 's/^/  /'
  "$HEARTH_LMS" ps 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | awk 'NR>1 && NF' | sed 's/^/  /'
fi

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
"${ROOT}/scripts/install-autostart.sh" --check >/dev/null 2>&1 && g "$(ai_boot_label) loaded" || y "$(ai_boot_label) not installed (scripts/install-autostart.sh --apply)"
