#!/bin/bash
# SearXNG — self-hosted metasearch, so local models can do web RAG.
#
#   scripts/searxng.sh up | down | status | logs | test | destroy
#
# PRIVACY, read this before enabling.
#
# SearXNG keeps Google/Bing/DuckDuckGo from seeing your IP or building a
# profile — it queries them on your behalf and aggregates. That is a real
# improvement over searching directly.
#
# It does NOT make search private. Your QUERY still leaves this machine and
# reaches upstream engines. The conversation, your documents and the model stay
# local; the search terms do not.
#
# So: never enable web search on a conversation involving sensitive data, PII,
# or any flagged-sensitive repo. "Summarise this document" is safe; "search for
# <client name> <address>" is a disclosure. See docs/ROUTING.md.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"
NAME="$(ai_container searxng)"
VOLUME="$(ai_volume searxng-config)"
IMAGE=docker.io/searxng/searxng:latest
PORT=8888

case "${1:-status}" in
  up)
    podman info >/dev/null 2>&1 || { echo "podman VM not running: podman machine start"; exit 1; }
    podman volume exists "$VOLUME" 2>/dev/null || podman volume create "$VOLUME" >/dev/null

    if podman container exists "$NAME" 2>/dev/null; then
      podman start "$NAME" >/dev/null && echo "started existing ${NAME}"
    else
      # 127.0.0.1 only — this is for Open WebUI on this machine, not the LAN.
      podman run -d \
        --name "$NAME" \
        --restart unless-stopped \
        -p "127.0.0.1:${PORT}:8080" \
        -e "BASE_URL=http://127.0.0.1:${PORT}/" \
        -e "INSTANCE_NAME=hearth" \
        -v "${VOLUME}:/etc/searxng" \
        "$IMAGE" >/dev/null
      echo "created ${NAME}"
      sleep 6
    fi

    # Open WebUI needs the json format. SearXNG ships json DISABLED and returns
    # 403 Forbidden for it — which reads like an auth problem and is not.
    #
    # The generated settings.yml is minimal (use_default_settings + a secret),
    # with no `formats:` key to patch and an existing `server:` block that a
    # naive append would duplicate, breaking the YAML. So rewrite the file
    # wholesale, carrying the generated secret_key across.
    if podman exec "$NAME" grep -qE '^\s+- json\s*$' /etc/searxng/settings.yml 2>/dev/null; then
      echo "  json format already enabled"
    else
      echo "  enabling json output (SearXNG defaults to html only -> 403)"

      SECRET=$(podman exec "$NAME" sh -c \
        "grep -oE 'secret_key: *\"?[^\"]+\"?' /etc/searxng/settings.yml | head -1 | sed -E 's/secret_key: *\"?([^\"]+)\"?/\1/'" 2>/dev/null)
      if [ -z "${SECRET:-}" ]; then
        SECRET=$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')
        echo "  no existing secret found — generated a new one"
      fi

      podman exec -i "$NAME" sh -c 'cat > /etc/searxng/settings.yml' <<EOF
# Managed by ~/dev/hearth/scripts/searxng.sh — regenerated on 'up'.
use_default_settings: true

server:
  secret_key: "${SECRET}"
  # Bound to 127.0.0.1 only, single user, so the bot limiter has nothing to
  # protect against and would otherwise reject Open WebUI's API calls.
  limiter: false
  image_proxy: true

search:
  # json is what Open WebUI requires. Without it SearXNG answers 403.
  formats:
    - html
    - json
EOF
      podman restart "$NAME" >/dev/null
      printf '  restarting'
      for _ in $(seq 1 20); do
        curl -s -m 2 -o /dev/null "http://127.0.0.1:${PORT}/" && break
        printf '.'; sleep 1
      done
      echo
    fi

    printf 'waiting'
    for _ in $(seq 1 20); do
      curl -s -m 2 -o /dev/null "http://127.0.0.1:${PORT}/" && break
      printf '.'; sleep 1
    done
    echo " — up on 127.0.0.1:${PORT}"
    echo
    echo "Now: scripts/searxng.sh test"
    ;;

  test)
    echo "Querying SearXNG for a json response..."
    out=$(curl -s -m 20 "http://127.0.0.1:${PORT}/search?q=test&format=json" 2>/dev/null)
    if printf '%s' "$out" | head -c 1 | grep -q '{'; then
      n=$(printf '%s' "$out" | python3 -c 'import sys,json; print(len(json.load(sys.stdin).get("results",[])))' 2>/dev/null || echo "?")
      echo "  OK — json works, ${n} results"
      echo "  Open WebUI can use this."
    elif printf '%s' "$out" | grep -qi '403\|forbidden'; then
      echo "  FAILED — 403 Forbidden."
      echo
      echo "  This is SearXNG refusing the json FORMAT, not an auth problem."
      echo "  Either json is still missing from settings.yml, or the bot limiter"
      echo "  is rejecting a non-browser request."
      echo
      echo "  Current settings.yml:"
      podman exec "$NAME" cat /etc/searxng/settings.yml 2>/dev/null | sed 's/^/    /'
      echo
      echo "  Re-run 'scripts/searxng.sh up' to rewrite it, or edit by hand and"
      echo "  ensure BOTH of these are present:"
      echo "    server:  { limiter: false }"
      echo "    search:  { formats: [html, json] }"
      exit 1
    else
      echo "  FAILED — unexpected response:"
      printf '%s' "$out" | head -c 300 | sed 's/^/    /'
      exit 1
    fi
    ;;

  down)   podman stop "$NAME" >/dev/null && echo "stopped" ;;
  status) podman ps -a --filter "name=${NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" ;;
  logs)   podman logs -f "$NAME" ;;
  destroy)
    podman rm -f "$NAME" >/dev/null 2>&1 || true
    podman volume rm "$VOLUME" >/dev/null 2>&1 || true
    echo "gone"
    ;;
  *) echo "usage: $0 {up|test|down|status|logs|destroy}"; exit 1 ;;
esac
