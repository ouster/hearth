#!/bin/bash
# One glance at whether the stack is up.
#
#   scripts/status.sh
#
# Read-only. Answers "is everything running" without the depth of
# preflight.sh (safe to deploy?) or healthcheck.sh (do the roles answer?).

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"
ai_load_env "$ROOT" 2>/dev/null

up()   { printf '  \033[32m●\033[0m %-22s %s\n' "$1" "$2"; }
down() { printf '  \033[31m○\033[0m %-22s %s\n' "$1" "$2"; }
warn() { printf '  \033[33m◐\033[0m %-22s %s\n' "$1" "$2"; }

echo "hearth"
echo

# ---------------------------------------------------------------- core
if curl -s -m 3 -o /dev/null http://127.0.0.1:11434/api/tags 2>/dev/null; then
  if [ -f "$HOME/Library/LaunchAgents/$(ai_ollama_label).plist" ]; then
    up "ollama" "127.0.0.1:11434 (service)"
  else
    up "ollama" "127.0.0.1:11434 (app — will not survive reboot)"
  fi
else
  down "ollama" "not responding — scripts/install-ollama-service.sh --apply"
fi

if curl -s -m 3 -o /dev/null http://127.0.0.1:4000/health/readiness 2>/dev/null; then
  up "gateway" ":4000"
else
  down "gateway" "not responding — scripts/boot.sh"
fi

if command -v podman >/dev/null 2>&1; then
  if podman info >/dev/null 2>&1; then
    up "podman machine" "running"
    for spec in postgres:5433 searxng:8888 webui:3000; do
      kind="${spec%%:*}"; port="${spec##*:}"
      name="$(ai_container "$kind")"
      if podman container exists "$name" 2>/dev/null; then
        st=$(podman inspect -f '{{.State.Status}}' "$name" 2>/dev/null)
        [ "$st" = "running" ] && up "$kind" ":${port}" || down "$kind" "$st — podman start ${name}"
      else
        warn "$kind" "not created"
      fi
    done
  else
    down "podman machine" "stopped — everything containerised is down"
  fi
fi

# ---------------------------------------------------------------- resident
echo
if command -v ollama >/dev/null 2>&1; then
  # grep -c returns "0" AND exits 1 on no match, so `|| echo 0` yields "0\n0"
  # and every numeric test after it fails. wc -l has no such opinion.
  n=$(ollama ps 2>/dev/null | awk 'NR>1' | wc -l | tr -d ' ')
  if [ "$n" -gt 0 ]; then
    echo "  models resident:"
    ollama ps 2>/dev/null | awk 'NR>1 {printf "    %-24s %s\n", $1, $3}'
  else
    echo "  models resident: none — first request will cold-load"
  fi
fi

# ---------------------------------------------------------------- exposure
echo
LANIP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "")
if [ -n "$LANIP" ]; then
  curl -s -m 2 -o /dev/null "http://${LANIP}:11434/api/tags" 2>/dev/null \
    && down "ollama on LAN" "EXPOSED — scripts/lock-ollama.sh --apply" \
    || up "ollama on LAN" "closed"
  curl -s -m 2 -o /dev/null "http://${LANIP}:4000/health/readiness" 2>/dev/null \
    && up "gateway on LAN" "${LANIP}:4000 — laptops can reach it" \
    || warn "gateway on LAN" "unreachable from ${LANIP}"
fi

# ---------------------------------------------------------------- sleep
echo
if command -v pmset >/dev/null 2>&1; then
  s=$(pmset -g custom 2>/dev/null | awk '/^AC Power/,0' | awk '/ sleep/ {print $2; exit}')
  [ "${s:-1}" = "0" ] && up "sleep" "disabled on AC" \
                      || warn "sleep" "after ${s:-?} min — laptops lose the gateway"
fi

echo
echo "  deeper: scripts/healthcheck.sh    safe to deploy: scripts/preflight.sh"
