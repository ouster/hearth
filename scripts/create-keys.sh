#!/bin/bash
# Create or update the scoped virtual keys. Idempotent — safe to re-run.
#
#   scripts/create-keys.sh          create missing, update existing
#   scripts/create-keys.sh --force  delete and recreate (new key values)
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
#      not an invoice.
#
# Re-run after adding or removing a role: a key's model list is fixed at
# creation, so an existing key cannot see a role added later. Updating in place
# means the key VALUES do not change and nothing needs re-pasting.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"
ai_python_or_die || exit 2
ai_load_env "$ROOT"

GATEWAY="${GATEWAY:-http://127.0.0.1:4000}"
KEY="${LITELLM_MASTER_KEY:?LITELLM_MASTER_KEY not found in ~/.config/litellm/env or litellm/.env}"
FORCE=false
[ "${1:-}" = "--force" ] && FORCE=true

# Keep in sync with the UNCOMMENTED roles in litellm/config.yaml.
# A key listing a role that does not exist in the config will fail.
LOCAL='"local-code","local-big","local-chat","local-embed"'
CLOUD_CHEAP='"cloud-cheap"'

# Only cloud-cheap is live — no Anthropic key by choice, no OpenRouter key yet.
# When you enable a dormant role in config.yaml, add it here and re-run.
CLOUD_ALL='"cloud-cheap"'
# CLOUD_ALL='"cloud-cheap","cloud-code","cloud-frontier","cloud-frontier-direct","cloud-frontier-fast"'

api() {
  curl -s -X "$1" "${GATEWAY}$2" \
    -H "Authorization: Bearer ${KEY}" \
    -H "Content-Type: application/json" \
    ${3:+-d "$3"}
}

# alias -> token, for keys that already exist.
#
# Data goes via a temp FILE, not a pipe. `curl | python <<'PY'` looks reasonable
# and is broken: the heredoc and the pipe both claim stdin, python reads its
# program from the heredoc, and sys.stdin is then empty. And the script goes in
# a heredoc rather than -c because escaped quotes inside an f-string raise
# "f-string expression part cannot include a backslash" on 3.11.
TMPJSON="$(mktemp)"
trap 'rm -f "$TMPJSON"' EXIT
api GET "/key/list?return_full_object=true" "" > "$TMPJSON"

EXISTING=$("$AI_PY" - "$TMPJSON" <<'PY'
import sys, json
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    raise SystemExit
ks = d.get("keys", d) if isinstance(d, dict) else d
for k in ks or []:
    if isinstance(k, dict) and k.get("key_alias"):
        tok = k.get("token") or k.get("key") or ""
        print(k["key_alias"] + "\t" + tok)
PY
)

token_for() { printf '%s\n' "$EXISTING" | awk -F'\t' -v a="$1" '$1==a{print $2; exit}'; }

sync_key() {
  local alias="$1" models="$2" cap="$3" desc="$4"
  local tok; tok="$(token_for "$alias")"

  if [ -n "$tok" ] && $FORCE; then
    api POST "/key/delete" "{\"keys\":[\"${tok}\"]}" >/dev/null
    tok=""
  fi

  if [ -n "$tok" ]; then
    # Update in place — the key VALUE is unchanged, so nothing needs re-pasting.
    local r
    r=$(api POST "/key/update" \
      "{\"key\":\"${tok}\",\"models\":[${models}],\"max_budget\":${cap},\"metadata\":{\"description\":\"${desc}\"}}")
    if printf '%s' "$r" | grep -q '"error"'; then
      printf '  %-9s UPDATE FAILED\n' "$alias"
      printf '%s' "$r" | head -c 300 | sed 's/^/      /'; echo
    else
      printf '  %-9s updated in place — existing key still valid\n' "$alias"
    fi
    return
  fi

  local r newkey
  r=$(api POST "/key/generate" \
    "{\"key_alias\":\"${alias}\",\"models\":[${models}],\"max_budget\":${cap},\"budget_duration\":\"30d\",\"metadata\":{\"description\":\"${desc}\"}}")
  newkey=$(printf '%s' "$r" | "$AI_PY" -c "import sys,json; print(json.load(sys.stdin).get('key',''))" 2>/dev/null)

  if [ -z "$newkey" ]; then
    printf '  %-9s CREATE FAILED\n' "$alias"
    printf '%s' "$r" | head -c 300 | sed 's/^/      /'; echo
  else
    printf '  %-9s %s   <-- NEW, paste into litellm/.env\n' "$alias" "$newkey"
  fi
}

echo "Syncing scoped keys on ${GATEWAY}"
$FORCE && echo "  --force: deleting and recreating, key values WILL change"
echo

sync_key "private" "${LOCAL}" 'null' \
  "Local only. Conveyancing work, Open WebUI default. Never add cloud roles."
sync_key "general" "${LOCAL},${CLOUD_ALL}" '100' \
  "This machine: Cursor, aider, scripts on non-sensitive repos."
sync_key "lan" "${LOCAL},${CLOUD_CHEAP}" '10' \
  "Other machines, everyday. Local plus cheap cloud."
sync_key "roam" "${LOCAL},${CLOUD_ALL}" '25' \
  "Laptop, when it needs real cloud models. Small cap so a lost laptop is contained."

echo
echo "Verify what each key can now reach:"
echo "  curl -s ${GATEWAY}/v1/models -H \"Authorization: Bearer \$LITELLM_PRIVATE_KEY\" | python3 -m json.tool"
echo
echo "Then: scripts/healthcheck.sh"
