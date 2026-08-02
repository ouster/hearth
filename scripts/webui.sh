#!/bin/bash
# Open WebUI — private chat surface on the gateway.
#
#   scripts/webui.sh up | down | status | logs | destroy
#
# Points at LiteLLM with the PRIVATE key, so the model picker shows local roles
# only and a cloud request is refused by the gateway rather than by intent.
# To reach cloud models deliberately, run `scripts/webui.sh up --general`.
#
# Bound to 127.0.0.1 like everything else — this is a browser tab on this
# machine, not a service for the LAN.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"
ai_load_env "$ROOT"

NAME="$(ai_container webui)"
VOLUME="$(ai_volume webui-data)"
IMAGE=ghcr.io/open-webui/open-webui:main
PORT=3000

CMD="${1:-status}"
SCOPE="private"
BIND="127.0.0.1"
for a in "$@"; do
  [ "$a" = "--general" ] && SCOPE="general"
  # --lan exposes the UI to the whole network. Open WebUI has its own login, so
  # this is not wide open — but it is another authenticated surface on a machine
  # whose other services are deliberately localhost-only. The SSH tunnel in
  # docs/RUNBOOK.md gives laptop access without opening anything.
  [ "$a" = "--lan" ] && BIND="0.0.0.0"
done

case "$CMD" in
  up)
    if [ "$SCOPE" = "general" ]; then
      KEY="${LITELLM_GENERAL_KEY:?LITELLM_GENERAL_KEY not set}"
      echo "scope: GENERAL — cloud roles reachable from the browser"
    else
      KEY="${LITELLM_PRIVATE_KEY:?LITELLM_PRIVATE_KEY not set}"
      echo "scope: PRIVATE — local roles only, cloud structurally refused"
    fi

    podman info >/dev/null 2>&1 || { echo "podman VM not running: podman machine start"; exit 1; }
    curl -s -m 5 -o /dev/null http://127.0.0.1:4000/health/readiness \
      || { echo "gateway not responding on :4000"; exit 1; }

    podman volume exists "$VOLUME" 2>/dev/null || podman volume create "$VOLUME" >/dev/null

    if podman container exists "$NAME" 2>/dev/null; then
      echo "removing existing container so the key/scope takes effect"
      podman rm -f "$NAME" >/dev/null
    fi

    # Web search is wired up only if SearXNG is actually running. It is opt-in
    # per conversation in the UI even then — see docs/ROUTING.md for why it
    # must never be used on client work.
    SEARCH_HOST="${SEARXNG_HOST:-host.containers.internal}"
    SEARCH_ENV=()
    if curl -s -m 3 -o /dev/null "http://127.0.0.1:8888/" 2>/dev/null; then
      SEARCH_ENV=(
        -e ENABLE_WEB_SEARCH=True
        -e ENABLE_RAG_WEB_SEARCH=True
        -e WEB_SEARCH_ENGINE=searxng
        -e RAG_WEB_SEARCH_ENGINE=searxng
        -e SEARXNG_QUERY_URL="http://${SEARCH_HOST}:8888/search?q=<query>"
      )
      echo "search: SearXNG detected — env vars set (see the note after startup)"
    else
      echo "search: none (start it with scripts/searxng.sh up)"
    fi

    podman run -d \
      --name "$NAME" \
      --restart unless-stopped \
      -p "${BIND}:${PORT}:8080" \
      -e OPENAI_API_BASE_URL="http://host.containers.internal:4000/v1" \
      -e OPENAI_API_KEY="$KEY" \
      -e ENABLE_OLLAMA_API=False \
      -e WEBUI_NAME="hearth (${SCOPE})" \
      -e ENABLE_SIGNUP=False \
      -e TASK_MODEL_EXTERNAL="local-chat" \
      -e DEFAULT_MODELS="local-chat" \
      ${SEARCH_ENV[@]+"${SEARCH_ENV[@]}"} \
      -v "${VOLUME}:/app/backend/data" \
      "$IMAGE" >/dev/null

    printf 'starting'
    for _ in $(seq 1 60); do
      curl -s -m 2 -o /dev/null "http://127.0.0.1:${PORT}/health" && break
      printf '.'; sleep 2
    done
    echo

    # Reachability must be checked from INSIDE the container. Curling :8888
    # from the host proves the service is up, not that host.containers.internal
    # resolves within Podman's VM — and only the latter matters.
    if [ "${#SEARCH_ENV[@]}" -gt 0 ]; then
      printf 'verifying the container can reach SearXNG... '
      if podman exec "$NAME" curl -s -m 8 \
           "http://host.containers.internal:8888/search?q=test&format=json" 2>/dev/null \
           | head -c 1 | grep -q '{'; then
        echo "ok"
      else
        echo "FAILED"
        echo "  The container cannot reach SearXNG at host.containers.internal:8888."
        echo "  Search is enabled in the UI but every query will fail."
        echo
        echo "  Find the address Podman's VM uses for the host:"
        echo "    podman exec ${NAME} sh -c 'ip route | awk \"/default/ {print \\\$3}\"'"
        echo "  then re-run with that address:"
        echo "    SEARXNG_HOST=<addr> scripts/webui.sh up"
      fi
    fi

    cat <<EOF

  http://127.0.0.1:${PORT}

  First visit asks you to create an account — it is local to the container,
  nothing leaves the machine. Signup is then disabled.

  ENABLE_OLLAMA_API=False is deliberate: without it Open WebUI would talk to
  Ollama directly and bypass the gateway, which is the exact hole Phase 3 closed.

  Default model and title/tag generation are pinned to local-chat, so general
  questions do not land on a coding model and housekeeping cannot become spend.

  Two settings worth changing on first run:
    Settings -> Interface -> Display "Response Info"   (model + token counts)
    Settings -> Advanced Params -> Function Calling: Default, NOT Native
      Native tool calling makes small local models invent tool calls instead
      of answering. That is what produced query_knowledge_files loops.

  WEB SEARCH — the env vars above are NOT sufficient on their own.
    Open WebUI stores these as config values in its database, and the DATABASE
    VALUE TAKES PRECEDENCE over the environment. The env vars only seed a fresh
    database. This container reuses the hearth-webui-data volume, so whatever
    was written on first run wins — which is why the toggle can be missing even
    though 'podman exec hearth-webui env' shows it enabled.

    Turn it on where it actually counts:
      Admin Panel -> Settings -> Web Search -> Enable Web Search
      Engine: searxng
      Query URL: http://host.containers.internal:8888/search?q=<query>

    The toggle then appears in the chat input, per message. If it later vanishes,
    it is usually a stale access token — sign out and back in.

    To start genuinely fresh instead: scripts/webui.sh destroy (loses chat history).

  For the fuller picture — which role, which actual model, local or cloud,
  tokens and cost — use:  scripts/usage.sh
EOF
    ;;

  down)    podman stop "$NAME" >/dev/null && echo "stopped" ;;
  status)  podman ps -a --filter "name=${NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" ;;
  logs)    podman logs -f "$NAME" ;;
  destroy)
    read -r -p "Delete container and all chat history? type destroy: " c
    [ "$c" = "destroy" ] || exit 1
    podman rm -f "$NAME" >/dev/null 2>&1 || true
    podman volume rm "$VOLUME" >/dev/null 2>&1 || true
    echo "gone"
    ;;
  *) echo "usage: $0 {up [--general] [--lan]|down|status|logs|destroy}"; exit 1 ;;
esac
