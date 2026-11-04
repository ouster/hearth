#!/bin/bash
# Trial: serve local-main from oMLX on 127.0.0.1:1234 so its RAM+SSD KV cache
# can be measured. LM Studio is stopped for the trial. `down` starts it again
# and reloads config/roles.tsv. A reboot runs scripts/boot.sh, which takes the
# port back. This does not change the role.
#
#   scripts/omlx-try.sh up | down | status | bench
#   scripts/omlx-try.sh sub-key list
#   scripts/omlx-try.sh sub-key add <name>      # token on stdin, not echoed
#   scripts/omlx-try.sh sub-key revoke <name>
#
# Weights, context, and slots come from the resident local-main row. The API
# key is the existing host token, written to ~/.omlx/settings.json (mode 600)
# and never printed. Clients that already send that token keep working.
# A laptop token is a different key. `sub-key add` registers one the operator
# pastes; it can call the model and cannot log in as admin. LM Studio stores
# only a hash, so the script cannot copy the token itself. `up` keeps
# sub-keys already in the settings file.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"
ai_load_env

OMLX_HOME="${OMLX_HOME:-$HOME/.omlx}"
MODEL_DIR="${OMLX_HOME}/models"
MODEL_LINK="${MODEL_DIR}/local-main"
PIDFILE="${OMLX_HOME}/hearth.pid"
LOG="${HOME}/Library/Logs/hearth-omlx.log"
LABEL="com.hearth.omlx-try"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
SETTINGS="${OMLX_HOME}/settings.json"
HOT_CACHE="8GB"
SSD_CACHE="20GB"
GUARD_GB=48
CMD="${1:-status}"

fail() { echo "omlx-try: $*" >&2; exit 1; }

find_omlx() {
  local c
  for c in /opt/homebrew/bin/omlx "${HOME}/.omlx/bin/omlx" "${HOME}/.omlx/venv/bin/omlx"; do
    [ -x "$c" ] && { printf '%s' "$c"; return 0; }
  done
  c="$(command -v omlx 2>/dev/null || true)"
  [ -n "$c" ] && [ -x "$c" ] && { printf '%s' "$c"; return 0; }
  return 1
}

role_fields() {
  awk -F'\t' '!/^[[:space:]]*(#|$)/ && $1=="local-main" && $2=="lmstudio" && $8=="resident" {
    print $4 "\t" $5 "\t" $6; exit
  }' "${ROOT}/config/roles.tsv"
}

listener() {
  lsof -nP -iTCP:"${HEARTH_PORT}" -sTCP:LISTEN 2>/dev/null | awk 'NR==2 {print $1}'
}

omlx_running() {
  launchctl print "gui/$(id -u)/${LABEL}" 2>/dev/null | grep -q 'state = running'
}

stop_omlx() {
  launchctl bootout "gui/$(id -u)/${LABEL}" >/dev/null 2>&1 || true
  if [ -f "$PIDFILE" ]; then
    pid="$(cat "$PIDFILE" 2>/dev/null || true)"
    if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
    fi
    rm -f "$PIDFILE"
  fi
  i=0
  while [ "$i" -lt 20 ] && omlx_running; do
    sleep 0.5
    i=$((i + 1))
  done
}

start_omlx() {
  mkdir -p "${HOME}/Library/LaunchAgents" "$(dirname "$LOG")"
  /usr/bin/python3 -I - "$PLIST" "$OMLX" "$HEARTH_PORT" "$MODEL_DIR" "$GUARD_GB" \
    "${OMLX_HOME}/cache" "$SSD_CACHE" "$HOT_CACHE" "$SLOTS" "$LOG" "$LABEL" <<'PY'
import plistlib, sys
path, omlx, port, model_dir, guard, cache, ssd, hot, slots, log, label = sys.argv[1:]
doc = {
    "Label": label,
    "ProgramArguments": [
        omlx, "serve",
        "--host", "127.0.0.1",
        "--port", port,
        "--model-dir", model_dir,
        "--memory-guard-gb", guard,
        "--paged-ssd-cache-dir", cache,
        "--paged-ssd-cache-max-size", ssd,
        "--hot-cache-max-size", hot,
        "--max-concurrent-requests", slots,
    ],
    "RunAtLoad": False,
    "KeepAlive": False,
    "StandardOutPath": log,
    "StandardErrorPath": log,
}
with open(path, "wb") as f:
    plistlib.dump(doc, f)
PY
  launchctl bootout "gui/$(id -u)/${LABEL}" >/dev/null 2>&1 || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST"
  launchctl kickstart "gui/$(id -u)/${LABEL}"
}

restore_lms() {
  echo "restoring LM Studio on 127.0.0.1:${HEARTH_PORT}"
  hearth_server_start >/dev/null
  "${ROOT}/scripts/lms-load.sh"
}

write_settings() {
  [ -n "${LMSTUDIO_HOST_TOKEN:-}" ] || fail "LMSTUDIO_HOST_TOKEN is not set"
  mkdir -p "$OMLX_HOME" "$MODEL_DIR" "${OMLX_HOME}/cache" "$(dirname "$LOG")"
  chmod 700 "$OMLX_HOME" "${OMLX_HOME}/cache" 2>/dev/null || true
  OMLX_API_KEY="$LMSTUDIO_HOST_TOKEN" \
  OMLX_SETTINGS="$SETTINGS" \
  OMLX_MODEL_DIR="$MODEL_DIR" \
  OMLX_CACHE_DIR="${OMLX_HOME}/cache" \
  OMLX_PORT="$HEARTH_PORT" \
  OMLX_CTX="$CTX" \
  OMLX_SLOTS="$SLOTS" \
  OMLX_HOT="$HOT_CACHE" \
  OMLX_SSD="$SSD_CACHE" \
  OMLX_GUARD="$GUARD_GB" \
  /usr/bin/python3 -I - <<'PY'
import json, os
path = os.environ["OMLX_SETTINGS"]
kept_sub = []
kept_secret = None
if os.path.isfile(path):
    try:
        old = json.load(open(path))
    except ValueError:
        old = {}
    auth_old = old.get("auth") if isinstance(old, dict) else None
    if isinstance(auth_old, dict):
        secret = auth_old.get("secret_key")
        if isinstance(secret, str) and secret:
            kept_secret = secret
        subs = auth_old.get("sub_keys")
        if isinstance(subs, list):
            for sk in subs:
                if not isinstance(sk, dict):
                    continue
                key = sk.get("key")
                if not isinstance(key, str) or not key:
                    continue
                name = sk.get("name") if isinstance(sk.get("name"), str) else ""
                created = sk.get("created_at") if isinstance(sk.get("created_at"), str) else ""
                kept_sub.append({"key": key, "name": name, "created_at": created})
auth = {
    "api_key": os.environ["OMLX_API_KEY"],
    "skip_api_key_verification": False,
    "allow_unauthenticated_inference": False,
    "sub_keys": kept_sub,
}
if kept_secret is not None:
    auth["secret_key"] = kept_secret
doc = {
  "version": "1.0",
  "server": {
    "host": "127.0.0.1",
    "port": int(os.environ["OMLX_PORT"]),
    "log_level": "info",
    "cors_origins": [],
  },
  "model": {
    "model_dirs": [os.environ["OMLX_MODEL_DIR"]],
    "model_dir": os.environ["OMLX_MODEL_DIR"],
    "model_fallback": False,
  },
  "memory": {
    "prefill_memory_guard": True,
    "memory_guard_tier": "custom",
    "memory_guard_custom_ceiling_gb": float(os.environ["OMLX_GUARD"]),
  },
  "scheduler": {"max_concurrent_requests": int(os.environ["OMLX_SLOTS"])},
  "cache": {
    "enabled": True,
    "hot_cache_only": False,
    "ssd_cache_dir": os.environ["OMLX_CACHE_DIR"],
    "ssd_cache_max_size": os.environ["OMLX_SSD"],
    "hot_cache_max_size": os.environ["OMLX_HOT"],
  },
  "sampling": {
    "max_context_window": int(os.environ["OMLX_CTX"]),
    "max_context_window_policy": int(os.environ["OMLX_CTX"]),
    "max_tokens": 65536,
    "temperature": 1.0,
    "top_p": 0.95,
    "top_k": 64,
    "repetition_penalty": 1.0,
  },
  "auth": auth,
  "mcp": {"config_path": None, "expose_tools": False},
  "huggingface": {"endpoint": "", "hf_cache_enabled": False},
}
with open(path, "w") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")
os.chmod(path, 0o600)
PY
}

link_weights() {
  src="${HOME}/.lmstudio/models/${WEIGHTS}"
  [ -d "$src" ] || fail "weights missing: ${src}"
  mkdir -p "$MODEL_DIR"
  if [ -e "$MODEL_LINK" ] && [ ! -L "$MODEL_LINK" ]; then
    fail "${MODEL_LINK} exists and is not a symlink"
  fi
  ln -sfn "$src" "$MODEL_LINK"
}

configure_model() {
  OMLX_API_KEY="$LMSTUDIO_HOST_TOKEN" \
  OMLX_PORT="$HEARTH_PORT" \
  OMLX_CTX="$CTX" \
  /usr/bin/python3 -I - <<'PY'
import json, os, time, urllib.error, urllib.request, http.cookiejar
base = "http://127.0.0.1:%s" % os.environ["OMLX_PORT"]
key = os.environ["OMLX_API_KEY"]
ctx = int(os.environ["OMLX_CTX"])
jar = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))

def call(method, path, body=None, timeout=30):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(base + path, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    req.add_header("Authorization", "Bearer " + key)
    try:
        with opener.open(req, timeout=timeout) as resp:
            raw = resp.read().decode()
            return resp.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read().decode(errors="replace")
        try:
            parsed = json.loads(raw)
        except ValueError:
            parsed = {"detail": raw[:300]}
        return e.code, parsed

code, _ = call("POST", "/admin/api/login", {"api_key": key})
if code != 200:
    raise SystemExit("admin login failed (%s)" % code)

code, listing = call("GET", "/v1/models")
if code != 200:
    raise SystemExit("/v1/models failed (%s)" % code)
ids = [m.get("id") for m in listing.get("data") or [] if m.get("id")]
if not ids:
    raise SystemExit("no models discovered")
if len(ids) != 1 and "local-main" not in ids:
    raise SystemExit("expected one model, found %s" % len(ids))
mid = "local-main" if "local-main" in ids else ids[0]
if mid != "local-main":
    code, body = call("PUT", "/admin/api/models/%s/settings" % mid, {"model_alias": "local-main"})
    if code != 200:
        raise SystemExit("alias failed (%s): %s" % (code, body.get("detail", "")[:200]))
    mid = "local-main"

settings = {
    "enable_thinking": True,
    "chat_template_kwargs": {"enable_thinking": True},
    "reasoning_parser": "gemma",
    "temperature": 1.0,
    "top_p": 0.95,
    "top_k": 64,
    "repetition_penalty": 1.0,
    "max_context_window": ctx,
    "max_tokens": 65536,
    "is_pinned": True,
}
code, body = call("PUT", "/admin/api/models/%s/settings" % mid, settings)
if code != 200:
    raise SystemExit("model settings failed (%s): %s" % (code, str(body.get("detail", ""))[:300]))

code, body = call("POST", "/admin/api/models/%s/load" % mid, None, timeout=600)
if code != 200:
    raise SystemExit("load failed (%s): %s" % (code, str(body.get("detail", ""))[:300]))

deadline = time.time() + 300
loaded = False
while time.time() < deadline:
    code, body = call("GET", "/admin/api/models")
    if code == 200:
        for m in body.get("models") or []:
            if m.get("id") in (mid, "local-main") and m.get("loaded"):
                loaded = True
                break
    if loaded:
        break
    time.sleep(2)
if not loaded:
    raise SystemExit("model did not report loaded")
print("loaded local-main")
PY
}

cmd_up() {
  OMLX="$(find_omlx)" || fail "omlx not installed"
  row="$(role_fields)"
  [ -n "$row" ] || fail "no resident local-main row in config/roles.tsv"
  CTX="$(printf '%s' "$row" | cut -f1)"
  SLOTS="$(printf '%s' "$row" | cut -f2)"
  WEIGHTS="$(printf '%s' "$row" | cut -f3)"
  case "$CTX" in ''|*[!0-9]*) fail "context is not an integer" ;; esac
  case "$SLOTS" in ''|*[!0-9]*) fail "slots is not an integer" ;; esac

  who="$(listener || true)"
  case "$who" in
    "" ) ;;
    omlx|Python|python* ) echo "oMLX already listening on ${HEARTH_PORT}"; exit 0 ;;
    LM*|lms ) ;;
    * ) fail "port ${HEARTH_PORT} is held by ${who}" ;;
  esac

  write_settings
  link_weights

  if [ -n "$who" ]; then
    echo "stopping LM Studio server (the app stays open)"
    "$HEARTH_LMS" unload local-main >/dev/null 2>&1 || true
    "$HEARTH_LMS" server stop >/dev/null 2>&1 || true
    i=0
    while [ "$i" -lt 30 ] && [ -n "$(listener || true)" ]; do
      sleep 1
      i=$((i + 1))
    done
    [ -z "$(listener || true)" ] || fail "port ${HEARTH_PORT} still busy after stopping LM Studio"
  fi

  echo "starting oMLX on 127.0.0.1:${HEARTH_PORT} (memory guard ${GUARD_GB} GB, hot cache ${HOT_CACHE}, SSD cache ${SSD_CACHE})"
  start_omlx

  code=000
  i=0
  while [ "$i" -lt 60 ]; do
    code="$(hearth_http /models || true)"
    [ "$code" = "401" ] && break
    sleep 1
    i=$((i + 1))
  done
  if [ "$code" != "401" ]; then
    echo "oMLX did not require a token (last status ${code}) — restoring LM Studio" >&2
    stop_omlx
    restore_lms
    exit 1
  fi
  code="$(hearth_http /models "$LMSTUDIO_HOST_TOKEN" || true)"
  if [ "$code" != "200" ]; then
    echo "host token was refused (${code}) — restoring LM Studio" >&2
    stop_omlx
    restore_lms
    exit 1
  fi

  if ! configure_model; then
    echo "model setup failed — restoring LM Studio" >&2
    tail -n 40 "$LOG" >&2 || true
    stop_omlx
    restore_lms
    exit 1
  fi
  echo "http://127.0.0.1:${HEARTH_PORT}/v1"
  echo "log: ${LOG}"
  echo "restore with: scripts/omlx-try.sh down"
}

cmd_down() {
  stop_omlx
  i=0
  while [ "$i" -lt 20 ]; do
    who="$(listener || true)"
    case "$who" in
      "" ) break ;;
      omlx|Python|python* ) sleep 1 ;;
      * ) break ;;
    esac
    i=$((i + 1))
  done
  restore_lms
}

cmd_status() {
  who="$(listener || true)"
  if [ -z "$who" ]; then
    echo "nothing listening on ${HEARTH_PORT}"
    exit 1
  fi
  echo "port ${HEARTH_PORT}: ${who}"
  if [ -f "$PIDFILE" ]; then
    pid="$(cat "$PIDFILE" 2>/dev/null || true)"
    if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
      echo "oMLX pid ${pid}"
    fi
  fi
}

cmd_bench() {
  omlx_running || fail "oMLX is not running"
  echo "thinking probe"
  TMPD="$(mktemp -d)"
  trap 'rm -rf "$TMPD"' EXIT
  body='{"model":"local-main","max_tokens":3000,"messages":[{"role":"user","content":"Pens are 3 for $2.10 and notebooks $1.35 each. 7 pens and 4 notebooks, paid with $20. Change? Amount only."}]}'
  code="$(printf 'header = "Authorization: Bearer %s"\n' "$LMSTUDIO_HOST_TOKEN" \
    | curl -s -m 300 -o "$TMPD/out" -w '%{http_code}' -K - \
        -H 'Content-Type: application/json' -d "$body" \
        "http://127.0.0.1:${HEARTH_PORT}/v1/chat/completions")"
  why="$(/usr/bin/python3 -I -c '
import json, sys
m = json.load(open(sys.argv[1]))["choices"][0]["message"]
c = m.get("content") or ""
if not (m.get("reasoning_content") or "").strip(): print("no reasoning_content")
elif any(t in c for t in ("<think>", "</think>", "<|channel>", "<channel|>")): print("thinking markers in the answer")
else: print("ok")
' "$TMPD/out" 2>/dev/null || echo "unreadable reply")"
  echo "thinking: ${code} ${why}"
  [ "$code" = "200" ] && [ "$why" = "ok" ] || fail "thinking probe failed"

  echo "tool smoke"
  "${ROOT}/scripts/tool-smoke.sh" "http://127.0.0.1:${HEARTH_PORT}/v1" local-main

  # The concurrency bench stamps a fresh session id at the front of every
  # prompt, so it never reuses a prefix. This sends one body twice.
  echo "two identical ~30k prompts (second turn is the cache)"
  ROOT="$ROOT" LMSTUDIO_HOST_TOKEN="$LMSTUDIO_HOST_TOKEN" \
  HEARTH_PORT="$HEARTH_PORT" /usr/bin/python3 -I - <<'PY'
import json, os, time, urllib.request
root = os.environ["ROOT"]
files = []
for sub in ("docs", "scripts", "docs/decisions", "bench/tasks"):
    d = os.path.join(root, sub)
    if not os.path.isdir(d):
        continue
    for n in sorted(os.listdir(d)):
        p = os.path.join(d, n)
        if os.path.isfile(p) and n.endswith((".md", ".sh", ".zsh", ".py")):
            files.append(p)
parts, total, i = [], 0, 0
target = int(30000 * 3.2)
while total < target and files:
    p = files[i % len(files)]
    with open(p, encoding="utf-8", errors="replace") as fh:
        chunk = "==> %s <==\n%s\n" % (os.path.relpath(p, root), fh.read())
    parts.append(chunk)
    total += len(chunk)
    i += 1
filler = "".join(parts)[:target]
body = json.dumps({
    "model": "local-main",
    "stream": True,
    "stream_options": {"include_usage": True},
    "temperature": 1.0,
    "max_tokens": 64,
    "messages": [
        {"role": "system", "content": "You are a coding assistant. Use the notes below.\n" + filler},
        {"role": "user", "content": "Reply with the single word ok."},
    ],
}).encode()
url = "http://127.0.0.1:%s/v1/chat/completions" % os.environ["HEARTH_PORT"]
key = os.environ["LMSTUDIO_HOST_TOKEN"]

def once(n):
    req = urllib.request.Request(url, data=body, method="POST")
    req.add_header("Authorization", "Bearer " + key)
    req.add_header("Content-Type", "application/json")
    t0 = time.monotonic()
    ttft = None
    prompt = None
    with urllib.request.urlopen(req, timeout=300) as resp:
        for line in resp:
            s = line.decode("utf-8", "replace").strip()
            if not s.startswith("data:"):
                continue
            data = s[5:].strip()
            if data == "[DONE]":
                break
            try:
                ev = json.loads(data)
            except ValueError:
                continue
            usage = ev.get("usage") or {}
            if usage.get("prompt_tokens"):
                prompt = usage.get("prompt_tokens")
            ch = ((ev.get("choices") or [{}])[0].get("delta") or {})
            if (ch.get("content") or ch.get("reasoning_content")) and ttft is None:
                ttft = time.monotonic() - t0
    print("turn %d ttft=%.3f prompt=%s" % (n, ttft if ttft is not None else -1, prompt))

once(1)
once(2)
PY
}

cmd_subkey() {
  action="${1:-}"
  name="${2:-}"
  case "$action" in
    list)
      [ -z "$name" ] || fail "sub-key list takes no name"
      ;;
    add|revoke)
      [ -n "$name" ] || fail "usage: $0 sub-key ${action} <name>"
      case "$name" in
        *[!A-Za-z0-9_-]*) fail "name must be letters, digits, hyphen, or underscore" ;;
        -*) fail "name must not start with a hyphen" ;;
      esac
      ;;
    *) fail "usage: $0 sub-key {list|add|revoke}" ;;
  esac
  omlx_running || fail "oMLX is not running"
  [ -n "${LMSTUDIO_HOST_TOKEN:-}" ] || fail "LMSTUDIO_HOST_TOKEN is not set"
  token=""
  if [ "$action" = "add" ]; then
    if [ -t 0 ]; then
      printf 'paste the token for %s (it will not echo): ' "$name" >&2
      IFS= read -rs token || fail "no token"
      printf '\n' >&2
    else
      IFS= read -r token || true
    fi
    token="${token%$'\r'}"
    [ -n "$token" ] || fail "empty token"
  fi
  OMLX_API_KEY="$LMSTUDIO_HOST_TOKEN" \
  OMLX_SUB_ACTION="$action" \
  OMLX_SUB_NAME="$name" \
  OMLX_SUB_KEY="$token" \
  OMLX_PORT="$HEARTH_PORT" \
  OMLX_SETTINGS="$SETTINGS" \
  /usr/bin/python3 -I - <<'PY'
import json, os, sys, urllib.error, urllib.request

def _quiet(etype, value, tb):
    if etype is not SystemExit:
        sys.stderr.write("omlx-try: %s\n" % etype.__name__)
sys.excepthook = _quiet

base = "http://127.0.0.1:%s" % os.environ["OMLX_PORT"]
host_key = os.environ["OMLX_API_KEY"]
action = os.environ["OMLX_SUB_ACTION"]
name = os.environ.get("OMLX_SUB_NAME", "")
sub = os.environ.get("OMLX_SUB_KEY", "")
settings_path = os.environ["OMLX_SETTINGS"]

def redact(text):
    if not isinstance(text, str):
        text = str(text)
    for secret in (host_key, sub):
        if secret and secret in text:
            text = text.replace(secret, "[redacted]")
    return text[:200]

def call(method, path, body=None, bearer=None, timeout=30):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(base + path, data=data, method=method)
    if body is not None:
        req.add_header("Content-Type", "application/json")
    if bearer:
        req.add_header("Authorization", "Bearer " + bearer)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode()
            return resp.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read().decode(errors="replace")
        try:
            parsed = json.loads(raw)
        except ValueError:
            parsed = {"detail": redact(raw)}
        return e.code, parsed
    except urllib.error.URLError:
        fail("no answer from the server")

def fail(msg):
    raise SystemExit("omlx-try: " + redact(msg))

def entries(body):
    auth = body.get("auth") if isinstance(body, dict) else None
    if not isinstance(auth, dict):
        return []
    out = []
    for sk in auth.get("sub_keys") or []:
        if isinstance(sk, dict) and isinstance(sk.get("key"), str):
            out.append(sk)
    return out

def lock_down():
    try:
        os.chmod(settings_path, 0o600)
    except OSError:
        pass

code, _ = call("GET", "/v1/models")
if code != 401:
    fail("a request with no token returned %s, expected 401" % code)

code, listing = call("GET", "/admin/api/global-settings", bearer=host_key, timeout=60)
if code != 200:
    fail("could not read sub-keys (%s)" % code)
current = entries(listing)

if action == "list":
    rows = sorted((sk.get("name") or "(unnamed)", sk.get("created_at") or "") for sk in current)
    if not rows:
        print("no sub-keys")
    else:
        for label, created in rows:
            print("%s\t%s" % (label, created))
    lock_down()
    raise SystemExit(0)

match = None
for sk in current:
    if sk.get("name") == name:
        match = sk
        break

if action == "revoke":
    if match is None:
        fail("no sub-key named %s" % name)
    code, body = call("DELETE", "/admin/api/sub-keys", {"key": match["key"]}, bearer=host_key)
    if code != 200:
        fail("revoke failed (%s): %s" % (code, redact(body.get("detail", ""))))
    code, listing = call("GET", "/admin/api/global-settings", bearer=host_key, timeout=60)
    if code != 200 or any(sk.get("name") == name for sk in entries(listing)):
        fail("sub-key %s is still present" % name)
    lock_down()
    print("revoked %s" % name)
    raise SystemExit(0)

if len(sub) < 4 or any(c.isspace() for c in sub) or not sub.isascii() or not sub.isprintable():
    fail("token must be at least 4 ASCII characters with no whitespace")
same = None
for sk in current:
    if sk.get("key") == sub:
        same = sk
        break
if match is not None and match.get("key") != sub:
    fail("sub-key %s already exists" % name)
if same is not None and same.get("name") != name:
    fail("this token is already registered as %s" % (same.get("name") or "(unnamed)"))

created = False
if match is None:
    code, body = call("POST", "/admin/api/sub-keys", {"key": sub, "name": name}, bearer=host_key)
    if code != 200:
        fail("add failed (%s): %s" % (code, redact(body.get("detail", ""))))
    created = True

def rollback():
    if not created:
        return
    call("DELETE", "/admin/api/sub-keys", {"key": sub}, bearer=host_key)

code, _ = call("GET", "/v1/models", bearer=sub)
if code != 200:
    rollback()
    fail("token was refused by /v1/models (%s)" % code)
code, _ = call("POST", "/admin/api/login", {"api_key": sub})
if code == 200:
    rollback()
    fail("this token was accepted as admin")
if code != 401:
    rollback()
    fail("admin login returned %s, expected 401" % code)
code, _ = call("GET", "/admin/api/global-settings", bearer=sub, timeout=60)
if code == 200:
    rollback()
    fail("this token can read admin settings")
if code != 401:
    rollback()
    fail("admin settings returned %s, expected 401" % code)
code, _ = call("GET", "/v1/models")
if code != 401:
    rollback()
    fail("a request with no token returned %s, expected 401" % code)
lock_down()
print("registered %s" % name)
print("no token: 401")
print("this token: 200")
print("admin login: 401")
PY
}

case "$CMD" in
  up) cmd_up ;;
  down) cmd_down ;;
  status) cmd_status ;;
  bench) cmd_bench ;;
  sub-key) cmd_subkey "${2:-}" "${3:-}" ;;
  *) echo "usage: $0 {up|down|status|bench|sub-key}" >&2; exit 1 ;;
esac
