#!/bin/bash
# Run bench/tasks against a set of models and write a comparison report.
#
#   scripts/bench.sh                                  # incumbents vs candidates
#   scripts/bench.sh qwen3-coder:30b llama3.3:70b     # specific models
#
# Hits Ollama directly, not the gateway: candidates are not roles yet, and that
# is the point — nothing becomes a role until this says it should.
#
# Auto-checks what can be checked (syntax). Everything else is written out for
# you to read. Do not let a script tell you a model "won" on quality.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OLLAMA="${OLLAMA_API_BASE:-http://127.0.0.1:11434}"
TASKDIR="${ROOT}/bench/tasks"
STAMP="$(date +%Y-%m-%d-%H%M)"
OUT="${ROOT}/bench/results/${STAMP}"

if [ $# -gt 0 ]; then
  MODELS=("$@")
else
  MODELS=(qwen2.5-coder:32b llama3.3:70b qwen3-coder:30b gpt-oss:20b devstral:24b)
fi

mkdir -p "$OUT"
REPORT="${OUT}/report.md"

available() { ollama list 2>/dev/null | awk 'NR>1{print $1}' | grep -qx "$1"; }

# Strip YAML front matter, return the prompt body.
body() { awk 'BEGIN{n=0} /^---$/{n++; next} n>=2{print}' "$1"; }
meta() { awk -v k="$2" -F': *' '/^---$/{n++} n==1 && $1==k {print $2; exit}' "$1"; }

{
  echo "# Bench — ${STAMP}"
  echo
  echo "Host: M4 Max, 64GB. Ollama direct at ${OLLAMA}."
  echo
} > "$REPORT"

declare -A TOKS TIME PASS FAIL

for model in "${MODELS[@]}"; do
  if ! available "$model"; then
    echo "SKIP ${model} — not pulled" >&2
    continue
  fi
  echo "=== ${model} ==="
  mkdir -p "${OUT}/${model//[:\/]/_}"
  TOKS[$model]=0; TIME[$model]=0; PASS[$model]=0; FAIL[$model]=0

  for task in "$TASKDIR"/*.md; do
    tid="$(basename "$task" .md)"
    check="$(meta "$task" auto_check)"
    prompt="$(body "$task")"

    # 04 gets the repo docs as context — that is the whole test.
    if [ "$tid" = "04-long-context" ]; then
      prompt="$(cat "${ROOT}"/docs/*.md 2>/dev/null)

---

${prompt}"
    fi

    printf '  %-24s ' "$tid"
    resp=$(curl -s -m 900 "${OLLAMA}/api/chat" \
      -H 'Content-Type: application/json' \
      -d "$(python3 -c 'import json,sys; print(json.dumps({"model":sys.argv[1],"stream":False,"messages":[{"role":"user","content":sys.stdin.read()}]}))' "$model" <<< "$prompt")")

    read -r content evalcount evaldur <<< "$(printf '%s' "$resp" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
    print("OK", d.get("eval_count", 0), d.get("eval_duration", 1))
    sys.stderr.write(d.get("message", {}).get("content", ""))
except Exception as e:
    print("ERR 0 1")
' 2> "${OUT}/${model//[:\/]/_}/${tid}.out")"

    if [ "$content" != "OK" ]; then
      echo "ERROR"
      FAIL[$model]=$(( ${FAIL[$model]} + 1 ))
      continue
    fi

    tps=$(python3 -c "print(f'{$evalcount/($evaldur/1e9):.1f}')" 2>/dev/null || echo 0)
    secs=$(python3 -c "print(f'{$evaldur/1e9:.1f}')" 2>/dev/null || echo 0)
    TOKS[$model]=$(python3 -c "print(${TOKS[$model]} + $evalcount)")
    TIME[$model]=$(python3 -c "print(f'{${TIME[$model]} + $evaldur/1e9:.1f}')")

    # Auto-check where the task declares one.
    verdict=""
    outfile="${OUT}/${model//[:\/]/_}/${tid}.out"
    case "$check" in
      bash-syntax)
        sed -n '/```/,/```/p' "$outfile" | sed '1d;$d' > "${outfile}.code"
        if bash -n "${outfile}.code" 2>/dev/null; then
          verdict="syntax-ok"; PASS[$model]=$(( ${PASS[$model]} + 1 ))
        else
          verdict="SYNTAX-FAIL"; FAIL[$model]=$(( ${FAIL[$model]} + 1 ))
        fi ;;
      python-syntax)
        sed -n '/```/,/```/p' "$outfile" | sed '1d;$d' > "${outfile}.code"
        if python3 -c "import ast,sys; ast.parse(open('${outfile}.code').read())" 2>/dev/null; then
          verdict="syntax-ok"; PASS[$model]=$(( ${PASS[$model]} + 1 ))
        else
          verdict="SYNTAX-FAIL"; FAIL[$model]=$(( ${FAIL[$model]} + 1 ))
        fi ;;
      *) verdict="needs-reading" ;;
    esac

    printf '%6s tok/s  %5ss  %s\n' "$tps" "$secs" "$verdict"
  done
done

{
  echo "## Speed and auto-checks"
  echo
  echo "| Model | tokens | total s | avg tok/s | syntax pass | syntax fail |"
  echo "|---|---|---|---|---|---|"
  for m in "${!TOKS[@]}"; do
    avg=$(python3 -c "print(f'{${TOKS[$m]}/max(${TIME[$m]},0.1):.1f}')")
    echo "| \`${m}\` | ${TOKS[$m]} | ${TIME[$m]} | ${avg} | ${PASS[$m]} | ${FAIL[$m]} |"
  done
  echo
  echo "## Quality — read these yourself"
  echo
  echo "Syntax checks prove a model emitted parseable code, nothing more."
  echo "Task 03 (float-for-currency) and 04 (long context) are the discriminating"
  echo "ones and neither can be scored automatically. Outputs are in:"
  echo
  echo '```'
  echo "${OUT}"
  echo '```'
  echo
  echo "## Decision"
  echo
  echo "If a candidate wins, write an ADR in docs/decisions/, update"
  echo "docs/MODELS.md and litellm/config.yaml together, then re-run"
  echo "scripts/audit-fallbacks.sh and scripts/healthcheck.sh."
} >> "$REPORT"

echo
echo "Report: ${REPORT}"
