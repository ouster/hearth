# hearth client — source this on a laptop or any other machine on the LAN.
#
#   echo 'source ~/.hearth-client.sh' >> ~/.zshrc      # macOS
#   echo 'source ~/.hearth-client.sh' >> ~/.bashrc     # Linux
#
# Portable: works under bash and zsh, macOS and Linux. No bash 4 syntax, no
# associative arrays, nothing macOS-specific.
#
# Required before sourcing (scripts/provision-client.sh on the gateway host
# prints these for you):
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
  echo "          or run scripts/provision-client.sh on the gateway host for copy-paste instructions." >&2
  return 1 2>/dev/null || exit 1
fi

HEARTH_KEY="${HEARTH_KEY:-${AI_STACK_KEY:-}}"

if [ -f "$HOME/.hearth-key" ]; then
  HEARTH_KEY="$(tr -d '\n\r' < "$HOME/.hearth-key")"
elif [ -f "$HOME/.ai-stack-key" ]; then
  HEARTH_KEY="$(tr -d '\n\r' < "$HOME/.ai-stack-key")"
fi

if [ -z "${HEARTH_KEY:-}" ]; then
  echo "hearth: no key — put the lan key in ~/.hearth-key (chmod 600)" >&2
  echo "          or run scripts/provision-client.sh on the gateway host." >&2
  return 1 2>/dev/null || exit 1
fi

# OpenAI-compatible, so most tools pick these up with no further config:
# aider, llm, continue, sgpt, openai-python, anything speaking the OpenAI API.
export OPENAI_API_BASE="${HEARTH_GATEWAY}/v1"
export OPENAI_BASE_URL="${HEARTH_GATEWAY}/v1"   # newer SDKs use this name
export OPENAI_API_KEY="${HEARTH_KEY}"

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
  printf 'gateway %s ... ' "$HEARTH_GATEWAY"
  if curl -s -m 5 -o /dev/null "${HEARTH_GATEWAY}/health/readiness"; then
    echo "up"
  else
    echo "UNREACHABLE"
    echo "  - is the gateway host awake?"
    # ping wants a host, not host:port
    _host="${HEARTH_GATEWAY#http://}"
    _host="${_host#https://}"
    _host="${_host%%/*}"
    _host="${_host%%:*}"
    echo "  - same network? try: ping ${_host}"
    unset _host
  fi
}

ai-ask() {
  # One-shot question without aider. ai-ask [role] "question"
  _r="local-chat"
  case "$1" in local-*|cloud-*) _r="$1"; shift ;; esac
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

# ---------------------------------------------------------------- one-shot roles
# Same semantics as client/hearth-client.ps1 — HTTP via the gateway, no aider.
# For repo editing: pipx install aider-chat, then `aider` (OPENAI_* are set).
# Drop any pre-existing aliases so zsh will accept function definitions.
unalias ask ask-chat ask-fast ask-big ask-cloud 2>/dev/null || true
ask()       { ai-ask local-code  "$@"; }
ask-chat()  { ai-ask local-chat  "$@"; }
ask-fast()  { ai-ask local-chat  "$@"; }
ask-big()   { ai-ask local-big   "$@"; }
ask-cloud() { ai-ask cloud-cheap "$@"; }
