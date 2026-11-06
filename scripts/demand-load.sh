#!/bin/bash
# Load or unload a role marked load=demand in config/roles.tsv (ADR 0020).
#
#   scripts/demand-load.sh <role> up            # load beside the resident role
#   scripts/demand-load.sh <role> up --evict    # unload the resident role first
#   scripts/demand-load.sh <role> down          # unload it; the resident stays, or comes back
#
# `up` prints "loaded" or "already". An unloaded name can be answered by
# whatever is loaded, so `up` confirms this role is really loaded before it
# returns 0.
#
# On a 64 GB host both roles may be loaded together (ADR 0028): `up` does
# not unload the resident, and `--evict` still does, for a run that needs the
# machine to itself. Below a 56 GB GPU ceiling `up` always evicts (ADR 0031).
# `down` unloads this role. If the resident was evicted, `down` loads it again.
#
# Exit 0 ok, 1 refused or failed, 2 could not run.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"

ROLE="${1:-}"; ACTION="${2:-}"; EVICT=0
[ "${3:-}" = "--evict" ] && EVICT=1
[ -n "$ROLE" ] && { [ "$ACTION" = up ] || [ "$ACTION" = down ]; } || { sed -n '2,6p' "$0"; exit 2; }
hearth_demand_roles | grep -qxF "$ROLE" || { echo "could not run: ${ROLE} is not a load=demand role in roles.tsv" >&2; exit 2; }
# Below a 56 GB ceiling (a 48 GB Mac) the pair does not fit: `up` always
# evicts the resident, and `down` brings it back (ADR 0031).
if [ "$ACTION" = up ] && [ "$EVICT" = 0 ] && ! hearth_coload_ok; then
  EVICT=1
  echo "GPU ceiling $(hearth_gpu_ceiling_gb || echo ?) GB is under ${HEARTH_COLOAD_MIN_GB} GB: ${ROLE} cannot load beside the resident, evicting it." >&2
fi
holder="$(lsof -nP -iTCP:"${HEARTH_PORT}" -sTCP:LISTEN 2>/dev/null | awk 'NR==2 {print $1}')"
case "$holder" in
  Python|python*|omlx)
    ai_load_env
    [ -n "${OMLX_HOST_TOKEN:-}" ] || { echo "could not run: host token missing" >&2; exit 2; }
    export OMLX_HOST_TOKEN
    HEARTH_ROLE="$ROLE" HEARTH_ACTION="$ACTION" HEARTH_EVICT="$EVICT" \
      HEARTH_PORT="$HEARTH_PORT" HEARTH_ROLES="${ROOT}/config/roles.tsv" \
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

residents = []
with open(os.environ["HEARTH_ROLES"]) as fh:
    for line in fh:
        if not line.strip() or line.startswith("#"):
            continue
        f = line.rstrip("\n").split("\t")
        if len(f) >= 8 and f[1] == "omlx" and f[7] == "resident":
            residents.append(f[0])

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

if role not in listing():
    raise SystemExit("could not run: %s is not discovered. Copy its weights under ~/.hearth/models and run scripts/omlx.sh up after a restart." % role)

if action == "down":
    unload(role)
    for mid in residents:
        load(mid)
    raise SystemExit(0)

if loaded(role):
    print("already")
    raise SystemExit(0)
if evict:
    sys.stderr.write("unloading resident roles for this session (Zed, aider and laptops have no local-main until down)…\n")
    for mid in residents:
        unload(mid)
load(role)
print("loaded")
PY
    exit $?
    ;;
  *)
    echo "could not run: oMLX is not listening on :${HEARTH_PORT} (scripts/omlx.sh up)" >&2
    exit 2 ;;
esac
