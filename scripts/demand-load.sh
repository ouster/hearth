#!/bin/bash
# Load or unload a role marked load=beside or load=swap in config/roles.tsv
# (ADR 0020, 0031, 0032, 0047, 0048).
#
#   scripts/demand-load.sh <role> up            # load (swap roles always evict)
#   scripts/demand-load.sh <role> up --evict    # unload the resident first
#   scripts/demand-load.sh <role> down          # unload; restore prior agent
#
# main-brain is resident on every tier (ADR 0048). On 64 GB, coding-brain and
# deep-brain are swap. coding-brain never shares RAM with main-brain or
# deep-brain (ADR 0047). A swap agent's down restores the resident.
# ask-deep records the prior agent under ~/.omlx/hearth-prior-agent and
# restores it on down (slot count follows that agent).
#
# Exit 0 ok, 1 refused or failed, 2 could not run.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"

ROLE="${1:-}"; ACTION="${2:-}"; EVICT=0
[ "${3:-}" = "--evict" ] && EVICT=1
[ -n "$ROLE" ] && { [ "$ACTION" = up ] || [ "$ACTION" = down ]; } || { sed -n '2,8p' "$0"; exit 2; }
hearth_demand_roles | grep -qxF "$ROLE" || { echo "could not run: ${ROLE} is not a beside or swap role for this host in roles.tsv" >&2; exit 2; }
LOAD="$(hearth_role_load "$ROLE")"
if [ "$ACTION" = up ] && [ "$EVICT" = 0 ] && [ "$LOAD" = swap ]; then
  EVICT=1
  echo "${ROLE} is load=swap on this $(hearth_ram_gb || echo ?) GB host: unloading the other agent first." >&2
fi
holder="$(lsof -nP -iTCP:"${HEARTH_PORT}" -sTCP:LISTEN 2>/dev/null | awk 'NR==2 {print $1}')"
case "$holder" in
  Python|python*|omlx)
    ai_load_env
    [ -n "${OMLX_HOST_TOKEN:-}" ] || { echo "could not run: host token missing" >&2; exit 2; }
    export OMLX_HOST_TOKEN
    HEARTH_ROLE="$ROLE" HEARTH_ACTION="$ACTION" HEARTH_EVICT="$EVICT" \
      HEARTH_PORT="$HEARTH_PORT" HEARTH_ROLES_TSV="$(hearth_resolved_roles)" \
      HEARTH_OMLX_HOME="${HOME}/.omlx" \
      /usr/bin/python3 -I - <<'PY'
import json, os, sys, time, urllib.error, urllib.request, http.cookiejar
base = "http://127.0.0.1:%s" % os.environ["HEARTH_PORT"]
key = os.environ["OMLX_HOST_TOKEN"]
role = os.environ["HEARTH_ROLE"]
action = os.environ["HEARTH_ACTION"]
evict = os.environ["HEARTH_EVICT"] == "1"
omlx_home = os.environ["HEARTH_OMLX_HOME"]
prior_path = os.path.join(omlx_home, "hearth-prior-agent")
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

role_to_leaf = {}
role_slots = {}
role_load = {}
residents = []
agents = []  # coding-brain / main-brain style chat agents (not deep, not edit)
for line in os.environ["HEARTH_ROLES_TSV"].splitlines():
    f = line.split("\t")
    if len(f) < 8 or f[1] != "omlx" or f[5] in ("", "-"):
        continue
    leaf = f[5].rstrip("/").split("/")[-1]
    role_to_leaf[f[0]] = leaf
    try:
        role_slots[f[0]] = int(f[4])
    except ValueError:
        role_slots[f[0]] = 1
    role_load[f[0]] = f[7]
    if f[7] == "resident":
        residents.append(f[0])
    if f[0] in ("main-brain", "coding-brain") or (
        f[7] in ("resident", "swap", "beside") and f[0] != "deep-brain" and "edit" not in f[0]
    ):
        if f[0] not in agents and f[0] != "deep-brain":
            agents.append(f[0])

# Prefer explicit agent names when present.
agents = [r for r in ("coding-brain", "main-brain") if r in role_to_leaf]
if not agents:
    agents = [r for r in residents if r in role_to_leaf]

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

def set_slots(n):
    code, body = call("POST", "/admin/api/global-settings", {
        "max_concurrent_requests": int(n),
    }, timeout=60)
    if code != 200:
        sys.stderr.write("warn: could not set max_concurrent_requests to %s (%s)\n" % (n, code))

def write_prior(name):
    try:
        os.makedirs(omlx_home, mode=0o700, exist_ok=True)
        with open(prior_path, "w") as fh:
            fh.write(name + "\n")
        os.chmod(prior_path, 0o600)
    except OSError as e:
        raise SystemExit("could not write prior agent file: %s" % e)

def read_prior():
    try:
        with open(prior_path) as fh:
            name = fh.read().strip()
        return name or None
    except OSError:
        return None

def clear_prior():
    try:
        os.remove(prior_path)
    except OSError:
        pass

def current_agent():
    """Which agent leaf is loaded, if any."""
    models = listing()
    for name in agents:
        mid = role_to_leaf.get(name)
        if mid and models.get(mid, {}).get("loaded"):
            return name
    return None

def unload_all_agents_and_deep():
    for name in agents:
        mid = role_to_leaf.get(name)
        if mid:
            unload(mid)
    deep_leaf = role_to_leaf.get("deep-brain")
    if deep_leaf:
        unload(deep_leaf)

if leaf not in listing():
    raise SystemExit(
        "could not run: %s (leaf %s) is not discovered. Copy its weights under "
        "~/.hearth/models and run scripts/omlx.sh up after a restart." % (role, leaf)
    )

default_resident = residents[0] if residents else None

if action == "down":
    unload(leaf)
    if role == "deep-brain":
        prior = read_prior()
        clear_prior()
        restore = prior if prior in role_to_leaf else default_resident
        if not restore:
            raise SystemExit("no agent to restore after deep-brain down")
        # Unload other agents, load restore
        for name in agents:
            if name != restore:
                mid = role_to_leaf.get(name)
                if mid:
                    unload(mid)
        load(role_to_leaf[restore])
        set_slots(role_slots.get(restore, 1))
        print("restored %s" % restore)
    else:
        # Swap agent down → default resident
        restore = default_resident
        if restore and restore != role:
            for name in agents:
                if name != restore:
                    mid = role_to_leaf.get(name)
                    if mid:
                        unload(mid)
            deep_leaf = role_to_leaf.get("deep-brain")
            if deep_leaf:
                unload(deep_leaf)
            load(role_to_leaf[restore])
            set_slots(role_slots.get(restore, 1))
            print("restored %s" % restore)
    raise SystemExit(0)

if loaded(leaf):
    print("already")
    raise SystemExit(0)

if role == "deep-brain":
    prior = current_agent()
    if prior:
        write_prior(prior)
    elif default_resident:
        write_prior(default_resident)
    # Unload all agents before deep
    for name in agents:
        mid = role_to_leaf.get(name)
        if mid:
            unload(mid)
    load(leaf)
    set_slots(role_slots.get(role, 1))
    print("loaded")
    raise SystemExit(0)

# main-brain (or other swap agent) up
if evict:
    sys.stderr.write(
        "unloading other agent roles for this session "
        "(default resident returns on demand-load %s down)…\n" % role
    )
    unload_all_agents_and_deep()
load(leaf)
set_slots(role_slots.get(role, 1))
print("loaded")
PY
    exit $?
    ;;
  *)
    echo "could not run: oMLX is not listening on :${HEARTH_PORT} (scripts/omlx.sh up)" >&2
    exit 2 ;;
esac
