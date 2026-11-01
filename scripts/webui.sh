#!/bin/bash
# Open WebUI — private chat surface on LM Studio (ADR 0016, D5).
#
#   scripts/webui.sh up | down | status | logs | destroy
#
# Points at LM Studio on the host (:1234) with the host token. LM Studio holds
# only local models, so nothing the browser sends can leave the machine. There
# is no cloud mode: the gateway that made `--general` possible is gone.
#
# The container reaches the host's 127.0.0.1:1234 via host.containers.internal
# (Podman's host forwarding) with "serve on local network" off — checked
# 2026-10-31.
#
# Bound to 127.0.0.1 like everything else — this is a browser tab on this
# machine, not a service for the LAN.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"
ai_load_env

NAME="$(ai_container webui)"
VOLUME="$(ai_volume webui-data)"
IMAGE=ghcr.io/open-webui/open-webui:main
PORT=3000

CMD="${1:-status}"
BIND="127.0.0.1"
for a in "$@"; do
  # --lan exposes the UI to the whole network. Open WebUI has its own login, so
  # this is not wide open — but it is another authenticated surface on a machine
  # whose other services are deliberately localhost-only. The SSH tunnel in
  # docs/RUNBOOK.md gives laptop access without opening anything.
  [ "$a" = "--lan" ] && BIND="0.0.0.0"
done

case "$CMD" in
  up)
    KEY="${LMSTUDIO_HOST_TOKEN:?LMSTUDIO_HOST_TOKEN not set in ~/.config/hearth/env}"

    podman info >/dev/null 2>&1 || { echo "podman VM not running: podman machine start"; exit 1; }
    # 200 with the token, not just "answering": a 401 here means the UI would
    # come up with an empty model list.
    code=$(hearth_http /models "$KEY")
    case "$code" in
      200) : ;;
      401) echo "LM Studio refused the host token (401) — check LMSTUDIO_HOST_TOKEN"; exit 1 ;;
      000) echo "LM Studio not answering on :1234 — lms server start --bind 127.0.0.1 -p 1234"; exit 1 ;;
      *)   echo "LM Studio answered ${code} on /v1/models"; exit 1 ;;
    esac

    podman volume exists "$VOLUME" 2>/dev/null || podman volume create "$VOLUME" >/dev/null

    if podman container exists "$NAME" 2>/dev/null; then
      echo "removing existing container so the endpoint and token take effect"
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

    # Secret on stdin, then into the container as an env var. Not -e, so the
    # token is not on podman's command line or in the container's Config.Env.
    # (printf's argv is the short-lived pipe; same pattern as hearth_http.)
    printf '%s' "$KEY" | podman secret create --replace hearth-lmstudio-token - >/dev/null
    podman run -d \
      --name "$NAME" \
      --restart unless-stopped \
      -p "${BIND}:${PORT}:8080" \
      --secret hearth-lmstudio-token,type=env,target=OPENAI_API_KEY \
      -e OPENAI_API_BASE_URL="http://host.containers.internal:1234/v1" \
      -e ENABLE_OLLAMA_API=False \
      -e WEBUI_NAME="hearth" \
      -e ENABLE_SIGNUP=False \
      -e TASK_MODEL_EXTERNAL="local-main" \
      -e DEFAULT_MODELS="local-main" \
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

    if [ "$BIND" = "0.0.0.0" ]; then
      cat <<EOF

  WARNING: Open WebUI is bound to 0.0.0.0:${PORT}.
  That is every interface, not only this machine. It has its own login.
  The SSH tunnel (docs/LAPTOP.md) is the way a laptop should reach it.
EOF
    fi

    cat <<EOF

  http://127.0.0.1:${PORT}   (published on ${BIND}:${PORT})

  First visit asks you to create an account — it is local to the container,
  nothing leaves the machine. Signup is then disabled.

  CONNECTION — like web search below, Open WebUI stores the OpenAI endpoint
  and key in its database, and the DATABASE VALUE wins over the environment.
  If the model list is empty, set it where it counts:
    Admin Panel -> Settings -> Connections -> OpenAI API
      URL: http://host.containers.internal:1234/v1
      Key: the host token (LMSTUDIO_HOST_TOKEN)
    Delete any leftover :4000 or :11434 connection.

  Default model and title/tag generation are local-main (D1): one resident
  model, so housekeeping never evicts anything.

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

  To see what the server is doing:  lms log stream
EOF
    # Best effort, in the background: snapshot the running image for Snyk.
    "${ROOT}/scripts/snyk-monitor.sh" webui >>"$HOME/Library/Logs/hearth-snyk.log" 2>&1 &
    ;;

  down)    podman stop "$NAME" >/dev/null && echo "stopped" ;;
  status)  podman ps -a --filter "name=${NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" ;;
  logs)    podman logs -f "$NAME" ;;
  destroy)
    read -r -p "Delete container and all chat history? type destroy: " c
    [ "$c" = "destroy" ] || exit 1
    podman rm -f "$NAME" >/dev/null 2>&1 || true
    podman volume rm "$VOLUME" >/dev/null 2>&1 || true
    podman secret rm hearth-lmstudio-token >/dev/null 2>&1 || true
    echo "gone"
    ;;
  *) echo "usage: $0 {up [--lan]|down|status|logs|destroy}"; exit 1 ;;
esac
