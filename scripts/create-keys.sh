#!/bin/bash
# Create or update the scoped virtual keys. Idempotent — safe to re-run.
#
#   scripts/create-keys.sh          create missing, update existing
#   scripts/create-keys.sh --prune  also delete keys with unmanaged aliases
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
FORCE=false; PRUNE=false
for a in "$@"; do
  [ "$a" = "--force" ] && FORCE=true
  [ "$a" = "--prune" ] && PRUNE=true
done

# Keep in sync with the UNCOMMENTED roles in litellm/config.yaml.
# A key listing a role that does not exist in the config will fail.
LOCAL='"local-code","local-big","local-chat","local-embed"'
CLOUD_CHEAP='"cloud-cheap"'

# Only cloud-cheap is live — no Anthropic key by choice, no OpenRouter key yet.
# When you enable a dormant role in config.yaml, add it here and re-run.
CLOUD_ALL='"cloud-cheap"'
# CLOUD_ALL='"cloud-cheap","cloud-code","cloud-frontier","cloud-frontier-direct","cloud-frontier-fast"'

# ---- MCP scope, per key -----------------------------------------------------
#
# Every key states its MCP grant explicitly. An absent or empty list does NOT
# mean "none" in LiteLLM — it means "inherit the team's list", and a team with
# an empty list means "no restriction". config.yaml sets
# require_key_mcp_access_defined to close that, but the two must agree: the
# flag makes an empty list grant nothing, and these lists say what it grants.
#
# Deny is an EMPTY list here, not the documented `no-mcp-servers` sentinel.
# LiteLLM 1.85.1 validates every entry against the registered servers before
# it interprets sentinels, so sending no-mcp-servers with none registered is
# rejected outright:
#
#   403  Only globally available (allow_all_keys) MCP servers can be
#        assigned: []. Disallowed servers: ['no-mcp-servers'].
#
# An empty list is accepted, and these keys belong to no team, so there is no
# team list for it to inherit. With require_key_mcp_access_defined set in
# config.yaml an empty list grants nothing. Revisit the sentinel if these keys
# ever join a team, because only the sentinel overrides team inheritance.
#
# Do not "fix" this by omitting object_permission — an absent field leaves any
# previous grant in place, so revoking would silently do nothing.
#
# Access GROUPS are deliberately unused. BerriAI/litellm#27657 (open as of
# 2026-08-02): assigning a group to a team never creates the underlying
# permission row, so discovery and enforcement both fall through. Direct
# per-key lists avoid that code path entirely.
MCP_NONE=''

# Servers each key may reach. Keep in sync with mcp_servers in config.yaml.
# Quote every entry, comma-separated, e.g. MCP_GENERAL='"auslaw"'.
#
# Only `research` holds a tool that reaches the network, and it holds no cloud
# role — that pairing is what audit-mcp-scope.sh enforces. `private` gets
# nothing: auslaw queries AustLII, and a key whose whole promise is that
# nothing leaves the machine cannot own a tool that leaves the machine.
MCP_PRIVATE="${MCP_NONE}"
MCP_GENERAL="${MCP_NONE}"
MCP_LAN="${MCP_NONE}"
MCP_LAN_CLOUD="${MCP_NONE}"
MCP_RESEARCH='"auslaw"'

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

# An MCP grant needs a TEAM behind it. A key outside a team may only be
# assigned servers flagged allow_all_keys, and that flag is not a scoping
# mechanism — the manager UNIONS those servers into every key's allowed set,
# so it means "grant to everyone". The team is the only way to grant one
# server to one key.
#
# Echoes the team_id. Idempotent: reuses the team with this alias if present.
sync_team() {
  local alias="$1" mcp="$2" tid r
  tid=$(api GET "/team/list" "" | "$AI_PY" -c "
import sys, json
try: d = json.load(sys.stdin)
except Exception: raise SystemExit
ts = d.get('teams', d) if isinstance(d, dict) else d
for t in ts or []:
    if isinstance(t, dict) and t.get('team_alias') == '${alias}':
        print(t.get('team_id', '')); break" 2>/dev/null)

  if [ -n "$tid" ]; then
    api POST "/team/update" \
      "{\"team_id\":\"${tid}\",\"object_permission\":{\"mcp_servers\":[${mcp}]}}" >/dev/null
  else
    r=$(api POST "/team/new" \
      "{\"team_alias\":\"${alias}\",\"object_permission\":{\"mcp_servers\":[${mcp}]}}")
    tid=$(printf '%s' "$r" | "$AI_PY" -c "import sys,json; print(json.load(sys.stdin).get('team_id',''))" 2>/dev/null)
    if [ -z "$tid" ]; then
      printf '  team %-4s CREATE FAILED\n' "$alias"
      printf '%s' "$r" | head -c 300 | sed 's/^/      /'; echo
      return 1
    fi
  fi
  printf '%s' "$tid"
}

sync_key() {
  local alias="$1" models="$2" cap="$3" mcp="$4" desc="$5" team="${6:-}"
  local tok; tok="$(token_for "$alias")"
  local team_field=""
  [ -n "$team" ] && team_field=",\"team_id\":\"${team}\""

  if [ -n "$tok" ] && $FORCE; then
    api POST "/key/delete" "{\"keys\":[\"${tok}\"]}" >/dev/null
    tok=""
  fi

  if [ -n "$tok" ]; then
    # Update in place — the key VALUE is unchanged, so nothing needs re-pasting.
    local r
    r=$(api POST "/key/update" \
      "{\"key\":\"${tok}\",\"models\":[${models}],\"max_budget\":${cap},\"object_permission\":{\"mcp_servers\":[${mcp}]}${team_field},\"metadata\":{\"description\":\"${desc}\"}}")
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
    "{\"key_alias\":\"${alias}\",\"models\":[${models}],\"max_budget\":${cap},\"budget_duration\":\"30d\",\"object_permission\":{\"mcp_servers\":[${mcp}]}${team_field},\"metadata\":{\"description\":\"${desc}\"}}")
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

sync_key "private" "${LOCAL}" 'null' "${MCP_PRIVATE}" \
  "Local only. Sensitive matter work, Open WebUI default. Never add cloud roles."
sync_key "general" "${LOCAL},${CLOUD_ALL}" '100' "${MCP_GENERAL}" \
  "This machine: aider, Zed, scripts on non-sensitive repos."
sync_key "lan" "${LOCAL},${CLOUD_CHEAP}" '10' "${MCP_LAN}" \
  "Other machines, everyday. Local plus cheap cloud."
sync_key "lan-cloud" "${LOCAL},${CLOUD_ALL}" '25' "${MCP_LAN_CLOUD}" \
  "Laptop, when it needs real cloud models. Small cap so a lost laptop is contained."
# Local models only, plus the AustLII tools. No cloud role, deliberately: tool
# output re-enters the prompt, so a key holding both would hand a cloud
# provider whatever the tool fetched. Switching to this key is the act of
# saying "this query is going to AustLII" — see docs/decisions/0008.
RESEARCH_TEAM="$(sync_team "research" "${MCP_RESEARCH}")"
sync_key "research" "${LOCAL}" 'null' "${MCP_RESEARCH}" \
  "Legal research. Local models plus AustLII lookup. Queries LEAVE this machine." \
  "${RESEARCH_TEAM}"

# While every cloud role except cloud-cheap is dormant, CLOUD_ALL == CLOUD_CHEAP,
# so lan and lan-cloud currently grant identical access. They diverge the moment
# a dormant role is enabled. Say so rather than let it look like a bug.
if [ "$CLOUD_ALL" = "$CLOUD_CHEAP" ]; then
  echo
  echo "NOTE: lan and lan-cloud are identical right now — cloud-cheap is the only"
  echo "      live cloud role. lan-cloud becomes meaningful once you enable a"
  echo "      dormant role and add it to CLOUD_ALL in this script."
fi

# Renaming an alias creates a new key and silently leaves the old one live and
# usable. `roam` -> `lan-cloud` did exactly that.
ORPHANS=$(printf '%s\n' "$EXISTING" | awk -F'\t' '{print $1}' \
          | grep -vE '^(private|general|lan|lan-cloud)$' | grep -v '^$' | tr '\n' ' ')
if [ -n "$ORPHANS" ]; then
  echo
  echo "ORPHANED KEYS still active on the gateway:${ORPHANS}"
  if $PRUNE; then
    for o in $ORPHANS; do
      # key_aliases, not the token hash — /key/delete rejects hashes silently,
      # returning success-shaped output while deleting nothing.
      r=$(api POST "/key/delete" "{\"key_aliases\":[\"${o}\"]}")
      if printf '%s' "$r" | grep -qi 'deleted\|success'; then
        echo "  deleted ${o}"
      else
        echo "  could not delete ${o}:"
        printf '%s' "$r" | head -c 200 | sed 's/^/      /'; echo
      fi
    done
  else
    echo "  Still valid and usable. Remove them with:"
    echo "    scripts/create-keys.sh --prune"
  fi
fi

echo
echo "Verify what each key can now reach:"
echo "  curl -s ${GATEWAY}/v1/models -H \"Authorization: Bearer \$LITELLM_PRIVATE_KEY\" | python3 -m json.tool"
echo
echo "Then: scripts/healthcheck.sh"
