#!/bin/bash
# Bring the stack up after a reboot. Called by the launchd agent that
# scripts/install-autostart.sh installs, and safe to run by hand.
#
#   scripts/boot.sh
#
# What actually needs help:
#
#   LiteLLM   launchd KeepAlive — comes back on its own, but crash-loops
#             with Prisma P1001 until Postgres is reachable on the host
#   Ollama    the app, if "Open at Login" is set
#   Podman    the VM does NOT start itself. This is the gap.
#   containers restart policies only apply once the VM is running
#
# launchd gives agents a stripped PATH (/usr/bin:/bin:/usr/sbin:/sbin).
# Homebrew podman lives at /opt/homebrew/bin — without that on PATH this
# script used to log "podman not installed" and skip containers, leaving
# LiteLLM crash-looping forever.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"

# launchd / non-interactive shells: ensure Homebrew tools are visible.
export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH:-/usr/bin:/bin:/usr/sbin:/sbin}"

log() { printf '[hearth boot] %s\n' "$1"; }

# Host TCP reachability — Podman port forwards can lag behind in-container
# pg_isready. LiteLLM connects via 127.0.0.1:5433, so that is the real gate.
host_tcp_open() {
  local host="$1" port="$2"
  if command -v nc >/dev/null 2>&1; then
    nc -z -w 1 "$host" "$port" >/dev/null 2>&1
    return $?
  fi
  # bash /dev/tcp fallback
  (echo >/dev/tcp/"$host"/"$port") >/dev/null 2>&1
}

# Readiness is db-aware and lives in lib.sh — see ai_gateway_state there.
gateway_db_connected() { ai_gateway_ready http://127.0.0.1:4000 3; }

wait_podman_info() {
  local i
  for i in $(seq 1 60); do
    podman info >/dev/null 2>&1 && return 0
    sleep 1
  done
  return 1
}

# ---------------------------------------------------------------- podman VM
PODMAN="$(command -v podman 2>/dev/null || true)"
if [ -z "$PODMAN" ]; then
  for cand in /opt/homebrew/bin/podman /usr/local/bin/podman; do
    [ -x "$cand" ] && PODMAN="$cand" && break
  done
fi

if [ -n "$PODMAN" ]; then
  if "$PODMAN" info >/dev/null 2>&1; then
    log "podman machine already running"
  else
    log "starting podman machine"
    if "$PODMAN" machine start >/dev/null 2>&1; then
      log "  ok"
    else
      # "already running" races show up as non-zero; re-check.
      "$PODMAN" info >/dev/null 2>&1 && log "  ok (already up)" || log "  FAILED"
    fi
  fi

  if ! wait_podman_info; then
    log "podman API still unreachable after start — skipping containers"
  else
    # Containers carry --restart unless-stopped, but that only takes effect once
    # the VM is up, and a container stopped before shutdown stays stopped.
    for kind in postgres searxng webui; do
      c="$(ai_container "$kind")"
      if "$PODMAN" container exists "$c" 2>/dev/null; then
        state=$("$PODMAN" inspect -f '{{.State.Status}}' "$c" 2>/dev/null)
        if [ "$state" = "running" ]; then
          log "${c}: running"
        else
          if "$PODMAN" start "$c" >/dev/null 2>&1; then
            log "${c}: started"
          else
            # Improper/stopped-odd state after reboot: stop then start.
            log "${c}: start failed — retrying after stop"
            "$PODMAN" stop "$c" >/dev/null 2>&1 || true
            sleep 1
            "$PODMAN" start "$c" >/dev/null 2>&1 \
              && log "${c}: started" \
              || log "${c}: FAILED to start"
          fi
        fi
      else
        log "${c}: not created"
      fi
    done
  fi
else
  log "podman not installed — skipping containers"
fi

# ---------------------------------------------------------------- ollama
if curl -s -m 5 -o /dev/null http://127.0.0.1:11434/api/tags 2>/dev/null; then
  log "ollama responding"
else
  OLLAMA_LABEL="$(ai_ollama_label)"
  if [ -f "$HOME/Library/LaunchAgents/${OLLAMA_LABEL}.plist" ]; then
    log "ollama not up — kicking the service (${OLLAMA_LABEL})"
    launchctl kickstart -k "gui/$(id -u)/${OLLAMA_LABEL}" 2>/dev/null
  else
    log "ollama NOT responding and no service installed"
    log "  fix properly: scripts/install-ollama-service.sh --apply"
    open -a Ollama 2>/dev/null && log "  opened the app as a stopgap"
  fi
fi

# ---------------------------------------------------------------- gateway
# Wait until the HOST can reach Postgres. In-container pg_isready alone is not
# enough — LiteLLM uses the published port on 127.0.0.1:5433.
log "waiting for postgres on 127.0.0.1:5433"
pg_ready=0
for _ in $(seq 1 90); do
  if host_tcp_open 127.0.0.1 5433; then
    pg_ready=1
    break
  fi
  sleep 1
done
if [ "$pg_ready" = 1 ]; then
  log "postgres reachable on host :5433"
else
  log "postgres NOT reachable on host :5433 — gateway will fail until it is"
fi

if gateway_db_connected; then
  log "gateway ready (db:connected)"
else
  if ai_gateway_answering http://127.0.0.1:4000 3; then
    log "gateway answering but db not connected — kicking launchd"
  else
    log "gateway not up yet — kicking launchd"
  fi
  launchctl kickstart -k "$(ai_litellm_agent)" 2>/dev/null
  for _ in $(seq 1 45); do
    gateway_db_connected && break
    sleep 2
  done
  if gateway_db_connected; then
    log "gateway ready (db:connected)"
  else
    body=$(curl -s -m 3 http://127.0.0.1:4000/health/readiness 2>/dev/null || true)
    if [ -n "$body" ]; then
      log "gateway STILL NOT READY — readiness: ${body}"
    else
      log "gateway STILL DOWN — see ~/Library/Logs/litellm.error.log"
    fi
  fi
fi

log "done"
