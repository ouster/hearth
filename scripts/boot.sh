#!/bin/bash
# Bring the stack up after a reboot. Called by the launchd agent that
# scripts/install-autostart.sh installs, and safe to run by hand.
#
#   scripts/boot.sh
#
# What actually needs help:
#
#   LiteLLM   launchd KeepAlive — comes back on its own
#   Ollama    the app, if "Open at Login" is set
#   Podman    the VM does NOT start itself. This is the gap.
#   containers restart policies only apply once the VM is running
#
# LiteLLM will crash-loop until Postgres answers, and launchd restarts it every
# 10s, so the order below is a nicety rather than a requirement — but a clean
# start beats a minute of restart noise in the log.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"

log() { printf '[hearth boot] %s\n' "$1"; }

# ---------------------------------------------------------------- podman VM
if command -v podman >/dev/null 2>&1; then
  if podman info >/dev/null 2>&1; then
    log "podman machine already running"
  else
    log "starting podman machine"
    podman machine start >/dev/null 2>&1 && log "  ok" || log "  FAILED"
  fi

  # Containers carry --restart unless-stopped, but that only takes effect once
  # the VM is up, and a container stopped before shutdown stays stopped.
  for kind in postgres searxng webui; do
    c="$(ai_container "$kind")"
    if podman container exists "$c" 2>/dev/null; then
      state=$(podman inspect -f '{{.State.Status}}' "$c" 2>/dev/null)
      if [ "$state" = "running" ]; then
        log "${c}: running"
      else
        podman start "$c" >/dev/null 2>&1 && log "${c}: started" || log "${c}: FAILED to start"
      fi
    fi
  done
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
# Postgres needs to be accepting connections before LiteLLM will hold a start.
for _ in $(seq 1 30); do
  podman exec "$(ai_container postgres)" pg_isready -U litellm -d litellm >/dev/null 2>&1 && break
  sleep 1
done

if curl -s -m 5 -o /dev/null http://127.0.0.1:4000/health/readiness 2>/dev/null; then
  log "gateway responding"
else
  log "gateway not up yet — kicking launchd"
  launchctl kickstart -k "$(ai_litellm_agent)" 2>/dev/null
  for _ in $(seq 1 30); do
    curl -s -m 2 -o /dev/null http://127.0.0.1:4000/health/readiness && break
    sleep 2
  done
  curl -s -m 2 -o /dev/null http://127.0.0.1:4000/health/readiness \
    && log "gateway responding" || log "gateway STILL DOWN — see ~/Library/Logs/litellm.error.log"
fi

log "done"
