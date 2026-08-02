#!/bin/bash
# Find which way of disabling qwen3 thinking actually works, by measuring
# tokens emitted for the same prompt.
#
#   scripts/test-nothink.sh
#
# Three candidates, because "it should work" is not evidence:
#
#   A  Ollama's think:false parameter, straight to Ollama
#   B  /no_think appended to the user message
#   C  a Modelfile variant with /no_think baked into the system prompt
#
# C is the one that survives the gateway: LiteLLM is configured with
# drop_params:true, which strips unknown parameters like `think` before they
# reach Ollama. A can therefore work against Ollama directly and still do
# nothing through :4000 — exactly the class of false-green this repo keeps
# tripping over.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"
ai_python_or_die || exit 2
ai_load_env "$ROOT"

OLLAMA="${OLLAMA_API_BASE:-http://127.0.0.1:11434}"
BASE="qwen3:8b"
VARIANT="qwen3:8b-nothink"
PROMPT="Write a Python function that reads a CSV and returns rows where the third column is numeric. Include type hints."

probe() {
  local label="$1" model="$2" prompt="$3" think="$4"
  "$AI_PY" - "$model" "$prompt" "$OLLAMA" "$think" "$label" <<'PY'
import sys, json, time, urllib.request
model, prompt, base, think, label = sys.argv[1:6]
body = {"model": model, "stream": False,
        "messages": [{"role": "user", "content": prompt}]}
if think == "false":
    body["think"] = False
req = urllib.request.Request(base + "/api/chat", data=json.dumps(body).encode(),
                             headers={"Content-Type": "application/json"})
t0 = time.time()
try:
    with urllib.request.urlopen(req, timeout=600) as r:
        d = json.load(r)
except Exception as e:
    print(f"  {label:<34} ERROR {type(e).__name__}")
    raise SystemExit
secs = time.time() - t0
toks = d.get("eval_count", 0) or 0
content = d.get("message", {}).get("content", "")
thinking = "<think>" in content or (d.get("message", {}).get("thinking") or "")
print(f"  {label:<34} {toks:>6} tok  {secs:>6.1f}s  thinking={'YES' if thinking else 'no'}")
PY
}

echo "Baseline and three ways to suppress thinking"
echo "Prompt: a small Python task"
echo

probe "baseline (thinking on)"        "$BASE" "$PROMPT" "true"
probe "A: think:false param"          "$BASE" "$PROMPT" "false"
probe "B: /no_think in user message"  "$BASE" "${PROMPT} /no_think" "true"

echo
echo "Building variant ${VARIANT} for C..."
printf 'FROM %s\nSYSTEM """/no_think"""\n' "$BASE" | ollama create "$VARIANT" -f - >/dev/null 2>&1 \
  && echo "  created (shares blobs with ${BASE} — negligible extra disk)" \
  || { echo "  ollama create FAILED"; exit 1; }

probe "C: Modelfile system /no_think"  "$VARIANT" "$PROMPT" "true"

cat <<'EOF'

Reading this:
  Fewer tokens and thinking=no means it worked.

  C is the option to prefer even if A also works, because LiteLLM's
  drop_params:true strips unknown parameters — so A can pass here and still
  do nothing once the request goes through the gateway on :4000.

  If C wins:
    scripts/swap-role.sh local-chat qwen3:8b-nothink
EOF
