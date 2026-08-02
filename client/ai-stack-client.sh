# ai-stack client — source this on a laptop or any other machine on the LAN.
#
#   echo 'source ~/.ai-stack-client.sh' >> ~/.zshrc      # macOS
#   echo 'source ~/.ai-stack-client.sh' >> ~/.bashrc     # Linux
#
# Portable: works under bash and zsh, macOS and Linux. No bash 4 syntax, no
# associative arrays, nothing macOS-specific.
#
# Set these two before sourcing, or edit the defaults below:
#   AI_STACK_GATEWAY   e.g. http://192.168.50.154:4000
#   AI_STACK_KEY       the `lan` or `lan-cloud` key from the host's litellm/.env
#
# There is no Ollama here and nothing is downloaded. Every request goes to the
# gateway on the Mac Studio, which does the inference and the routing. If that
# machine is off, none of this works — by design.

AI_STACK_GATEWAY="${AI_STACK_GATEWAY:-http://192.168.50.154:4000}"
AI_STACK_KEY="${AI_STACK_KEY:-}"

if [ -f "$HOME/.ai-stack-key" ]; then
  AI_STACK_KEY="$(cat "$HOME/.ai-stack-key")"
fi

# OpenAI-compatible, so most tools pick these up with no further config:
# aider, llm, continue, sgpt, openai-python, anything speaking the OpenAI API.
export OPENAI_API_BASE="${AI_STACK_GATEWAY}/v1"
export OPENAI_BASE_URL="${AI_STACK_GATEWAY}/v1"   # newer SDKs use this name
export OPENAI_API_KEY="${AI_STACK_KEY}"

# ---------------------------------------------------------------- aider
# Roles, never model names — the same contract as on the host. When the model
# behind local-code changes, nothing here needs editing.
_ai_role() {
  role="$1"; shift
  aider --model "openai/${role}" "$@"
}

alias ask='_ai_role local-code'        # coding, private (runs on the Studio)
alias ask-chat='_ai_role local-chat'   # general questions
alias ask-fast='_ai_role local-chat'
alias ask-big='_ai_role local-big'     # reasoning
alias ask-cloud='_ai_role cloud-cheap' # needs the `lan` or `lan-cloud` key

# ---------------------------------------------------------------- utilities
ai-models() {
  curl -s "${AI_STACK_GATEWAY}/v1/models" \
    -H "Authorization: Bearer ${AI_STACK_KEY}" \
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
  printf 'gateway %s ... ' "$AI_STACK_GATEWAY"
  if curl -s -m 5 -o /dev/null "${AI_STACK_GATEWAY}/health/readiness"; then
    echo "up"
  else
    echo "UNREACHABLE"
    echo "  - is the Mac Studio awake?"
    echo "  - same network? try: ping ${AI_STACK_GATEWAY#http://}"
  fi
}

ai-ask() {
  # One-shot question without aider. ai-ask [role] "question"
  _r="local-chat"
  case "$1" in local-*|cloud-*) _r="$1"; shift ;; esac
  curl -s "${AI_STACK_GATEWAY}/v1/chat/completions" \
    -H "Authorization: Bearer ${AI_STACK_KEY}" \
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
