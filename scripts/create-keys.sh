#!/bin/bash
# Create the scoped virtual keys.
#
# Two purposes, neither of them billing — you are the only user:
#
#   1. SCOPE. The `private` key's model list contains no cloud roles, so a
#      request for a cloud model with it is refused by the gateway rather than
#      by remembering not to. That is the privacy boundary.
#
#   2. CIRCUIT BREAKER. max_budget caps spend on YOUR provider account. If a
#      key leaks onto the LAN, or an agent loop runs away overnight against a
#      $15/M-output model, the gateway stops honouring that key. It is a fuse,
#      not an invoice. Raise the numbers freely — just don't set them to null
#      on anything that can reach a paid model.
#
# Re-run after enabling dormant cloud roles so the keys can see them.
# Requires Postgres: scripts/db.sh up

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"
ai_load_env "$ROOT"

GATEWAY="${GATEWAY:-http://127.0.0.1:4000}"
KEY="${LITELLM_MASTER_KEY:?LITELLM_MASTER_KEY not found in ~/.config/litellm/env or litellm/.env}"

# Keep in sync with the UNCOMMENTED roles in litellm/config.yaml.
# A key listing a role that does not exist in the config will fail to create.
LOCAL='"local-fast","local-code","local-big","local-embed"'
CLOUD_CHEAP='"cloud-cheap"'

# Only cloud-cheap is live — no Anthropic key by choice, no OpenRouter key yet.
# When you enable a dormant role in config.yaml, add it here and re-run.
CLOUD_ALL='"cloud-cheap"'
# CLOUD_ALL='"cloud-cheap","cloud-code","cloud-frontier","cloud-frontier-direct","cloud-frontier-fast"'

mkkey() {
  local alias="$1" models="$2" cap="$3" desc="$4"
  local payload result newkey
  payload=$(cat <<JSON
{
  "key_alias": "${alias}",
  "models": [${models}],
  "max_budget": ${cap},
  "budget_duration": "30d",
  "metadata": {"description": "${desc}"}
}
JSON
)
  result=$(curl -s -X POST "${GATEWAY}/key/generate" \
    -H "Authorization: Bearer ${KEY}" \
    -H "Content-Type: application/json" \
    -d "${payload}")

  newkey=$(printf '%s' "$result" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("key",""))' 2>/dev/null)

  if [ -z "$newkey" ]; then
    echo "FAILED: ${alias}"
    printf '%s\n' "$result" | head -c 400
    return 1
  fi
  printf '%-10s %s\n' "${alias}" "${newkey}"
}

echo "Creating scoped keys on ${GATEWAY}"
echo

# No cloud roles, no cap needed — local inference costs electricity, not tokens.
mkkey "private" "${LOCAL}" 'null' \
  "Local only. Conveyancing work, Open WebUI default. Never add cloud roles."

mkkey "general" "${LOCAL},${CLOUD_ALL}" '100' \
  "This machine: Cursor, aider, scripts on non-sensitive repos."

mkkey "lan" "${LOCAL},${CLOUD_CHEAP}" '10' \
  "Other machines, everyday. Local plus cheap cloud."

mkkey "roam" "${LOCAL},${CLOUD_ALL}" '25' \
  "Laptop, when it needs real cloud models. Small cap so a lost laptop is contained."

echo
echo "Paste into litellm/.env as LITELLM_{PRIVATE,GENERAL,LAN,ROAM}_KEY"
echo "Then: scripts/healthcheck.sh"
