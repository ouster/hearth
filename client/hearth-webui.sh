#!/bin/bash
# Run Open WebUI ON THIS MACHINE, pointed at the hearth gateway.
#
#   ./hearth-webui.sh up | tunnel | down | status | logs | destroy
#
# Each machine gets its OWN chat history — the database lives in a local
# volume and nothing is shared with the Studio. Inference still happens on the
# Studio; only the UI and its history are local.
#
# Needs podman or docker. That is the cost of separate history: the alternative
# is browsing the Studio's instance, which shares everything.
#
# Config comes from the same two places as the shell client:
#   $HEARTH_GATEWAY   e.g. http://192.168.1.10:4000  (required)
#   $HOME/.hearth-key
#   $HEARTH_SSH       optional user@host for the SearXNG tunnel
#
# Portable: bash 3.2 compatible, macOS and Linux. On Windows use Docker Desktop
# and run the equivalent `docker run` — see the README.

set -uo pipefail

NAME=hearth-webui-client
VOLUME=hearth-webui-client-data
IMAGE=ghcr.io/open-webui/open-webui:main
PORT="${WEBUI_PORT:-3000}"

GATEWAY="${HEARTH_GATEWAY:-}"
if [ -z "$GATEWAY" ]; then
  echo "hearth: set HEARTH_GATEWAY first (e.g. export HEARTH_GATEWAY=http://HOST:4000)" >&2
  exit 1
fi
KEY="${HEARTH_KEY:-}"
[ -z "$KEY" ] && [ -f "$HOME/.hearth-key" ] && KEY="$(cat "$HOME/.hearth-key")"

GATEWAY_HOST="$(printf '%s' "$GATEWAY" | sed -E 's#https?://##; s#:.*##')"
STUDIO_HOST="${HEARTH_SSH:-$GATEWAY_HOST}"

# podman preferred, docker accepted. They use different names for "the host",
# and getting it wrong means search silently fails on every query.
RT=""; HOSTALIAS=""
if command -v podman >/dev/null 2>&1; then RT=podman; HOSTALIAS=host.containers.internal
elif command -v docker >/dev/null 2>&1; then RT=docker; HOSTALIAS=host.docker.internal
fi

# Only the commands that actually drive a container need a runtime. `tunnel`
# just prints an ssh line and must work before anything is installed.
need_runtime() {
  [ -n "$RT" ] && return 0
  echo "Neither podman nor docker found."
  echo "  macOS:  brew install podman && podman machine init && podman machine start"
  echo "  Linux:  your package manager, e.g. apt install podman"
  echo
  echo "Not needed for: $0 tunnel"
  exit 1
}

case "${1:-status}" in
  up)
    need_runtime
    [ -n "$KEY" ] || { echo "No key. Put the lan key in ~/.hearth-key"; exit 1; }

    # Read the body: the gateway answers 503 {"db":"disconnected"} when its
    # Postgres is down, curl exits 0 on that, and your key lives in that
    # database. Starting the UI against it produces an empty model picker and
    # no explanation.
    gw_body=$(curl -s -m 5 "${GATEWAY}/health/readiness" 2>/dev/null)
    if [ -z "$gw_body" ]; then
      echo "Gateway ${GATEWAY} is unreachable."
      echo "  - is the gateway host awake and on the same network?"
      exit 1
    elif ! printf '%s' "$gw_body" | grep -qi '"db"[[:space:]]*:[[:space:]]*"connected"'; then
      echo "Gateway ${GATEWAY} is answering but its database is down."
      echo "  Your key will return 401. On the gateway host: scripts/boot.sh"
      exit 1
    fi
    echo "gateway: ${GATEWAY} — reachable (db:connected)"

    [ "$RT" = "podman" ] && { podman info >/dev/null 2>&1 || podman machine start; }
    $RT volume create "$VOLUME" >/dev/null 2>&1 || true
    $RT rm -f "$NAME" >/dev/null 2>&1 || true

    # SearXNG lives on the Studio's localhost. If an ssh tunnel is forwarding
    # 8888 to this machine, wire search up; otherwise leave it off rather than
    # configure something that fails on every query.
    SEARCH_ARGS=""
    if curl -s -m 3 -o /dev/null "http://127.0.0.1:8888/" 2>/dev/null; then
      SEARCH_ARGS="-e ENABLE_WEB_SEARCH=True -e ENABLE_RAG_WEB_SEARCH=True"
      SEARCH_ARGS="$SEARCH_ARGS -e WEB_SEARCH_ENGINE=searxng -e RAG_WEB_SEARCH_ENGINE=searxng"
      SEARCH_ARGS="$SEARCH_ARGS -e SEARXNG_QUERY_URL=http://${HOSTALIAS}:8888/search?q=<query>"
      echo "search:  tunnel to SearXNG detected on :8888"
    else
      echo "search:  no tunnel on :8888 — web search off ($0 tunnel)"
    fi

    # Bound to 127.0.0.1: this UI is for this machine only. It is a client, and
    # a client that serves other clients is a surprise nobody wants.
    $RT run -d \
      --name "$NAME" \
      --restart unless-stopped \
      -p "127.0.0.1:${PORT}:8080" \
      -e OPENAI_API_BASE_URL="${GATEWAY}/v1" \
      -e OPENAI_API_KEY="$KEY" \
      -e ENABLE_OLLAMA_API=False \
      -e ENABLE_SIGNUP=False \
      -e WEBUI_NAME="hearth ($(hostname -s))" \
      -e DEFAULT_MODELS="local-chat" \
      -e TASK_MODEL_EXTERNAL="local-chat" \
      -v "${VOLUME}:/app/backend/data" \
      $SEARCH_ARGS \
      "$IMAGE" >/dev/null || exit 1

    printf 'starting'
    i=0
    while [ "$i" -lt 60 ]; do
      curl -s -m 2 -o /dev/null "http://127.0.0.1:${PORT}/health" && break
      printf '.'; sleep 2; i=$((i+1))
    done
    echo

    cat <<EOF

  http://127.0.0.1:${PORT}

  Chat history is LOCAL to this machine — a separate database from the Studio's
  instance. Nothing is shared.

  Inference still runs on the Studio. If it sleeps, this stops working.

  ENABLE_OLLAMA_API=False is deliberate: there is no Ollama here anyway, and
  leaving it on makes the UI probe for one and show confusing errors.

  First visit creates a local account; signup is then disabled.

  Two settings on first run:
    Settings -> Interface -> Display "Response Info"
    Settings -> Advanced Params -> Function Calling: Default, NOT Native

EOF
    if [ -n "$SEARCH_ARGS" ]; then
      printf '  verifying the container can reach SearXNG... '
      if $RT exec "$NAME" curl -s -m 8 \
           "http://${HOSTALIAS}:8888/search?q=test&format=json" 2>/dev/null \
           | head -c 1 | grep -q '{'; then
        echo "ok"
        cat <<'EOF'

  Web search is wired, but Open WebUI's DATABASE overrides these env vars once
  it has been created. Turn it on where it counts:
    Admin Panel -> Settings -> Web Search -> Enable Web Search
    Engine: searxng
  Then it appears as a per-message toggle in the chat input.

  Keep the tunnel running, or search fails.
EOF
      else
        echo "FAILED"
        echo "  The container cannot reach ${HOSTALIAS}:8888 even though the"
        echo "  tunnel is up on the host. Search will fail on every query."
      fi
    else
      cat <<EOF

  Web search is OFF. SearXNG runs on the Studio, bound to its localhost.
  Start a tunnel, then re-run '$0 up':

    $0 tunnel

EOF
    fi
    ;;

  tunnel)
    cat <<EOF
Forwarding the Studio's SearXNG to this machine.

  ssh -N -L 8888:127.0.0.1:8888 ${STUDIO_HOST}

Leave that running in another terminal, then:

  $0 up

The tunnel only carries search. Chat already works without it — and remember
that a search query LEAVES the network even though the conversation does not,
so never enable web search on a chat involving client data.
EOF
    ;;

  down)    need_runtime; $RT stop "$NAME" >/dev/null && echo "stopped" ;;
  status)  need_runtime; $RT ps -a --filter "name=${NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" ;;
  logs)    need_runtime; $RT logs -f "$NAME" ;;
  destroy)
    need_runtime
    printf 'Delete this container and ALL local chat history? type destroy: '
    read -r c
    [ "$c" = "destroy" ] || exit 1
    $RT rm -f "$NAME" >/dev/null 2>&1 || true
    $RT volume rm "$VOLUME" >/dev/null 2>&1 || true
    echo "gone"
    ;;
  *) echo "usage: $0 {up|tunnel|down|status|logs|destroy}"; exit 1 ;;
esac
