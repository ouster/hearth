#!/bin/bash
# Dump what the gateway actually thinks it has. Use when healthcheck reports
# "no healthy deployments" — that error means the router loaded the model
# GROUPS but has no usable deployment behind them, which is a different fault
# from a config that never loaded.
#
#   scripts/diagnose.sh

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"
ai_load_env "$ROOT"

GATEWAY="${GATEWAY:-http://127.0.0.1:4000}"
KEY="${LITELLM_MASTER_KEY:?LITELLM_MASTER_KEY not found}"
H=(-H "Authorization: Bearer ${KEY}" -H "Content-Type: application/json")

j() { python3 -m json.tool 2>/dev/null || cat; }
hdr() { printf '\n\033[1m===== %s =====\033[0m\n' "$1"; }

hdr "which config file is the process using"
ps -eo pid,command | grep -E '[l]itellm' | sed 's/^/  /'
echo "  symlink: $(readlink "$HOME/.config/litellm/config.yaml" 2>/dev/null || echo 'not a symlink')"

hdr "/v1/models — what the gateway will serve"
curl -s -m 10 "${H[@]}" "${GATEWAY}/v1/models" | j

hdr "/model/info — deployments and their params"
curl -s -m 10 "${H[@]}" "${GATEWAY}/model/info" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    print(sys.stdin.read()[:500]); raise SystemExit
items = d.get("data", d) if isinstance(d, dict) else d
if not items:
    print("  EMPTY — the router has no deployments at all.")
    print("  That means model_list did not load, even if router_settings did.")
for m in items or []:
    lp = m.get("litellm_params", {})
    print(f'"'"'  {m.get("model_name"):24} -> {lp.get("model")}'"'"')
    print(f'"'"'    api_base: {lp.get("api_base")}'"'"')
    if lp.get("api_key"): print("    api_key: <present>")
' 2>&1 | head -40

hdr "/health — live probe of each deployment"
curl -s -m 60 "${H[@]}" "${GATEWAY}/health" | j | head -60

hdr "ollama direct — is the backend actually answering"
curl -s -m 5 "http://127.0.0.1:11434/api/tags" \
  | python3 -c 'import sys,json;print("  models:", [m["name"] for m in json.load(sys.stdin).get("models",[])])' 2>&1

echo "  chat probe:"
curl -s -m 60 http://127.0.0.1:11434/api/chat \
  -d '{"model":"qwen2.5-coder:7b","stream":false,"messages":[{"role":"user","content":"say ok"}]}' \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); print("   ", d.get("message",{}).get("content","<no content>")[:80])' 2>&1

hdr "error log — last 40 lines"
tail -40 "$HOME/Library/Logs/litellm.error.log" 2>/dev/null | sed 's/^/  /'
