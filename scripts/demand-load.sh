#!/bin/bash
# Load or unload a role marked load=demand in config/roles.tsv (ADR 0020).
#
#   scripts/demand-load.sh <role> up            # load beside the resident roles, if it fits
#   scripts/demand-load.sh <role> up --evict    # unload the resident roles first
#   scripts/demand-load.sh <role> down          # unload it; reload resident roles
#
# `up` prints "loaded" or "already". With JIT off, LM Studio answers a
# request for an unloaded role with whatever IS loaded, so `up` confirms the
# role is really loaded before it returns 0.
#
# On oMLX (ADR 0027) --evict unloads the resident role, loads this one, and
# `down` reverses it. Without --evict, `up` refuses: beside local-main a long
# prompt starved the resident (ADR 0020), and a higher GPU cap does not change that.
#
# The LM Studio path is the rollback. Its memory guard is the 2026-11-01
# measurement: beside local-main, a ~30K-token prompt grew this role's cache
# by ~8 GB while local-main's own three slots grew by ~8.4 GB, peaking at
# 49.9 GB. Without --evict, `up` refuses when the footprint now + the weights
# + HEARTH_DEMAND_KV_GB (8) + HEARTH_RESIDENT_GROWTH_GB (9) would pass 44 GB.
# With --evict only the first three count.
#
# Exit 0 ok, 1 refused or failed, 2 could not run.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"

ROLE="${1:-}"; ACTION="${2:-}"; EVICT=0
[ "${3:-}" = "--evict" ] && EVICT=1
LIMIT_GB=44
KV_GB="${HEARTH_DEMAND_KV_GB:-8}"
GROWTH_GB="${HEARTH_RESIDENT_GROWTH_GB:-9}"
[ -n "$ROLE" ] && { [ "$ACTION" = up ] || [ "$ACTION" = down ]; } || { sed -n '2,6p' "$0"; exit 2; }
hearth_demand_roles | grep -qxF "$ROLE" || { echo "could not run: ${ROLE} is not a load=demand role in roles.tsv" >&2; exit 2; }
holder="$(lsof -nP -iTCP:"${HEARTH_PORT}" -sTCP:LISTEN 2>/dev/null | awk 'NR==2 {print $1}')"
case "$holder" in
  Python|python*|omlx)
    ai_load_env
    [ -n "${LMSTUDIO_HOST_TOKEN:-}" ] || { echo "could not run: host token missing" >&2; exit 2; }
    export LMSTUDIO_HOST_TOKEN
    HEARTH_ROLE="$ROLE" HEARTH_ACTION="$ACTION" HEARTH_EVICT="$EVICT" \
      HEARTH_PORT="$HEARTH_PORT" HEARTH_ROLES="${ROOT}/config/roles.tsv" \
      /usr/bin/python3 -I - <<'PY'
import json, os, time, urllib.error, urllib.request, http.cookiejar
base = "http://127.0.0.1:%s" % os.environ["HEARTH_PORT"]
key = os.environ["LMSTUDIO_HOST_TOKEN"]
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
        if len(f) >= 8 and f[1] == "lmstudio" and f[7] == "resident":
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
    raise SystemExit("could not run: %s is not discovered. Copy its weights under ~/.hearth/models and run scripts/omlx-try.sh up after a restart." % role)

if action == "down":
    unload(role)
    for mid in residents:
        load(mid)
    raise SystemExit(0)

if loaded(role):
    print("already")
    raise SystemExit(0)
if not evict:
    raise SystemExit("not loading %s beside the resident role. Use --evict (ask-deep always does)." % role)
import sys
sys.stderr.write("unloading resident roles for this session (Zed, aider and laptops have no local-main until down)…\n")
for mid in residents:
    unload(mid)
load(role)
print("loaded")
PY
    exit $?
    ;;
esac
hearth_lms_ok || { echo "could not run: LM Studio not running (scripts/omlx-try.sh down)" >&2; exit 2; }

is_loaded() {
  "$HEARTH_LMS" ps --json 2>/dev/null | /usr/bin/python3 -I -c '
import json, sys
sys.exit(0 if any(m.get("identifier") == sys.argv[1] and m.get("modelKey") == sys.argv[2]
                  for m in json.load(sys.stdin)) else 1)' "$ROLE" "$1"
}

if [ "$ACTION" = down ]; then
  "$HEARTH_LMS" unload "$ROLE" >/dev/null 2>&1 || { echo "unload ${ROLE} failed" >&2; exit 1; }
  # Brings local-main back after --evict; a no-op when it never left.
  "${ROOT}/scripts/lms-load.sh" >/dev/null 2>&1 || { echo "lms-load.sh failed — run it by hand" >&2; exit 1; }
  exit 0
fi

row=$(awk -F'\t' -v r="$ROLE" '!/^[[:space:]]*#/ && $1 == r' "${ROOT}/config/roles.tsv")
key=$(printf '%s' "$row" | cut -f3); ctx=$(printf '%s' "$row" | cut -f4); slots=$(printf '%s' "$row" | cut -f5)

if is_loaded "$key"; then echo "already"; exit 0; fi

size=$("$HEARTH_LMS" ls --json 2>/dev/null | /usr/bin/python3 -I -c '
import json, sys
print(next(("%.1f" % (m["sizeBytes"] / 1e9) for m in json.load(sys.stdin) if m.get("modelKey") == sys.argv[1]), ""))' "$key")
[ -n "$size" ] || { echo "could not run: ${key} not downloaded" >&2; exit 2; }

if [ "$EVICT" -eq 1 ]; then
  echo "unloading resident roles for this session (Zed, aider and laptops have no local-main until down)…" >&2
  for r in $(hearth_resident_roles | cut -f1); do "$HEARTH_LMS" unload "$r" >/dev/null 2>&1; done
  GROWTH_GB=0
fi

used=$(hearth_footprint_gb)
if awk -v u="$used" -v s="$size" -v k="$KV_GB" -v g="$GROWTH_GB" -v l="$LIMIT_GB" 'BEGIN {exit !(u + s + k + g > l)}'; then
  echo "not loading ${ROLE}: LM Studio uses ${used} GB; + ${size} GB weights + ${KV_GB} GB cache + ${GROWTH_GB} GB for local-main under load would pass ${LIMIT_GB} GB (~48 GB ceiling, 4 GB headroom)." >&2
  echo "Use --evict to unload local-main for the session (ask-deep always does)." >&2
  exit 1
fi

echo "loading ${ROLE} (${size} GB; LM Studio at ${used} GB)…" >&2
"$HEARTH_LMS" load "$key" --identifier "$ROLE" -c "$ctx" --parallel "$slots" --gpu max -y </dev/null >/dev/null 2>&1
if ! is_loaded "$key"; then
  echo "load ${ROLE} failed — not in lms ps" >&2
  [ "$EVICT" -eq 1 ] && "${ROOT}/scripts/lms-load.sh" >/dev/null 2>&1
  exit 1
fi
echo "loaded"
