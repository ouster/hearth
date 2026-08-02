#!/bin/bash
# Disable qwen3 thinking on local-chat, THROUGH THE GATEWAY, and verify it.
#
#   scripts/apply-nothink.sh
#
# Measured directly against Ollama, `think:false` cuts a sample prompt from
# 2236 tokens to 333. But LiteLLM is configured with drop_params:true, and if
# it strips the parameter the request reaches Ollama unchanged and thinking
# stays on — a config that looks right and does nothing.
#
# So: apply, restart, measure through :4000, and REVERT automatically if the
# token count says it did not take.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"
ai_python_or_die || exit 2
ai_load_env "$ROOT"

CFG="${ROOT}/litellm/config.yaml"
BAK="${CFG}.pre-nothink"
GATEWAY="http://127.0.0.1:4000"
KEY="${LITELLM_MASTER_KEY:?LITELLM_MASTER_KEY not found}"
PROMPT="Write a Python function that reads a CSV and returns rows where the third column is numeric. Include type hints."

measure() {
  "$AI_PY" - "$GATEWAY" "$KEY" "$PROMPT" <<'PY'
import sys, json, time, urllib.request
gw, key, prompt = sys.argv[1:4]
body = {"model": "local-chat", "messages": [{"role": "user", "content": prompt}]}
req = urllib.request.Request(gw + "/v1/chat/completions",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "Authorization": "Bearer " + key})
t0 = time.time()
try:
    with urllib.request.urlopen(req, timeout=600) as r:
        d = json.load(r)
except Exception as e:
    print(f"0 0 ERR:{type(e).__name__}")
    raise SystemExit
secs = time.time() - t0
toks = (d.get("usage") or {}).get("completion_tokens", 0)
content = d["choices"][0]["message"]["content"]
print(f"{toks} {secs:.1f} {'THINKING' if '<think>' in content else 'direct'}")
PY
}

restart() {
  launchctl kickstart -k "$(ai_litellm_agent)" 2>/dev/null
  for _ in $(seq 1 30); do
    ai_gateway_ready "$GATEWAY" 3 && return 0
    sleep 1
  done
  return 1
}

echo "1/4  Baseline through the gateway"
before="$(measure)"
echo "     ${before}"
btok=$(printf '%s' "$before" | awk '{print $1}')

echo
echo "2/4  Adding think:false to local-chat"
cp "$CFG" "$BAK"
"$AI_PY" - "$CFG" <<'PY'
import sys, re
path = sys.argv[1]
lines = open(path).read().split('\n')
out, inrole, done = [], False, False
for ln in lines:
    if re.match(r'\s*-\s*model_name:\s*local-chat\s*$', ln):
        inrole = True
    elif re.match(r'\s*-\s*model_name:', ln):
        inrole = False
    out.append(ln)
    if inrole and not done and re.match(r'\s*api_base:', ln):
        indent = ln[:len(ln) - len(ln.lstrip())]
        out.append(f'{indent}think: false      # qwen3 thinking off — see ADR 0006')
        done = True
open(path, 'w').write('\n'.join(out))
print('     added' if done else '     WARNING: no api_base line found under local-chat')
PY

echo
echo "3/4  Restarting"
restart && echo "     gateway up" || { echo "     did not come up — reverting"; mv "$BAK" "$CFG"; restart; exit 1; }

echo
echo "4/4  Measuring through the gateway"
after="$(measure)"
echo "     ${after}"
atok=$(printf '%s' "$after" | awk '{print $1}')

echo
if [ "${atok:-0}" -gt 0 ] && [ "${btok:-0}" -gt 0 ] && \
   [ "$("$AI_PY" -c "print(1 if $atok < $btok * 0.5 else 0)")" = "1" ]; then
  rm -f "$BAK"
  echo "WORKED — ${btok} tokens -> ${atok} through the gateway."
  echo "LiteLLM forwarded think:false despite drop_params:true."
  echo
  echo "Next: update docs/MODELS.md, write an ADR, re-run scripts/bench.sh"
else
  mv "$BAK" "$CFG"
  restart
  echo "NO EFFECT — ${btok} -> ${atok}. Config reverted, gateway restarted."
  echo
  echo "drop_params:true is stripping the parameter. Options:"
  echo "  1. Set drop_params:false and re-run (may surface other param errors)"
  echo "  2. Swap local-chat to a non-thinking model: llama3.1:8b"
  echo "     scripts/swap-role.sh local-chat llama3.1:8b"
  exit 1
fi
