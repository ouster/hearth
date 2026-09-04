#!/bin/bash
# Fails if an MCP server that leaves this machine is reachable by a key that
# can also reach a cloud model.
#
#   scripts/audit-mcp-scope.sh
#
# audit-fallbacks.sh guards the model path: a prompt must not reach a cloud
# model by accident. This guards the tool path, which is a separate hole:
#
#   - A tool RESULT is fed back into the prompt. On a cloud role, the tool
#     definitions and everything they return go to the provider along with it.
#   - A tool can reach the network by itself. auslaw-mcp queries AustLII and
#     jade.io, so a search term leaves the host whether or not a cloud MODEL
#     was ever involved. The model-level leak test cannot see that.
#
# So the rule this enforces is the tool twin of rule 2:
#
#   an MCP server marked as leaving the host must not be reachable by any key
#   that can also reach a cloud role.
#
# Egress is declared, not guessed. Each server in config.yaml carries an
# x-hearth-egress marker, because nothing in the MCP protocol tells a gateway
# whether a tool phones home — only the person who read its source knows, and
# that knowledge has to live somewhere a script can check.
#
# Exit 2 = could not run. Exit 1 = a real scope violation. Never confuse them.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"
CFG="${CFG:-${ROOT}/litellm/config.yaml}"
GATEWAY="${GATEWAY:-http://127.0.0.1:4000}"

ai_python_or_die || exit 2
ai_load_env "$ROOT"

# ---------------------------------------------------------------- config side
# Which registered servers are declared as leaving the host.
EGRESS=$("$AI_PY" - "$CFG" <<'PY'
import sys, yaml
cfg = yaml.safe_load(open(sys.argv[1])) or {}
for name, spec in (cfg.get('mcp_servers') or {}).items():
    spec = spec or {}
    mark = str(spec.get('x-hearth-egress', 'unknown')).lower()
    print(f"{name}\t{mark}")
PY
) || { echo "could not parse ${CFG}"; exit 2; }

if [ -z "$EGRESS" ]; then
  echo "No MCP servers registered in ${CFG}."
  echo "PASS — nothing to scope."
  exit 0
fi

echo "Registered MCP servers:"
printf '%s\n' "$EGRESS" | awk -F'\t' '{printf "  %-20s egress=%s\n", $1, $2}'

undeclared=$(printf '%s\n' "$EGRESS" | awk -F'\t' '$2=="unknown"{print $1}' | tr '\n' ' ')
if [ -n "$undeclared" ]; then
  echo
  echo "FAIL — server(s) with no x-hearth-egress marker: ${undeclared}"
  echo "  Add 'x-hearth-egress: none' or 'x-hearth-egress: <where it calls>'."
  echo "  Unmarked is treated as a failure, not as safe: an unread server is"
  echo "  exactly the one most likely to phone home."
  exit 1
fi

# ---------------------------------------------------------------- key side
if [ -z "${LITELLM_MASTER_KEY:-}" ]; then
  echo
  echo "Cannot check key grants — LITELLM_MASTER_KEY not set."
  exit 2
fi

# Via a temp FILE, not a pipe. A heredoc and a pipe both claim stdin, the
# heredoc wins, and json.load(sys.stdin) then reads an empty program tail —
# which surfaces as "could not parse the key list" rather than as a bug.
TMPKEYS="$(mktemp)"
trap 'rm -f "$TMPKEYS"' EXIT
curl -s -m 15 -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
  "${GATEWAY}/key/list?return_full_object=true" > "$TMPKEYS" 2>/dev/null || {
  echo; echo "Cannot reach ${GATEWAY} to read key grants."; exit 2; }

echo
"$AI_PY" - "$CFG" "$TMPKEYS" <<'PY'
import sys, json, yaml

cfg = yaml.safe_load(open(sys.argv[1])) or {}
egress = {
    name: str((spec or {}).get('x-hearth-egress', 'unknown')).lower()
    for name, spec in (cfg.get('mcp_servers') or {}).items()
}
leaves_host = {n for n, m in egress.items() if m not in ('none', 'local')}

cloud_roles = {
    m['model_name'] for m in cfg.get('model_list', [])
    if m['model_name'].startswith('cloud-')
}

try:
    d = json.load(open(sys.argv[2]))
except Exception:
    print("Could not parse the key list."); raise SystemExit(2)
keys = d.get("keys", d) if isinstance(d, dict) else d

violations, rows = [], []
for k in keys or []:
    if not isinstance(k, dict) or not k.get("key_alias"):
        continue
    alias = k["key_alias"]
    models = set(k.get("models") or [])
    perm = k.get("object_permission") or {}
    granted = set(perm.get("mcp_servers") or [])

    # An empty model list means "every model", which includes the cloud ones.
    reaches_cloud = bool(models & cloud_roles) or not models
    bad = granted & leaves_host
    rows.append((alias, sorted(granted) or ['-'], reaches_cloud))
    if reaches_cloud and bad:
        violations.append((alias, sorted(bad)))

print("Key grants:")
for alias, granted, cloud in rows:
    print(f"  {alias:<12} mcp={','.join(granted):<24} cloud={'yes' if cloud else 'no'}")

if violations:
    print("\nFAIL — key can reach BOTH a cloud model and a network-reaching tool:")
    for alias, bad in violations:
        print(f"  {alias}: {', '.join(bad)}")
    print("\n  Tool output enters the prompt. On a cloud role it goes to the")
    print("  provider with it, and the tool has already reached the network on")
    print("  its own account. Split the key, or drop the server from its grant.")
    raise SystemExit(1)

print("\nPASS — no key holds both a cloud role and a network-reaching MCP tool")
PY
exit $?
