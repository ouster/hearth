#!/bin/bash
# Open WebUI was removed (ADR 0044). Editors talk to main-brain.
# SearXNG stays for Zed. This script only retires a leftover container.
#
#   scripts/webui.sh status
#   scripts/webui.sh down       # stop it
#   scripts/webui.sh destroy    # delete the container and its volume
#
# up is refused.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"
NAME="$(ai_container webui)"
VOLUME="$(ai_volume webui-data)"

_gone() {
  echo "Open WebUI was removed (ADR 0044)."
  echo "Chat is the editors on main-brain. SearXNG stays for Zed search."
}

_podman_up() {
  command -v podman >/dev/null 2>&1 || { echo "podman not installed"; return 1; }
  podman info >/dev/null 2>&1 || { echo "podman VM not running"; return 1; }
  return 0
}

case "${1:-status}" in
  up|logs)
    _gone
    exit 1
    ;;
  down)
    _podman_up || exit 0
    if podman container exists "$NAME" 2>/dev/null; then
      podman stop "$NAME" >/dev/null
      echo "stopped ${NAME}"
    else
      echo "no ${NAME} container"
    fi
    ;;
  destroy)
    _podman_up || exit 1
    podman rm -f "$NAME" >/dev/null 2>&1 || true
    podman volume rm "$VOLUME" >/dev/null 2>&1 || true
    echo "removed ${NAME} and ${VOLUME} if they existed"
    ;;
  status)
    _gone
    if ! _podman_up; then
      exit 0
    fi
    if podman container exists "$NAME" 2>/dev/null; then
      podman ps -a --filter "name=${NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
      echo "Retire it: scripts/webui.sh down"
    else
      echo "no leftover container"
    fi
    ;;
  *)
    echo "usage: scripts/webui.sh {status|down|destroy}" >&2
    exit 2
    ;;
esac
