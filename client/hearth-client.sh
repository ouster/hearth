# hearth client — source this on a laptop or any other machine on the LAN.
#
#   echo 'source ~/.hearth-client.sh' >> ~/.zshrc      # macOS
#   echo 'source ~/.hearth-client.sh' >> ~/.bashrc     # Linux
#
# Portable: works under bash and zsh, macOS and Linux. No bash 4 syntax, no
# associative arrays, nothing macOS-specific.
#
# Required before sourcing (scripts/client-setup.sh prints these for you):
#   HEARTH_GATEWAY   e.g. http://192.168.1.10:4000
#   HEARTH_KEY       or put the lan / lan-cloud key in ~/.hearth-key
#
# There is no Ollama here and nothing is downloaded. Every request goes to the
# gateway host, which does the inference and the routing. If that machine is
# off, none of this works — by design.

# Accept legacy AI_STACK_* names from older laptop installs.
HEARTH_GATEWAY="${HEARTH_GATEWAY:-${AI_STACK_GATEWAY:-}}"
if [ -z "${HEARTH_GATEWAY:-}" ]; then
  echo "hearth: set HEARTH_GATEWAY first (e.g. export HEARTH_GATEWAY=http://HOST:4000)" >&2
  echo "          or run scripts/client-setup.sh on the gateway host for copy-paste instructions." >&2
  return 1 2>/dev/null || exit 1
fi

# An explicitly exported HEARTH_KEY wins. The key file is the default, not an
# override — otherwise `HEARTH_KEY=... ai-ask ...` silently uses the old key.
HEARTH_KEY="${HEARTH_KEY:-${AI_STACK_KEY:-}}"

if [ -z "$HEARTH_KEY" ]; then
  if [ -f "$HOME/.hearth-key" ]; then
    HEARTH_KEY="$(cat "$HOME/.hearth-key")"
  elif [ -f "$HOME/.ai-stack-key" ]; then
    HEARTH_KEY="$(cat "$HOME/.ai-stack-key")"
  fi
fi

# OpenAI-compatible, so most tools pick these up with no further config:
# aider, llm, continue, sgpt, openai-python, anything speaking the OpenAI API.
export OPENAI_API_BASE="${HEARTH_GATEWAY}/v1"
export OPENAI_BASE_URL="${HEARTH_GATEWAY}/v1"   # newer SDKs use this name
export OPENAI_API_KEY="${HEARTH_KEY}"

# ---------------------------------------------------------------- aider
# Roles, never model names — the same contract as on the host. When the model
# behind local-code changes, nothing here needs editing.
_ai_role() {
  role="$1"; shift
  aider --model "openai/${role}" "$@"
}

alias ask='_ai_role local-code'        # coding (runs on the gateway host)
alias ask-chat='_ai_role local-chat'   # general questions
alias ask-fast='_ai_role local-chat'
alias ask-big='_ai_role local-big'     # reasoning
alias ask-cloud='_ai_role cloud-cheap' # needs the `lan` or `lan-cloud` key

# ---------------------------------------------------------------- utilities
ai-models() {
  curl -s "${HEARTH_GATEWAY}/v1/models" \
    -H "Authorization: Bearer ${HEARTH_KEY}" \
  | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin)
except Exception:
    print("no response — is the gateway up and the key correct?"); raise SystemExit
ms=[m["id"] for m in d.get("data",[])]
print("roles this key can use:")
[print("  "+m) for m in ms] if ms else print("  (none — key may be wrong)")'
}

ai-ping() {
  # /health/readiness answers 503 {"db":"disconnected"} when the gateway's
  # Postgres is down, and curl exits 0 on a 503. Your key lives in that
  # database, so "answering" and "usable" are different questions — and the
  # second is the one you care about. Read the body, not the exit code.
  printf 'gateway %s ... ' "$HEARTH_GATEWAY"
  _body=$(curl -s -m 5 "${HEARTH_GATEWAY}/health/readiness" 2>/dev/null)
  if [ -z "$_body" ]; then
    echo "UNREACHABLE"
    echo "  - is the gateway host awake?"
    echo "  - same network? try: ping ${HEARTH_GATEWAY#http://}"
  elif printf '%s' "$_body" | grep -qi '"db"[[:space:]]*:[[:space:]]*"connected"'; then
    echo "up"
  else
    echo "DEGRADED — answering, but its database is down"
    echo "  Your key will return 401 until that is fixed."
    echo "  On the gateway host: scripts/boot.sh"
  fi
  unset _body
}

ai-ask() {
  # One-shot question without aider. ai-ask [role] "question"
  if [ $# -eq 0 ]; then
    echo "usage: ai-ask [role] \"question\"" >&2
    return 2
  fi
  _r="local-chat"
  case "${1:-}" in local-*|cloud-*) _r="$1"; shift ;; esac
  curl -s "${HEARTH_GATEWAY}/v1/chat/completions" \
    -H "Authorization: Bearer ${HEARTH_KEY}" \
    -H "Content-Type: application/json" \
    -d "$(python3 -c 'import json,sys; print(json.dumps({"model":sys.argv[1],"messages":[{"role":"user","content":" ".join(sys.argv[2:])}]}))' "$_r" "$@")" \
  | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin)
except Exception:
    print("bad response from gateway"); raise SystemExit
if "error" in d: print("error:", d["error"].get("message", d["error"])); raise SystemExit
print(d["choices"][0]["message"]["content"])'
}
