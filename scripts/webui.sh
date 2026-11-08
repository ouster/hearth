#!/bin/bash
# Open WebUI — private chat surface on oMLX (ADR 0026).
#
#   scripts/webui.sh up | down | status | logs | destroy
#
# Points at oMLX on the host (:1234) with the host token. oMLX holds only
# local models, so nothing the browser sends can leave the machine. There
# is no cloud mode.
#
# Authentication is off, so every browser is the same user. Open WebUI
# creates that user as admin, and this image does not enforce temporary
# chat for admins — which is how one anonymous session remembered, and
# shared, every chat. up demotes the user, turns sharing off, deletes
# saved chats, and refuses new chat rows. The page then runs as a
# temporary chat: a refresh starts empty.
#
# The container reaches the host's 127.0.0.1:1234 via host.containers.internal
# (Podman's host forwarding) with "serve on local network" off — checked
# 2026-10-31. SearXNG is reached by container name on the hearth network
# (internal port 8080). The host's 127.0.0.1:8888 is for Zed and tunnels.
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

# /health, then return. Open WebUI is slow on a cold start.
wait_webui() {
  printf '%s' "$1"
  for _ in $(seq 1 60); do
    if curl -s -m 2 -o /dev/null "http://127.0.0.1:${PORT}/health"; then
      echo
      return 0
    fi
    printf '.'
    sleep 2
  done
  echo
  echo "Open WebUI did not become healthy on :${PORT}"
  return 1
}

# The permission env vars only seed a fresh database. This volume already
# has them, and the database wins. Patch it, then the caller restarts so
# the process reloads. oMLX models have no access-grant row, so a non-admin
# would see an empty list without BYPASS_MODEL_ACCESS_CONTROL.
lock_anon_chats() {
  podman exec -e HEARTH_SEARXNG_URL="${HEARTH_SEARXNG_URL:-}" -i "$NAME" python3 - <<'PY'
import json
import os
import sqlite3
import time
import urllib.error
import urllib.request

def signin():
    last = "unreachable"
    body = json.dumps({"email": "x", "password": "x"}).encode()
    for _ in range(15):
        req = urllib.request.Request(
            "http://127.0.0.1:8080/api/v1/auths/signin",
            data=body,
            headers={"Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                resp.read()
                return
        except urllib.error.HTTPError as exc:
            last = exc.code
        except Exception as exc:
            last = type(exc).__name__
        time.sleep(2)
    raise SystemExit("signin failed: %s" % last)

signin()
db = sqlite3.connect("/app/backend/data/webui.db")
now = int(time.time())
row = db.execute(
    "select value from config where key=?", ("user.permissions",)
).fetchone()
if row is None:
    raise SystemExit("user.permissions missing from the WebUI database")
perms = json.loads(row[0])
chat = perms.setdefault("chat", {})
chat["temporary"] = True
chat["temporary_enforced"] = True
chat["share"] = False
db.execute(
    "update config set value=?, updated_at=? where key=?",
    (json.dumps(perms, separators=(",", ":")), now, "user.permissions"),
)
db.execute(
    "update config set value=?, updated_at=? where key=?",
    ("false", now, "ui.enable_community_sharing"),
)
search_url = os.environ.get("HEARTH_SEARXNG_URL", "")
if search_url:
    # The database wins over the container env. Stored values are JSON.
    for key, val in (
        ("web.search.enable", "true"),
        ("web.search.engine", json.dumps("searxng")),
        ("web.search.searxng_query_url", json.dumps(search_url)),
    ):
        n = db.execute("select count(*) from config where key=?", (key,)).fetchone()[0]
        if n:
            db.execute(
                "update config set value=?, updated_at=? where key=?",
                (val, now, key),
            )
        else:
            db.execute(
                "insert into config (key, value, updated_at) values (?,?,?)",
                (key, val, now),
            )
found = db.execute(
    "select count(*) from user where lower(email)=?",
    ("admin@localhost",),
).fetchone()[0]
if found != 1:
    raise SystemExit("anonymous user missing; signin did not create it")
db.execute(
    "update user set role=? where lower(email)=?",
    ("user", "admin@localhost"),
)
tables = {
    r[0]
    for r in db.execute("select name from sqlite_master where type='table'")
}
for table in ("chat_message", "chat_file", "chatidtag", "shared_chat", "chat"):
    if table in tables:
        db.execute("delete from %s" % table)
if "feedback" in tables:
    cols = [r[1] for r in db.execute("pragma table_info(feedback)")]
    if "chat_id" in cols:
        db.execute("delete from feedback")
db.executescript(
    """
    CREATE TRIGGER IF NOT EXISTS hearth_refuse_chat
    BEFORE INSERT ON chat
    BEGIN
      SELECT RAISE(ABORT, 'anonymous chats are not saved');
    END;
    CREATE TRIGGER IF NOT EXISTS hearth_refuse_chat_message
    BEFORE INSERT ON chat_message
    BEGIN
      SELECT RAISE(ABORT, 'anonymous chats are not saved');
    END;
    CREATE TRIGGER IF NOT EXISTS hearth_refuse_shared_chat
    BEFORE INSERT ON shared_chat
    BEGIN
      SELECT RAISE(ABORT, 'anonymous chats are not shared');
    END;
    """
)
db.commit()
print("anonymous chats locked")
PY
}

# Confirms the running process, not just the database: role, permissions,
# the model list, and that a normal chat save is refused.
verify_anon_chats() {
  podman exec -i "$NAME" python3 - <<'PY'
import json
import sqlite3
import urllib.error
import urllib.request

def request(method, path, token, payload=None):
    data = None if payload is None else json.dumps(payload).encode()
    headers = {"Authorization": "Bearer " + token}
    if data is not None:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(
        "http://127.0.0.1:8080" + path, data=data, headers=headers, method=method
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            return resp.status, json.loads(resp.read().decode() or "null")
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode(errors="replace")
        try:
            body = json.loads(raw)
        except Exception:
            body = raw[:200]
        return exc.code, body

signin = urllib.request.Request(
    "http://127.0.0.1:8080/api/v1/auths/signin",
    data=json.dumps({"email": "x", "password": "x"}).encode(),
    headers={"Content-Type": "application/json"},
)
with urllib.request.urlopen(signin, timeout=10) as resp:
    user = json.loads(resp.read().decode())
token = user.get("token") or ""
chat = (user.get("permissions") or {}).get("chat") or {}
if user.get("role") != "user" or not chat.get("temporary_enforced") or chat.get("share"):
    raise SystemExit(
        "anon chat policy did not load: role=%s temporary_enforced=%s share=%s"
        % (user.get("role"), chat.get("temporary_enforced"), chat.get("share"))
    )
status, models = request("GET", "/api/models", token)
ids = []
if isinstance(models, dict):
    ids = [m.get("id") for m in models.get("data") or []]
if status != 200 or "main-brain" not in ids:
    raise SystemExit("model list missing main-brain (%s)" % status)
status, body = request(
    "POST", "/api/v1/chats/new", token, {"chat": {"title": "probe"}}
)
db = sqlite3.connect("/app/backend/data/webui.db")
left = db.execute("select count(*) from chat").fetchone()[0]
if status == 200 or left != 0:
    raise SystemExit("chat save was accepted (http %s, rows %s)" % (status, left))
print("anonymous chats are not saved")
PY
}

CMD="${1:-status}"
BIND="127.0.0.1"
for a in "$@"; do
  # Authentication is off. A LAN bind would be an open chat UI on every
  # interface. Laptops use the SSH tunnel in docs/RUNBOOK.md.
  if [ "$a" = "--lan" ]; then
    echo "refusing --lan: authentication is off, so a LAN bind would be an open chat UI"
    exit 1
  fi
done

case "$CMD" in
  up)
    KEY="${OMLX_HOST_TOKEN:?OMLX_HOST_TOKEN not set in ~/.config/hearth/env}"

    podman info >/dev/null 2>&1 || { echo "podman VM not running: podman machine start"; exit 1; }
    # 200 with the token, not just "answering": a 401 here means the UI would
    # come up with an empty model list.
    code=$(hearth_http /models "$KEY")
    case "$code" in
      200) : ;;
      401) echo "oMLX refused the host token (401) — check OMLX_HOST_TOKEN"; exit 1 ;;
      000) echo "oMLX not answering on :1234 — scripts/omlx.sh up"; exit 1 ;;
      *)   echo "oMLX answered ${code} on /v1/models"; exit 1 ;;
    esac

    podman volume exists "$VOLUME" 2>/dev/null || podman volume create "$VOLUME" >/dev/null

    if podman container exists "$NAME" 2>/dev/null; then
      echo "removing existing container so the endpoint and token take effect"
      podman rm -f "$NAME" >/dev/null
    fi

    # Web search is wired up only if SearXNG is actually running. It is opt-in
    # per conversation. The query leaves, and an agent can put personal
    # information it has just read into that query. See docs/ROUTING.md.
    SEARCH_ENV=()
    HEARTH_SEARXNG_URL=""
    SEARXNG_NAME="$(ai_container searxng)"
    if curl -s -m 3 -o /dev/null "http://127.0.0.1:8888/" 2>/dev/null \
       && podman container exists "$SEARXNG_NAME" 2>/dev/null; then
      hearth_podman_connect "$SEARXNG_NAME"
      # 8080 is the container port. 8888 is only the host's loopback publish.
      HEARTH_SEARXNG_URL="http://${SEARXNG_NAME}:8080/search?q=<query>"
      SEARCH_ENV=(
        -e ENABLE_WEB_SEARCH=True
        -e ENABLE_RAG_WEB_SEARCH=True
        -e WEB_SEARCH_ENGINE=searxng
        -e RAG_WEB_SEARCH_ENGINE=searxng
        -e SEARXNG_QUERY_URL="$HEARTH_SEARXNG_URL"
      )
      export HEARTH_SEARXNG_URL
      echo "search: ${SEARXNG_NAME}:8080 on the hearth network"
    else
      echo "search: none (start it with scripts/searxng.sh up)"
    fi

    # Secret on stdin, then into the container as an env var. Not -e, so the
    # token is not on podman's command line or in the container's Config.Env.
    # (printf's argv is the short-lived pipe; same pattern as hearth_http.)
    printf '%s' "$KEY" | podman secret create --replace hearth-omlx-token - >/dev/null
    hearth_podman_net
    podman run -d \
      --name "$NAME" \
      --restart unless-stopped \
      --network hearth \
      -p "${BIND}:${PORT}:8080" \
      --secret hearth-omlx-token,type=env,target=OPENAI_API_KEY \
      -e OPENAI_API_BASE_URL="http://host.containers.internal:1234/v1" \
      -e ENABLE_OLLAMA_API=False \
      -e WEBUI_NAME="hearth" \
      -e WEBUI_AUTH=False \
      -e USER_PERMISSIONS_CHAT_TEMPORARY=True \
      -e USER_PERMISSIONS_CHAT_TEMPORARY_ENFORCED=True \
      -e USER_PERMISSIONS_CHAT_SHARE=False \
      -e ENABLE_COMMUNITY_SHARING=False \
      -e BYPASS_MODEL_ACCESS_CONTROL=True \
      -e TASK_MODEL_EXTERNAL="main-brain" \
      -e DEFAULT_MODELS="main-brain" \
      ${SEARCH_ENV[@]+"${SEARCH_ENV[@]}"} \
      -v "${VOLUME}:/app/backend/data" \
      "$IMAGE" >/dev/null

    wait_webui 'starting'
    lock_anon_chats
    podman restart "$NAME" >/dev/null
    wait_webui 'reloading'
    verify_anon_chats

    # Reachability must be checked from INSIDE the container. Curling :8888
    # from the host proves the service is up, not that host.containers.internal
    # resolves within Podman's VM — and only the latter matters.
    if [ -n "$HEARTH_SEARXNG_URL" ]; then
      printf 'verifying the container can reach SearXNG... '
      if podman exec "$NAME" curl -s -m 8 \
           "http://${SEARXNG_NAME}:8080/search?q=test&format=json" 2>/dev/null \
           | head -c 1 | grep -q '{'; then
        echo "ok"
      else
        echo "FAILED"
        echo "  The container cannot reach ${SEARXNG_NAME}:8080 on the hearth network."
        echo "  Search is enabled in the UI but every query will fail."
        echo "  Re-run scripts/searxng.sh up, then scripts/webui.sh up."
        exit 1
      fi
    fi

    cat <<EOF

  http://127.0.0.1:${PORT}   (published on ${BIND}:${PORT})

  No login. WEBUI_AUTH is off, so the page opens straight into chat.
  That session is not an admin. Chats are temporary: nothing is saved, the
  share action is off, and a refresh starts empty. Saved chats were deleted.
  The UI stays on 127.0.0.1. --lan is refused. A laptop uses the SSH tunnel.

  CONNECTION — Open WebUI stores the OpenAI endpoint and key in its
  database, and that value wins over the environment. up does not rewrite
  it. The anonymous session cannot open the admin panel.

  Default model and title/tag generation are main-brain (D1): one resident
  model, so housekeeping never evicts anything.

  Two settings worth changing on first run:
    Settings -> Interface -> Display "Response Info"   (model + token counts)
    Settings -> Advanced Params -> Function Calling: Default, NOT Native
      Native tool calling makes small local models invent tool calls instead
      of answering. That is what produced query_knowledge_files loops.

  WEB SEARCH — up writes the SearXNG URL into the database, which is what
    the toggle uses. The toggle is still per message, in the chat input.
    The query text leaves. Leave it off on anything you would not type into
    a search engine.

    To start genuinely fresh instead: scripts/webui.sh destroy (deletes the
    volume, including the saved connection).

  To see what the server is doing:  tail -f ~/Library/Logs/hearth-omlx.log
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
    podman secret rm hearth-omlx-token >/dev/null 2>&1 || true
    echo "gone"
    ;;
  *) echo "usage: $0 {up|down|status|logs|destroy}"; exit 1 ;;
esac
