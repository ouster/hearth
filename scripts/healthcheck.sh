#!/bin/bash
# Health of every role on the gateway, plus the privacy leak test.
# Usage: scripts/healthcheck.sh
# Needs: LITELLM_MASTER_KEY, optionally LITELLM_PRIVATE_KEY

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"
CFG="${CFG:-${ROOT}/litellm/config.yaml}"
GATEWAY="${GATEWAY:-http://127.0.0.1:4000}"

# Exit 2 throughout = "could not run", never "found a problem". deploy.sh
# depends on that distinction to decide whether a rollback is warranted.
ai_python_or_die || exit 2
ai_load_env "$ROOT"

if [ -z "${LITELLM_MASTER_KEY:-}" ]; then
  echo "LITELLM_MASTER_KEY not found in either env file:"
  echo "  ~/.config/litellm/env      (the one launchd reads)"
  echo "  ${ROOT}/litellm/.env       (scripts only)"
  exit 2
fi
KEY="$LITELLM_MASTER_KEY"
PRIVATE_KEY="${LITELLM_PRIVATE_KEY:-}"

# Read live roles from the config so dormant (commented-out) cloud roles don't
# show up as false failures. Embedding roles are skipped — different endpoint.
read_roles() {
  "$AI_PY" - "$CFG" "$1" <<'PY'
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
  local start elapsed code body timeout payload

  # Local roles may need a cold load. local-big is ~23GB on Ollama's MLX
  # runner; the first request after it was evicted can take a minute.
  # Cloud roles have no such excuse.
  case "$label" in
    local) timeout="${PROBE_TIMEOUT_LOCAL:-600}" ;;
    *)     timeout="${PROBE_TIMEOUT_CLOUD:-90}"  ;;
  esac

  # Cloud Flash counts thinking against max_tokens. A cap of 10 is spent
  # before any visible text (ADR 0014). Omit it and let the model stop.
  # Local probes stay capped so a cold role cannot ramble.
  payload="{\"model\":\"${role}\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with the single word: ok\"}]}"
  if [ "$label" != "cloud" ]; then
    payload="{\"model\":\"${role}\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with the single word: ok\"}],\"max_tokens\":10}"
  fi

  start=$(date +%s)
  body=$(curl -s -m "$timeout" -w '\n%{http_code}' \
    -H "Authorization: Bearer ${key}" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "${GATEWAY}/v1/chat/completions" 2>&1)
  code=$(printf '%s' "$body" | tail -n1)
  elapsed=$(( $(date +%s) - start ))

  if [ "$code" = "200" ]; then
    printf '  %-16s %-8s OK    %4ss\n' "$role" "$label" "$elapsed"
    pass=$((pass+1))
  elif [ "$code" = "000" ]; then
    # curl never got a response. Almost always a cold model load, not a fault.
    printf '  %-16s %-8s TIMEOUT after %ss\n' "$role" "$label" "$timeout"
    echo "      No HTTP response — the model was probably still loading."
    echo "      Check with: ollama ps    (shows what is resident)"
    echo "      Retry with: PROBE_TIMEOUT_LOCAL=1200 scripts/healthcheck.sh"
    fail=$((fail+1))
  else
    printf '  %-16s %-8s FAIL  HTTP %s\n' "$role" "$label" "$code"
    printf '%s\n' "$body" | head -c 300 | sed 's/^/      /'
    # Only claim the router is empty if the gateway actually said so.
    printf '%s' "$body" | grep -q 'no healthy deployments' && SAW_NO_DEPLOYMENTS=1
    fail=$((fail+1))
  fi
}
SAW_NO_DEPLOYMENTS=0

echo "Gateway: ${GATEWAY}"
echo
echo "Reachability:"
case "$(ai_gateway_state "$GATEWAY" 5)" in
  ready)
    echo "  gateway responding (db:connected)"
    ;;
  nodb)
    # Not a warning. Virtual keys live in Postgres, so with the DB down every
    # scoped key 401s and the leak test below proves nothing: the private key
    # would be "refused" on a cloud role for the wrong reason entirely.
    echo "  gateway answering but db:disconnected — NOT usable"
    echo "      Every virtual key returns 401. The privacy leak test cannot run:"
    echo "      a refusal here means broken auth, not enforced scope."
    echo "      Fix: scripts/boot.sh    then re-run this."
    exit 1
    ;;
  hung)
    echo "  gateway is listening but /health/readiness did not answer"
    echo "      This is what a dead Postgres looks like from here: LiteLLM"
    echo "      blocks retrying the connection rather than returning 503."
    echo "      Check the database first, not launchd:  scripts/status.sh"
    echo "      Fix: scripts/boot.sh"
    exit 1
    ;;
  *)
    echo "  gateway NOT responding — nothing listening on :4000"
    echo "      check: launchctl list | grep litellm"
    exit 1
    ;;
esac

echo
echo "Local roles:"
for r in ${LOCAL_ROLES[@]+"${LOCAL_ROLES[@]}"}; do probe "$r" "$KEY" "local"; done

echo
echo "Cloud roles:"
for r in ${CLOUD_ROLES[@]+"${CLOUD_ROLES[@]}"}; do probe "$r" "$KEY" "cloud"; done

echo
echo "Privacy leak test:"
#
# Two halves, and BOTH are needed:
#
#   Positive control — the private key must SUCCEED on a local role. Without
#     this, a key that is simply broken refuses everything and looks like
#     perfect scoping.
#   Negative test — the private key must be REFUSED on a LIVE cloud role.
#     Probing a dormant role is meaningless: "model not found" also returns
#     4xx, so the test would pass without proving anything about scope.
#
if [ -z "$PRIVATE_KEY" ]; then
  echo "  SKIPPED — LITELLM_PRIVATE_KEY not set (needs Postgres + virtual keys)"
  echo "  Until this passes, the privacy boundary is documented, not enforced."
elif [ -z "${LOCAL_ROLES[0]:-}" ]; then
  echo "  SKIPPED — no local role to use as the positive control"
elif [ "${#CLOUD_ROLES[@]:-0}" -eq 0 ] || [ -z "${CLOUD_ROLES[0]:-}" ]; then
  echo "  SKIPPED — no live cloud role to probe against"
else
  probe_local="${LOCAL_ROLES[0]}"
  probe_cloud="${CLOUD_ROLES[0]}"

  ctl=$(curl -s -m 120 -o /dev/null -w '%{http_code}' \
    -H "Authorization: Bearer ${PRIVATE_KEY}" -H "Content-Type: application/json" \
    -d "{\"model\":\"${probe_local}\",\"messages\":[{\"role\":\"user\",\"content\":\"ok\"}],\"max_tokens\":5}" \
    "${GATEWAY}/v1/chat/completions")

  if [ "$ctl" = "200" ]; then
    echo "  control: private key WORKS on ${probe_local} (HTTP 200)"
    pass=$((pass+1))
  else
    echo "  *** control FAILED: private key cannot reach ${probe_local} (HTTP ${ctl}) ***"
    echo "      The key is broken, not scoped. The negative test below proves nothing."
    fail=$((fail+1))
  fi

  body=$(curl -s -m 30 -w '\n%{http_code}' \
    -H "Authorization: Bearer ${PRIVATE_KEY}" -H "Content-Type: application/json" \
    -d "{\"model\":\"${probe_cloud}\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":5}" \
    "${GATEWAY}/v1/chat/completions")
  code=$(printf '%s' "$body" | tail -n1)
  msg=$(printf '%s' "$body" | sed '$d')

  case "$code" in
    200)
      echo "  *** LEAK: private key reached ${probe_cloud} (HTTP 200) ***"
      fail=$((fail+1)) ;;
    401|403)
      echo "  private key correctly REFUSED ${probe_cloud} (HTTP ${code})"
      if printf '%s' "$msg" | grep -qiE 'not allowed|no access|not in the list|team.*model'; then
        echo "      refusal cites model scope — this is the boundary working"
      else
        echo "      NOTE: refused, but the message does not mention model scope."
        echo "      Check it is not an auth failure masquerading as a scope refusal:"
        printf '%s' "$msg" | head -c 200 | sed 's/^/        /'
        echo
      fi
      pass=$((pass+1)) ;;
    *)
      echo "  INCONCLUSIVE: HTTP ${code} from ${probe_cloud}"
      printf '%s' "$msg" | head -c 200 | sed 's/^/      /'; echo
      echo "      Not counted as a pass. A 4xx can mean 'model missing' rather than 'refused'."
      fail=$((fail+1)) ;;
  esac
fi

echo
echo "MCP tool scope:"
#
# A second egress path the model-level test above cannot see. Tool RESULTS are
# fed back into the prompt, and a tool can reach the network on its own, so a
# key that cannot touch a cloud MODEL can still ship data off the host through
# a TOOL. The private key must therefore see zero tools it is not granted.
#
# Same two halves as the leak test. "Nobody sees any tools" is the correct
# result when nothing is registered AND the result of a broken MCP gateway,
# and those must not look the same — hence the master-key control.
mcp_tools_for() {
  curl -s -m 10 -H "Authorization: Bearer $1" "${GATEWAY}/v1/mcp/tools" 2>/dev/null \
    | "$AI_PY" -c 'import sys,json
try: d=json.load(sys.stdin)
except Exception: print("ERR"); raise SystemExit
t=d.get("tools")
print("ERR" if t is None else len(t))'
}

mcp_admin="$(mcp_tools_for "$KEY")"
if [ "$mcp_admin" = "ERR" ]; then
  echo "  SKIPPED — /v1/mcp/tools did not answer (build without the MCP gateway?)"
elif [ "$mcp_admin" = "0" ]; then
  echo "  no MCP servers registered — nothing to scope yet"
  echo "      Registering one is a routing decision: see docs/decisions/0008."
elif [ -z "$PRIVATE_KEY" ]; then
  echo "  ${mcp_admin} tool(s) registered, but LITELLM_PRIVATE_KEY is unset"
  echo "      Cannot prove the private key is scoped. Not a pass."
  fail=$((fail+1))
else
  echo "  control: ${mcp_admin} tool(s) visible to the master key"
  mcp_priv="$(mcp_tools_for "$PRIVATE_KEY")"
  allowed="${HEARTH_PRIVATE_MCP_TOOLS:-0}"
  if [ "$mcp_priv" = "ERR" ]; then
    echo "  *** INCONCLUSIVE: private key got no usable answer from /v1/mcp/tools ***"
    fail=$((fail+1))
  elif [ "$mcp_priv" = "$allowed" ]; then
    echo "  private key sees ${mcp_priv} tool(s) — matches its granted scope"
    pass=$((pass+1))
  else
    echo "  *** LEAK: private key sees ${mcp_priv} tool(s), expected ${allowed} ***"
    echo "      A tool that reaches the network is egress the model scope does"
    echo "      not cover. Check object_permission.mcp_servers on the key and"
    echo "      require_key_mcp_access_defined in config.yaml."
    fail=$((fail+1))
  fi
fi

echo
echo "Direct Ollama bypass check:"
# Same false-pass class as the leak test: an unreachable address and a closed
# port produce identical curl failures. Probe THIS machine's LAN IP, or report
# inconclusive — never a hardcoded foreign address.
LANIP="$(ai_lan_ip)"
LISTEN="$(lsof -nP -iTCP:11434 -sTCP:LISTEN 2>/dev/null | awk 'NR>1{print $9}' | tr '\n' ' ')"
if [ -n "$LISTEN" ]; then
  echo "  listening on: ${LISTEN}"
  case " $LISTEN " in
    *" *:11434 "*|*" 0.0.0.0:11434 "*|*" [::]:11434 "*)
      echo "  *** OPEN — Ollama bound to all interfaces, bypasses the gateway ***"
      fail=$((fail+1))
      ;;
  esac
fi
if [ -z "$LANIP" ]; then
  echo "  INCONCLUSIVE — no LAN IP (set HEARTH_LAN_IP or connect to a network)"
  echo "      Unreachable and secure look the same; not counted as a pass."
  fail=$((fail+1))
elif curl -s -m 5 -o /dev/null "http://${LANIP}:11434/api/tags" 2>/dev/null; then
  echo "  *** LEAK — Ollama reachable at ${LANIP}:11434, bypassing the gateway ***"
  fail=$((fail+1))
else
  echo "  Ollama not reachable from LAN address ${LANIP}"
  pass=$((pass+1))
fi

echo
echo "${pass} passed, ${fail} failed"

# Only fires when the gateway genuinely reported an empty router. Showing this
# after a plain cold-load timeout sends you chasing the wrong fault.
if [ "${SAW_NO_DEPLOYMENTS}" -eq 1 ]; then
  cat <<EOF

If every role reported "no healthy deployments", the config is probably fine
and the router is not. In order of likelihood:

  1. The gateway started before the database schema existed.
       launchctl kickstart -k $(ai_litellm_agent)

  2. store_model_in_db: true makes some LiteLLM versions serve ONLY database
     rows and ignore config.yaml's model_list. With an empty DB that means no
     models at all. Set it to false in litellm/config.yaml and redeploy —
     nothing in this stack depends on it (see docs/decisions/0002).
EOF
fi

[ "$fail" -eq 0 ]
