#!/bin/bash
# Load or unload a role marked load=beside or load=swap in config/roles.tsv (ADR 0020, 0032).
#
#   scripts/demand-load.sh <role> up            # load beside the resident role
#   scripts/demand-load.sh <role> up --evict    # unload the resident role first
#   scripts/demand-load.sh <role> down          # unload it; the resident stays, or comes back
#
# `up` prints "loaded" or "already". An unloaded name can be answered by
# whatever is loaded, so `up` confirms this role is really loaded before it
# returns 0.
#
# load=beside (ADR 0028): `up` loads next to the resident, and `--evict`
# still unloads it, for a run that needs the machine to itself. load=swap
# (ADR 0031): `up` always evicts. The load comes from this host's tier in
# config/roles.tsv (ADR 0032).
# `down` unloads this role. If the resident was evicted, `down` loads it again.
#
# Exit 0 ok, 1 refused or failed, 2 could not run.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"

ROLE="${1:-}"; ACTION="${2:-}"; EVICT=0
[ "${3:-}" = "--evict" ] && EVICT=1
[ -n "$ROLE" ] && { [ "$ACTION" = up ] || [ "$ACTION" = down ]; } || { sed -n '2,6p' "$0"; exit 2; }
hearth_demand_roles | grep -qxF "$ROLE" || { echo "could not run: ${ROLE} is not a beside or swap role for this host in roles.tsv" >&2; exit 2; }
# A swap row (this host's tier, ADR 0031, 0032) always evicts the resident;
# `down` brings it back.
LOAD="$(hearth_role_load "$ROLE")"
if [ "$ACTION" = up ] && [ "$EVICT" = 0 ] && [ "$LOAD" = swap ]; then
  EVICT=1
  echo "${ROLE} is load=swap on this $(hearth_ram_gb || echo ?) GB host: unloading the resident first." >&2
fi
holder="$(lsof -nP -iTCP:"${HEARTH_PORT}" -sTCP:LISTEN 2>/dev/null | awk 'NR==2 {print $1}')"
case "$holder" in
  Python|python*|omlx)
    ai_load_env
    [ -n "${OMLX_HOST_TOKEN:-}" ] || { echo "could not run: host token missing" >&2; exit 2; }
    export OMLX_HOST_TOKEN
    HEARTH_ROLE="$ROLE" HEARTH_ACTION="$ACTION" HEARTH_EVICT="$EVICT" \
      HEARTH_PORT="$HEARTH_PORT" HEARTH_ROLES_TSV="$(hearth_resolved_roles)" \
      /usr/bin/python3 -I - <<'PY'
import json, os, sys, time, urllib.error, urllib.request, http.cookiejar
base = "http://127.0.0.1:%s" % os.environ["HEARTH_PORT"]
key = os.environ["OMLX_HOST_TOKEN"]
role = os.environ["HEARTH_ROLE"]
action = os.environ["HEARTH_ACTION"]
evict = os.environ["HEARTH_EVICT"] == "1"
jar = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))

def call(method, path, body=None, timeout=30):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(base + path, data=data, method=method)
    req.add_header("Content-Type", "application/json")
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

# Admin APIs use the discovery leaf (org/leaf basename). Clients use the
# role via model_alias (ADR 0034).
role_to_leaf = {}
residents = []
for line in os.environ["HEARTH_ROLES_TSV"].splitlines():
    f = line.split("\t")
    if len(f) < 8 or f[1] != "omlx" or f[5] in ("", "-"):
        continue
    leaf = f[5].rstrip("/").split("/")[-1]
    role_to_leaf[f[0]] = leaf
    if f[7] == "resident":
        residents.append(leaf)

leaf = role_to_leaf.get(role)
if not leaf:
    raise SystemExit("could not run: %s has no weights path in roles.tsv" % role)

def listing():
    code, body = call("GET", "/admin/api/models")
    if code != 200:
        raise SystemExit("admin models failed (%s)" % code)
    return {m.get("id"): m for m in body.get("models") or []}

def loaded(mid):
    return bool((listing().get(mid) or {}).get("loaded"))

def wait_until(mid, want, seconds):
    deadline = time.time() + seconds
    while time.time() < deadline:
        if loaded(mid) == want:
            return True
        time.sleep(2)
    return False

def unload(mid):
    if mid not in listing() or not loaded(mid):
        return
    code, body = call("POST", "/admin/api/models/%s/unload" % mid, None, timeout=120)
    detail = str(body.get("detail", ""))
    if code not in (200, 202, 400):
        raise SystemExit("unload %s failed (%s): %s" % (mid, code, detail[:200]))
    if not wait_until(mid, False, 180):
        raise SystemExit("unload %s did not finish" % mid)

def load(mid):
    code, body = call("POST", "/admin/api/models/%s/load" % mid, None, timeout=600)
    detail = str(body.get("detail") or body.get("message") or "")
    if code == 200 or (code == 409 and ("already loading" in detail or "already loaded" in detail or "Already loaded" in detail)):
        pass
    else:
        raise SystemExit("load %s failed (%s): %s" % (mid, code, detail[:300]))
    if not wait_until(mid, True, 300):
        raise SystemExit("%s did not report loaded" % mid)

if leaf not in listing():
    raise SystemExit(
        "could not run: %s (leaf %s) is not discovered. Copy its weights under "
        "~/.hearth/models and run scripts/omlx.sh up after a restart." % (role, leaf)
    )

if action == "down":
    unload(leaf)
    for mid in residents:
        load(mid)
    raise SystemExit(0)

if loaded(leaf):
    print("already")
    raise SystemExit(0)
if evict:
    sys.stderr.write("unloading resident roles for this session (Zed, aider and laptops have no local-main until down)…\n")
    for mid in residents:
        unload(mid)
load(leaf)
print("loaded")
PY
    exit $?
    ;;
  *)
    echo "could not run: oMLX is not listening on :${HEARTH_PORT} (scripts/omlx.sh up)" >&2
    exit 2 ;;
esac
