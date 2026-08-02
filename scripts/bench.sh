#!/bin/bash
# Run bench/tasks against a set of models and write a comparison report.
#
#   scripts/bench.sh                          every local model in config.yaml
#   scripts/bench.sh gpt-oss:20b qwen3:8b     specific models
#
# Hits Ollama directly, not the gateway: candidates are not roles yet, and that
# is the point — nothing becomes a role until this says it should.
#
# Auto-checks what can be checked (syntax). Everything else is written out for
# you to read. Do not let a script tell you a model "won" on quality.
#
# bash 3.2 compatible. macOS ships bash 3.2, which has no associative arrays,
# so results accumulate in a TSV and python aggregates at the end.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"
ai_python_or_die || exit 2

OLLAMA="${OLLAMA_API_BASE:-http://127.0.0.1:11434}"
TASKDIR="${ROOT}/bench/tasks"
STAMP="$(date +%Y-%m-%d-%H%M)"
OUT="${ROOT}/bench/results/${STAMP}"
mkdir -p "$OUT"
REPORT="${OUT}/report.md"
TSV="${OUT}/raw.tsv"
printf 'model\ttask\ttokens\tseconds\tverdict\n' > "$TSV"

# Default to whatever local models the config currently uses. Hardcoding a list
# is how this script ended up naming two models that had been deleted.
if [ $# -gt 0 ]; then
  MODELS="$*"
else
  MODELS=$("$AI_PY" - "${ROOT}/litellm/config.yaml" <<'PY'
import sys, yaml
cfg = yaml.safe_load(open(sys.argv[1])) or {}
seen = []
for m in cfg.get('model_list', []):
    if (m.get('model_info') or {}).get('mode') == 'embedding':
        continue
    t = m['litellm_params']['model']
    if t.startswith(('ollama/', 'ollama_chat/')):
        name = t.split('/', 1)[1]
        if name not in seen:
            seen.append(name)
print(' '.join(seen))
PY
)
fi

echo "Models: ${MODELS}"
echo "Ollama: ${OLLAMA}"
echo

available() { ollama list 2>/dev/null | awk 'NR>1{print $1}' | grep -qx -e "$1" -e "${1}:latest"; }
body()      { awk 'BEGIN{n=0} /^---$/{n++; next} n>=2{print}' "$1"; }
meta()      { awk -v k="$2" -F': *' '/^---$/{n++} n==1 && $1==k {print $2; exit}' "$1"; }

for model in $MODELS; do
  if ! available "$model"; then
    echo "SKIP ${model} — not pulled"
    continue
  fi
  echo "=== ${model} ==="
  safe=$(printf '%s' "$model" | tr ':/' '__')
  mkdir -p "${OUT}/${safe}"

  for task in "$TASKDIR"/*.md; do
    tid="$(basename "$task" .md)"
    check="$(meta "$task" auto_check)"
    outfile="${OUT}/${safe}/${tid}.out"

    body "$task" > "${outfile}.prompt"
    if [ "$tid" = "04-long-context" ]; then
      # The point of this task is whether the model uses long context or skims.
      { cat "${ROOT}"/docs/*.md 2>/dev/null; echo; echo "---"; echo; body "$task"; } \
        > "${outfile}.prompt"
    fi

    printf '  %-24s ' "$tid"

    stats=$("$AI_PY" - "$model" "${outfile}.prompt" "$OLLAMA" "$outfile" <<'PY'
import sys, json, urllib.request
model, prompt_path, base, out_path = sys.argv[1:5]
payload = json.dumps({
    "model": model, "stream": False,
    "messages": [{"role": "user", "content": open(prompt_path).read()}],
}).encode()
req = urllib.request.Request(base + "/api/chat", data=payload,
                             headers={"Content-Type": "application/json"})
try:
    with urllib.request.urlopen(req, timeout=1800) as r:
        d = json.load(r)
    open(out_path, "w").write(d.get("message", {}).get("content", ""))
    toks = d.get("eval_count", 0) or 0
    secs = (d.get("eval_duration", 0) or 0) / 1e9
    print(f"{toks} {secs:.1f}")
except Exception as e:
    open(out_path, "w").write("")
    print(f"0 0 ERR:{type(e).__name__}")
PY
)
    toks=$(printf '%s' "$stats" | awk '{print $1}')
    secs=$(printf '%s' "$stats" | awk '{print $2}')
    err=$(printf '%s' "$stats" | awk '{print $3}')

    if [ -n "${err:-}" ]; then
      printf 'ERROR %s\n' "$err"
      printf '%s\t%s\t0\t0\terror\n' "$model" "$tid" >> "$TSV"
      continue
    fi

    # Auto-check only where the task declares one. Syntax proves parseability,
    # nothing more — the discriminating tasks are judged by reading them.
    verdict="needs-reading"
    case "$check" in
      bash-syntax|python-syntax)
        sed -n '/```/,/```/p' "$outfile" | sed '1d;$d' > "${outfile}.code"
        if [ "$check" = "bash-syntax" ]; then
          bash -n "${outfile}.code" 2>/dev/null && verdict="syntax-ok" || verdict="SYNTAX-FAIL"
        else
          "$AI_PY" -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "${outfile}.code" \
            2>/dev/null && verdict="syntax-ok" || verdict="SYNTAX-FAIL"
        fi ;;
    esac

    tps=$("$AI_PY" -c "import sys; t,s=float(sys.argv[1]),float(sys.argv[2]); print(f'{t/s:.1f}' if s>0 else '0')" "$toks" "$secs")
    printf '%6s tok/s  %6ss  %s\n' "$tps" "$secs" "$verdict"
    printf '%s\t%s\t%s\t%s\t%s\n' "$model" "$tid" "$toks" "$secs" "$verdict" >> "$TSV"
  done
done

# ---------------------------------------------------------------- report
"$AI_PY" - "$TSV" "$OUT" "$STAMP" > "$REPORT" <<'PY'
import sys, csv
from collections import defaultdict

tsv, out, stamp = sys.argv[1], sys.argv[2], sys.argv[3]
rows = list(csv.DictReader(open(tsv), delimiter='\t'))

agg = defaultdict(lambda: {"toks": 0, "secs": 0.0, "ok": 0, "bad": 0, "err": 0})
for r in rows:
    a = agg[r["model"]]
    a["toks"] += int(r["tokens"] or 0)
    a["secs"] += float(r["seconds"] or 0)
    v = r["verdict"]
    if v == "syntax-ok":   a["ok"]  += 1
    elif v == "SYNTAX-FAIL": a["bad"] += 1
    elif v == "error":     a["err"] += 1

print(f"# Bench — {stamp}\n")
print("Host: M4 Max, 64 GB. Ollama direct.\n")
print("## Speed and auto-checks\n")
print("| Model | tokens | total s | avg tok/s | syntax ok | syntax fail | errors |")
print("|---|---|---|---|---|---|---|")
for m, a in sorted(agg.items()):
    avg = a["toks"] / a["secs"] if a["secs"] > 0 else 0
    print(f'| `{m}` | {a["toks"]} | {a["secs"]:.1f} | {avg:.1f} | {a["ok"]} | {a["bad"]} | {a["err"]} |')

print("\n## Per task\n")
print("| Model | Task | tok/s | verdict |")
print("|---|---|---|---|")
for r in rows:
    s = float(r["seconds"] or 0); t = int(r["tokens"] or 0)
    print(f'| `{r["model"]}` | {r["task"]} | {(t/s if s>0 else 0):.1f} | {r["verdict"]} |')

print(f"""
## Quality — read these yourself

Syntax checks prove a model emitted parseable code, nothing more.

The two discriminating tasks cannot be scored automatically:

- **03-refactor-judgment** hides a float-for-currency bug in settlement
  arithmetic. A weak model fixes the obvious `range(len())` and misses the one
  that matters. This is the task that should decide `local-big`.
- **04-long-context** feeds the repo's own docs in. It separates models that
  genuinely use long context from ones that skim the start and confabulate.

Outputs:

```
{out}
```

## Decision

If a candidate wins, use `scripts/swap-role.sh <role> <model>`, then update
`docs/MODELS.md` and write an ADR. Nothing is promoted on speed alone.
""")
PY

echo
echo "Report: ${REPORT}"
