#!/bin/bash
# What actually happened: which role, which model behind it, local or cloud,
# how many tokens, what it cost.
#
#   scripts/usage.sh            last 25 requests
#   scripts/usage.sh 100        last 100
#   scripts/usage.sh --summary  totals by role and by tier
#   scripts/usage.sh --keys     per-key spend against its cap
#
# The role -> model mapping and the local/cloud classification come from
# litellm/config.yaml, so this stays correct across model swaps without edits.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"
ai_python_or_die || exit 2
ai_load_env "$ROOT"

GATEWAY="${GATEWAY:-http://127.0.0.1:4000}"
KEY="${LITELLM_MASTER_KEY:?LITELLM_MASTER_KEY not found}"
CFG="${ROOT}/litellm/config.yaml"

MODE="recent"; N=25
case "${1:-}" in
  --summary) MODE="summary" ;;
  --keys)    MODE="keys" ;;
  ''|*[!0-9]*) : ;;
  *) N="$1" ;;
esac

if [ "$MODE" = "keys" ]; then
  # Temp file, not a pipe — a heredoc script and piped stdin cannot coexist.
  KTMP="$(mktemp)"; trap 'rm -f "$KTMP"' EXIT
  curl -s -m 15 -H "Authorization: Bearer ${KEY}" \
    "${GATEWAY}/key/list?return_full_object=true" > "$KTMP"
  "$AI_PY" - "$KTMP" <<'PY'
import sys, json
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print("could not read /key/list")
    raise SystemExit
keys = d.get("keys", d) if isinstance(d, dict) else d
hdr = "alias"
print(f"{hdr:<10} {'spent':>10} {'cap':>10}  scope")
print("-" * 62)
for k in keys or []:
    if not isinstance(k, dict):
        continue
    alias  = k.get("key_alias") or "(none)"
    spend  = k.get("spend") or 0
    cap    = k.get("max_budget")
    models = k.get("models") or []
    captxt = "none" if cap is None else str(cap)
    scope  = "LOCAL ONLY" if models and not any(m.startswith("cloud") for m in models) else "has cloud"
    print(f"{alias:<10} {spend:>10.4f} {captxt:>10}  {scope} ({len(models)} roles)")
print()
print("LOCAL ONLY on `private` is the privacy boundary — if that ever reads")
print("'has cloud', something has widened it and the leak test will fail.")
PY
  exit 0
fi

# Temp file, not a pipe. `curl | python - args <<'PY'` is broken: the heredoc
# supplies the program on stdin, so sys.stdin is exhausted before json.load
# sees the response. The symptom is a bogus "response was not JSON".
LTMP="$(mktemp)"; trap 'rm -f "$LTMP"' EXIT
curl -s -m 20 -H "Authorization: Bearer ${KEY}" "${GATEWAY}/spend/logs" > "$LTMP"

"$AI_PY" - "$CFG" "$MODE" "$N" "$LTMP" <<'PY'
import sys, json, yaml
from collections import defaultdict

cfg_path, mode, n, logs_path = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]

# role -> concrete model, and whether that role is local or cloud.
role_model, role_tier = {}, {}
cfg = yaml.safe_load(open(cfg_path)) or {}
for m in cfg.get("model_list", []):
    name = m["model_name"]
    target = m["litellm_params"]["model"]
    role_model[name] = target
    role_tier[name] = "LOCAL" if target.startswith(("ollama/", "ollama_chat/")) else "CLOUD"

raw = open(logs_path).read()
try:
    data = json.loads(raw)
except Exception:
    print("Could not parse /spend/logs. The gateway returned:")
    print("  " + (raw[:400] if raw.strip() else "<empty response>"))
    print()
    print("If that is an auth error, LITELLM_MASTER_KEY is wrong.")
    print("If it is empty, no requests have been logged yet.")
    raise SystemExit(1)

# An error response is valid JSON, so it would otherwise render as an empty
# table — "no usage" and "your key was rejected" must not look identical.
if isinstance(data, dict) and "error" in data:
    err = data["error"]
    msg = err.get("message", err) if isinstance(err, dict) else err
    print("The gateway returned an error, not usage data:")
    print(f"  {msg}")
    print()
    print("A 401/403 here means LITELLM_MASTER_KEY is wrong or expired.")
    raise SystemExit(1)

rows = data.get("data", data) if isinstance(data, dict) else data
if not rows:
    print("No requests logged yet. Make a request through the gateway, then re-run.")
    print("Note: only requests that reached the gateway appear here — anything")
    print("talking to Ollama directly is invisible to this, by definition.")
    raise SystemExit(0)

def get(r, *names, default=None):
    for k in names:
        if isinstance(r, dict) and r.get(k) not in (None, ""):
            return r[k]
    return default

recs = []
for r in rows:
    if not isinstance(r, dict):
        continue
    meta = r.get("metadata") or {}
    role = get(r, "model", "model_group", default="?")
    actual = get(meta, "model", "litellm_model_name", default=role_model.get(role, "?"))
    recs.append({
        "t":     str(get(r, "startTime", "start_time", default=""))[:19].replace("T", " "),
        "key":   get(meta, "user_api_key_alias", default=str(get(r, "api_key", default=""))[:8]),
        "role":  role,
        "model": actual,
        "tier":  role_tier.get(role, "?"),
        "pt":    get(r, "prompt_tokens", default=0) or 0,
        "ct":    get(r, "completion_tokens", default=0) or 0,
        "tt":    get(r, "total_tokens", default=0) or 0,
        "cost":  float(get(r, "spend", default=0) or 0),
        "cache": bool(get(r, "cache_hit", default=False)),
    })

recs.sort(key=lambda x: x["t"], reverse=True)

if mode == "recent":
    print(f'{"time":<19} {"key":<9} {"role":<12} {"tier":<5} {"model":<26} {"in":>7} {"out":>7} {"cost":>9}')
    print("-" * 104)
    for r in recs[:n]:
        model = r["model"].split("/")[-1][:26]
        cost = "-" if r["tier"] == "LOCAL" else f'${r["cost"]:.5f}'
        print(f'{r["t"]:<19} {str(r["key"])[:9]:<9} {r["role"]:<12} {r["tier"]:<5} {model:<26} {r["pt"]:>7} {r["ct"]:>7} {cost:>9}')
    print()
    print("tier is derived from config.yaml: ollama* -> LOCAL, anything else -> CLOUD.")
    print("LOCAL rows cost nothing but electricity, so no price is shown.")
else:
    by_role = defaultdict(lambda: {"n": 0, "pt": 0, "ct": 0, "cost": 0.0, "tier": "?"})
    for r in recs:
        b = by_role[r["role"]]
        b["n"] += 1; b["pt"] += r["pt"]; b["ct"] += r["ct"]
        b["cost"] += r["cost"]; b["tier"] = r["tier"]

    print(f'{"role":<14} {"tier":<6} {"calls":>6} {"tokens in":>11} {"tokens out":>11} {"cost":>10}')
    print("-" * 62)
    for role, b in sorted(by_role.items(), key=lambda kv: -kv[1]["pt"] - kv[1]["ct"]):
        cost = "-" if b["tier"] == "LOCAL" else f'${b["cost"]:.4f}'
        print(f'{role:<14} {b["tier"]:<6} {b["n"]:>6} {b["pt"]:>11,} {b["ct"]:>11,} {cost:>10}')

    lt = sum(b["pt"] + b["ct"] for b in by_role.values() if b["tier"] == "LOCAL")
    ct = sum(b["pt"] + b["ct"] for b in by_role.values() if b["tier"] == "CLOUD")
    total = lt + ct
    spend = sum(b["cost"] for b in by_role.values())
    print("-" * 62)
    print(f'{"LOCAL":<14} {lt:>34,} tokens   {(100*lt/total if total else 0):5.1f}%')
    print(f'{"CLOUD":<14} {ct:>34,} tokens   {(100*ct/total if total else 0):5.1f}%')
    print(f'{"spend":<14} {"":>34} ${spend:.4f}')
    print()
    print("The LOCAL share is the number that matters: it is the proportion of")
    print("your work that never left the machine.")
PY
