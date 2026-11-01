#!/bin/bash
# Bring local inference up after login. Called by the launchd agent that
# scripts/install-autostart.sh installs, and safe to run by hand.
#
#   scripts/boot.sh
#
# What actually needs help (ADR 0016, D6 = the LM Studio app):
#
#   LM Studio   the app owns the daemon. It is opened hidden; nothing serves
#               until it is running.
#   server      autoStartOnLaunch is off, and the app's saved settings can
#               differ from what we want (bind 0.0.0.0 + CORS on was observed
#               2026-10-31). hearth_server_start writes loopback and CORS off,
#               then starts with --bind. --cors only turns CORS on.
#   models      not loaded at launch. scripts/lms-load.sh loads roles.tsv.
#   Podman      the VM does not start itself; container restart policies only
#               apply once it is up. SearXNG and Open WebUI live there.
#
# Always 127.0.0.1. D8 is an SSH tunnel; there is no LAN bind switch.
# CORS is forced off in the saved settings before start (`--cors` can only
# turn it on). If the app is slow, boot opens it a second time and waits
# again. launchd does not retry a failed boot: a Podman failure must not
# restart the server in a loop.
#
# Exit 0 serving with roles loaded, 1 something failed, 2 could not run.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"

log() { printf '%s [hearth boot] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$1"; }
wait_for_app() {
  local _
  for _ in $(seq 1 90); do
    [ "$(hearth_daemon_owner)" = "app" ] && return 0
    sleep 2
  done
  return 1
}
rc=0

[ -x "$HEARTH_LMS" ] || { log "could not run: lms not found at $HEARTH_LMS"; exit 2; }
[ -d "$HEARTH_APP" ] || { log "could not run: $HEARTH_APP not installed"; exit 2; }

# ---------------------------------------------------------------- LM Studio
case "$(hearth_daemon_owner)" in
  app)     log "LM Studio running" ;;
  llmster) log "llmster owns ~/.lmstudio — stopping it so the app can (D6)"
           "$HEARTH_LMS" daemon down >/dev/null 2>&1
           open -g -j -a "$HEARTH_APP" ;;
  *)       log "opening LM Studio (hidden)"
           open -g -j -a "$HEARTH_APP" ;;
esac
if ! wait_for_app; then
  log "still down after 180 s — opening LM Studio again"
  open -g -j -a "$HEARTH_APP" || true
  if ! wait_for_app; then
    log "FAILED: LM Studio daemon not up after a second 180 s wait"
    exit 1
  fi
fi

# ---------------------------------------------------------------- server
"$HEARTH_LMS" server stop >/dev/null 2>&1 || true
start_log=$(mktemp)
if hearth_server_start >"$start_log" 2>&1; then
  log "server on 127.0.0.1:${HEARTH_PORT}; saved settings confirmed loopback and CORS off"
  rm -f "$start_log"
else
  log "FAILED: server start — loopback and CORS were not confirmed"
  while IFS= read -r line; do log "$line"; done < "$start_log"
  rm -f "$start_log"
  exit 1
fi
code=000
for _ in $(seq 1 30); do
  code=$(hearth_http /models)
  [ "$code" != "000" ] && break
  sleep 1
done
case "$code" in
  401) log "auth on (no token → 401)" ;;
  200) log "WARNING: no token → 200. Require Authentication is OFF — turn it on in the app"; rc=1 ;;
  *)   log "FAILED: server answered ${code} on /v1/models"; rc=1 ;;
esac
wan=$(hearth_wan_binds "$HEARTH_PORT")
if [ -n "$wan" ]; then
  log "FAILED: :${HEARTH_PORT} is not loopback-only:${wan}"
  rc=1
fi

# ---------------------------------------------------------------- models
if "${ROOT}/scripts/lms-load.sh" >/dev/null 2>&1; then
  log "roles loaded per config/roles.tsv"
else
  log "FAILED: scripts/lms-load.sh (run it by hand to see why)"
  rc=1
fi

# ---------------------------------------------------------------- podman
PODMAN="$(command -v podman 2>/dev/null || true)"
if [ -z "$PODMAN" ]; then
  log "podman not installed — skipping SearXNG / Open WebUI"
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
    for kind in searxng webui; do
      c="$(ai_container "$kind")"
      if ! "$PODMAN" container exists "$c" 2>/dev/null; then
        log "${c}: not created (scripts/${kind}.sh up)"
      elif [ "$("$PODMAN" inspect -f '{{.State.Running}}' "$c" 2>/dev/null)" = "true" ]; then
        log "${c}: running"
      elif "$PODMAN" start "$c" >/dev/null 2>&1; then
        log "${c}: started"
      else
        log "${c}: FAILED to start"
        rc=1
      fi
    done
  fi
fi

[ "$rc" -eq 0 ] && log "up" || log "finished with failures"
exit "$rc"
