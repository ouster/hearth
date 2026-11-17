#!/bin/bash
# Bring local inference up after login. Called by the launchd agent that
# scripts/install-autostart.sh installs, and safe to run by hand.
#
#   scripts/boot.sh
#
# What actually needs help (ADR 0026):
#
#   oMLX        serves main-brain on 127.0.0.1 from ~/.hearth/models.
#               scripts/omlx.sh up. scripts/omlx.sh down stops it
#               and leaves the port empty.
#   Podman      the VM does not start itself; container restart policies only
#               apply once it is up. SearXNG lives there. Open WebUI was
#               removed (ADR 0044); a leftover container is stopped.
#
# Always 127.0.0.1. D8 is an SSH tunnel; there is no LAN bind switch.
# launchd does not retry a failed boot: a Podman failure must not
# restart the server in a loop.
#
# Exit 0 serving with roles loaded, 1 something failed, 2 could not run.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"

log() { printf '%s [hearth boot] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$1"; }
rc=0

# ---------------------------------------------------------------- oMLX
log "starting oMLX"
if "${ROOT}/scripts/omlx.sh" up; then
  log "oMLX on 127.0.0.1:${HEARTH_PORT}"
else
  log "FAILED: scripts/omlx.sh up"
  exit 1
fi
wan=$(hearth_wan_binds "$HEARTH_PORT")
if [ -n "$wan" ]; then
  log "FAILED: :${HEARTH_PORT} is not loopback-only:${wan}"
  rc=1
fi

# ---------------------------------------------------------------- podman
PODMAN="$(command -v podman 2>/dev/null || true)"
if [ -z "$PODMAN" ]; then
  log "podman not installed — skipping SearXNG"
else
  if ! "$PODMAN" info >/dev/null 2>&1; then
    log "starting podman machine"
    "$PODMAN" machine start >/dev/null 2>&1 || true
  fi
  ready=0
  for _ in $(seq 1 60); do
    "$PODMAN" info >/dev/null 2>&1 && { ready=1; break; }
    sleep 1
  done
  if [ "$ready" -ne 1 ]; then
    log "podman API unreachable — skipping containers"
    rc=1
  else
    c="$(ai_container searxng)"
    if ! "$PODMAN" container exists "$c" 2>/dev/null; then
      log "${c}: not created (scripts/searxng.sh up)"
    elif [ "$("$PODMAN" inspect -f '{{.State.Running}}' "$c" 2>/dev/null)" = "true" ]; then
      log "${c}: running"
    elif "$PODMAN" start "$c" >/dev/null 2>&1; then
      log "${c}: started"
    else
      log "${c}: FAILED to start"
      rc=1
    fi
    c="$(ai_container webui)"
    if "$PODMAN" container exists "$c" 2>/dev/null \
      && [ "$("$PODMAN" inspect -f '{{.State.Running}}' "$c" 2>/dev/null)" = "true" ]; then
      if "$PODMAN" stop "$c" >/dev/null 2>&1; then
        log "${c}: stopped (Open WebUI removed, ADR 0044)"
      else
        log "${c}: FAILED to stop"
        rc=1
      fi
    fi
  fi
fi

[ "$rc" -eq 0 ] && log "up" || log "finished with failures"
exit "$rc"
