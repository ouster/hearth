#!/bin/bash
# Serve local roles from oMLX on 127.0.0.1:1234 (ADR 0026, 0028). Login boot
# runs `up`. Weights are the copies under ~/.hearth/models. `down` stops oMLX
# and leaves the port empty.
#
#   scripts/omlx.sh up | down | status | bench
#   scripts/omlx.sh sub-key list
#   scripts/omlx.sh sub-key add <name>      # token on stdin, not echoed
#   scripts/omlx.sh sub-key revoke <name>
#
# Weights, context, and slots come from the resident local-main row. The API
# key is the existing host token, written to ~/.omlx/settings.json (mode 600)
# and never printed. Clients that already send that token keep working.
# A laptop token is a different key. `sub-key add` registers one the operator
# pastes; it can call the model and cannot log in as admin. `up` keeps
# sub-keys already in the settings file.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"
ai_load_env

OMLX_HOME="${OMLX_HOME:-$HOME/.omlx}"
MODEL_DIR="${OMLX_HOME}/models"
PIDFILE="${OMLX_HOME}/hearth.pid"
LOG="${HOME}/Library/Logs/hearth-omlx.log"
LABEL="com.hearth.omlx"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
SETTINGS="${OMLX_HOME}/settings.json"
# Guard and hot cache follow installed RAM (ADR 0031): 56 GB / 8 GB on a
# 64 GB host, 40 GB / 4 GB on 48 GB. The SSD cache is disk, not RAM.
GUARD_GB="$(hearth_gpu_ceiling_gb)" || { echo "omlx: cannot read hw.memsize" >&2; exit 2; }
if [ "$(hearth_ram_gb)" -ge 64 ]; then HOT_CACHE="8GB"; else HOT_CACHE="4GB"; fi
SSD_CACHE="20GB"
CMD="${1:-status}"

fail() { echo "omlx: $*" >&2; exit 1; }

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
  awk -F'\t' '!/^[[:space:]]*(#|$)/ && $1=="local-main" && $2=="omlx" && $8=="resident" {
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

write_settings() {
  [ -n "${OMLX_HOST_TOKEN:-}" ] || fail "OMLX_HOST_TOKEN is not set"
  mkdir -p "$OMLX_HOME" "$MODEL_DIR" "${OMLX_HOME}/cache" "$(dirname "$LOG")"
  chmod 700 "$OMLX_HOME" "${OMLX_HOME}/cache" 2>/dev/null || true
  OMLX_API_KEY="$OMLX_HOST_TOKEN" \
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

link_one() {
  role="$1"
  src="${HOME}/.hearth/models/${2}"
  dest="${MODEL_DIR}/${role}"
  [ -d "$src" ] || return 1
  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    fail "${dest} exists and is not a symlink"
  fi
  ln -sfn "$src" "$dest"
}

link_weights() {
  mkdir -p "$MODEL_DIR"
  link_one local-main "$WEIGHTS" || fail "weights missing: ${HOME}/.hearth/models/${WEIGHTS}"
  deep=$(awk -F'\t' '!/^[[:space:]]*(#|$)/ && $1=="local-deep" && $8=="demand" { print $6; exit }' "${ROOT}/config/roles.tsv")
  if [ -n "$deep" ]; then
    link_one local-deep "$deep" || echo "omlx: local-deep weights not under ~/.hearth/models — ask-deep cannot load it until the weights are copied" >&2
  fi
}

configure_model() {
  OMLX_API_KEY="$OMLX_HOST_TOKEN" \
  OMLX_PORT="$HEARTH_PORT" \
  OMLX_CTX="$CTX" \
  OMLX_ROLES="${ROOT}/config/roles.tsv" \
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

roles = {}
with open(os.environ["OMLX_ROLES"]) as fh:
    for line in fh:
        if not line.strip() or line.startswith("#"):
            continue
        f = line.rstrip("\n").split("\t")
        if len(f) < 8 or f[1] != "omlx" or f[5] in ("", "-"):
            continue
        roles[f[0]] = {"ctx": int(f[3]), "load": f[7]}

code, listing = call("GET", "/v1/models")
if code != 200:
    raise SystemExit("/v1/models failed (%s)" % code)
ids = [m.get("id") for m in listing.get("data") or [] if m.get("id")]
if "local-main" not in ids:
    raise SystemExit("local-main was not discovered")

def apply(mid, settings):
    code, body = call("PUT", "/admin/api/models/%s/settings" % mid, settings)
    if code != 200:
        raise SystemExit("model settings failed for %s (%s): %s" % (mid, code, str(body.get("detail", ""))[:300]))

common = {
    "enable_thinking": True,
    "chat_template_kwargs": {"enable_thinking": True},
    "temperature": 1.0,
    "top_p": 0.95,
    "top_k": 64,
    "repetition_penalty": 1.0,
}
main = dict(common)
main.update({
    "reasoning_parser": "qwen",
    "top_k": 20,
    "max_context_window": ctx,
    "max_tokens": 65536,
    "is_pinned": True,
    "is_default": True,
})
apply("local-main", main)
if "local-deep" in ids and "local-deep" in roles:
    deep = dict(common)
    deep.update({
        "max_context_window": roles["local-deep"]["ctx"],
        "max_tokens": 32768,
        "is_pinned": False,
        "is_default": False,
    })
    apply("local-deep", deep)

code, body = call("POST", "/admin/api/models/local-main/load", None, timeout=600)
detail = str(body.get("detail", ""))
if code not in (200, 409):
    raise SystemExit("load failed (%s): %s" % (code, detail[:300]))
if code == 409 and "already loading" not in detail and "already loaded" not in detail and "Already loaded" not in detail:
    raise SystemExit("load failed (%s): %s" % (code, detail[:300]))

deadline = time.time() + 300
loaded = False
while time.time() < deadline:
    code, body = call("GET", "/admin/api/models")
    if code == 200:
        for m in body.get("models") or []:
            if m.get("id") == "local-main" and m.get("loaded"):
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
    * ) fail "port ${HEARTH_PORT} is held by ${who}. Stop that process, then re-run." ;;
  esac

  write_settings
  link_weights

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
    echo "oMLX did not require a token (last status ${code})" >&2
    stop_omlx
    exit 1
  fi
  code="$(hearth_http /models "$OMLX_HOST_TOKEN" || true)"
  if [ "$code" != "200" ]; then
    echo "host token was refused (${code})" >&2
    stop_omlx
    exit 1
  fi

  if ! configure_model; then
    echo "model setup failed" >&2
    tail -n 40 "$LOG" >&2 || true
    stop_omlx
    exit 1
  fi
  echo "http://127.0.0.1:${HEARTH_PORT}/v1"
  echo "log: ${LOG}"
  echo "stop with: scripts/omlx.sh down"
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
  echo "oMLX stopped; nothing is listening on ${HEARTH_PORT}"
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
  code="$(printf 'header = "Authorization: Bearer %s"\n' "$OMLX_HOST_TOKEN" \
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
  ROOT="$ROOT" OMLX_HOST_TOKEN="$OMLX_HOST_TOKEN" \
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
key = os.environ["OMLX_HOST_TOKEN"]

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
  [ -n "${OMLX_HOST_TOKEN:-}" ] || fail "OMLX_HOST_TOKEN is not set"
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
  OMLX_API_KEY="$OMLX_HOST_TOKEN" \
  OMLX_SUB_ACTION="$action" \
  OMLX_SUB_NAME="$name" \
  OMLX_SUB_KEY="$token" \
  OMLX_PORT="$HEARTH_PORT" \
  OMLX_SETTINGS="$SETTINGS" \
  /usr/bin/python3 -I - <<'PY'
import json, os, sys, urllib.error, urllib.request

def _quiet(etype, value, tb):
    if etype is not SystemExit:
        sys.stderr.write("omlx: %s\n" % etype.__name__)
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
    raise SystemExit("omlx: " + redact(msg))

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
