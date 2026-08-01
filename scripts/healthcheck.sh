#!/bin/bash
# Health of every role on the gateway, plus the privacy leak test.
# Usage: scripts/healthcheck.sh
# Needs: LITELLM_MASTER_KEY, optionally LITELLM_PRIVATE_KEY

set -uo pipefail

GATEWAY="${GATEWAY:-http://127.0.0.1:4000}"
KEY="${LITELLM_MASTER_KEY:?LITELLM_MASTER_KEY not set}"
PRIVATE_KEY="${LITELLM_PRIVATE_KEY:-}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CFG="${CFG:-${ROOT}/litellm/config.yaml}"

# Read live roles from the config so dormant (commented-out) cloud roles don't
# show up as false failures. Embedding roles are skipped — different endpoint.
read_roles() {
  python3 - "$CFG" "$1" <<'PY'
import sys, yaml
cfg = yaml.safe_load(open(sys.argv[1]))
want = sys.argv[2]
for m in cfg.get('model_list', []):
    n = m['model_name']
    if (m.get('model_info') or {}).get('mode') == 'embedding':
        continue
    if n.startswith(want):
        print(n)
PY
}

read -r -a LOCAL_ROLES <<< "$(read_roles local- | tr '\n' ' ')"
read -r -a CLOUD_ROLES <<< "$(read_roles cloud- | tr '\n' ' ')"

pass=0; fail=0

probe() {
  local role="$1" key="$2" label="$3"
  local start elapsed code body
  start=$(date +%s)
  body=$(curl -s -m 180 -w '\n%{http_code}' \
    -H "Authorization: Bearer ${key}" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"${role}\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with the single word: ok\"}],\"max_tokens\":10}" \
    "${GATEWAY}/v1/chat/completions" 2>&1)
  code=$(printf '%s' "$body" | tail -n1)
  elapsed=$(( $(date +%s) - start ))

  if [ "$code" = "200" ]; then
    printf '  %-16s %-8s OK    %3ss\n' "$role" "$label" "$elapsed"
    pass=$((pass+1))
  else
    printf '  %-16s %-8s FAIL  HTTP %s\n' "$role" "$label" "$code"
    printf '%s\n' "$body" | head -c 300 | sed 's/^/      /'
    fail=$((fail+1))
  fi
}

echo "Gateway: ${GATEWAY}"
echo
echo "Reachability:"
if curl -s -m 5 -o /dev/null "${GATEWAY}/health/readiness"; then
  echo "  gateway responding"
else
  echo "  gateway NOT responding — check: launchctl list | grep litellm"
  exit 1
fi

echo
echo "Local roles:"
for r in "${LOCAL_ROLES[@]}"; do probe "$r" "$KEY" "local"; done

echo
echo "Cloud roles:"
for r in "${CLOUD_ROLES[@]}"; do probe "$r" "$KEY" "cloud"; done

echo
echo "Privacy leak test:"
if [ -z "$PRIVATE_KEY" ]; then
  echo "  SKIPPED — LITELLM_PRIVATE_KEY not set (needs Postgres + virtual keys)"
else
  code=$(curl -s -m 30 -o /dev/null -w '%{http_code}' \
    -H "Authorization: Bearer ${PRIVATE_KEY}" \
    -H "Content-Type: application/json" \
    -d '{"model":"cloud-code","messages":[{"role":"user","content":"hi"}],"max_tokens":5}' \
    "${GATEWAY}/v1/chat/completions")
  if [ "$code" = "401" ] || [ "$code" = "403" ] || [ "$code" = "400" ]; then
    echo "  private key correctly REFUSED cloud-code (HTTP ${code})"
    pass=$((pass+1))
  else
    echo "  *** LEAK: private key reached cloud-code (HTTP ${code}) ***"
    fail=$((fail+1))
  fi
fi

echo
echo "Direct Ollama bypass check:"
if curl -s -m 5 -o /dev/null "http://192.168.50.154:11434/api/tags" 2>/dev/null; then
  echo "  WARNING — Ollama still reachable on the LAN, bypassing the gateway"
else
  echo "  Ollama not reachable from the LAN address"
fi

echo
echo "${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
