#!/bin/bash
# Run bench/tasks against roles or candidate models and write a comparison
# report. LM Studio on :1234 (ADR 0016).
#
#   scripts/bench.sh                         every lmstudio LLM role in roles.tsv
#   scripts/bench.sh local-big               a loaded role
#   scripts/bench.sh <lms model key> ...     candidates (see `lms ls`)
#   scripts/bench.sh --evict <key>           unload the roles first — for a
#                                            candidate that will not fit beside
#                                            local-big under the ~48 GB ceiling
#
# JIT is off, so a candidate is loaded explicitly as `bench-candidate`
# (64K context, 1 slot), benched, and unloaded; roles.tsv is restored with
# scripts/lms-load.sh on exit either way. Nothing becomes a role until this
# (and scripts/concurrency-bench.sh) says it should — rule 5.
#
# Auto-checks what can be checked (syntax). Everything else is written out for
# you to read. Do not let a script tell you a model "won" on quality.
#
# bash 3.2: results accumulate in a TSV and python aggregates at the end.
#
# Exit 0 ran, 2 could not run.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"
ai_load_env
AI_PY=/usr/bin/python3
[ -n "${LMSTUDIO_HOST_TOKEN:-}" ] || { echo "could not run: LMSTUDIO_HOST_TOKEN not set"; exit 2; }
hearth_lms_ok || { echo "could not run: LM Studio not running (scripts/boot.sh)"; exit 2; }
export LMSTUDIO_HOST_TOKEN

EVICT=0
if [ "${1:-}" = "--evict" ]; then EVICT=1; shift; fi

TASKDIR="${ROOT}/bench/tasks"
STAMP="$(date +%Y-%m-%d-%H%M)"
OUT="${ROOT}/bench/results/${STAMP}"
mkdir -p "$OUT"
REPORT="${OUT}/report.md"
TSV="${OUT}/raw.tsv"
printf 'model\ttask\ttokens\tseconds\tverdict\n' > "$TSV"

if [ $# -gt 0 ]; then
  MODELS="$*"
else
  MODELS=$(hearth_roles lmstudio | awk -F'\t' '$3 !~ /embed/ {print $1}' | tr '\n' ' ')
fi
ROLE_NAMES=" $(hearth_roles lmstudio | cut -f1 | tr '\n' ' ') "

restore() {
  "$HEARTH_LMS" unload bench-candidate >/dev/null 2>&1 || true
  "${ROOT}/scripts/lms-load.sh" >/dev/null 2>&1 || echo "WARNING: lms-load.sh failed — run it by hand"
}
trap restore EXIT

echo "Models: ${MODELS}"
echo "Server: ${HEARTH_URL}"
echo

body()      { awk 'BEGIN{n=0} /^---$/{n++; next} n>=2{print}' "$1"; }
meta()      { awk -v k="$2" -F': *' '/^---$/{n++} n==1 && $1==k {print $2; exit}' "$1"; }

for model in $MODELS; do
  target="$model"
  case "$ROLE_NAMES" in
    *" ${model} "*) : ;;
    *)
      if ! "$HEARTH_LMS" ls --json 2>/dev/null | grep -qF "\"${model}\""; then
        echo "SKIP ${model} — not downloaded (lms get)"; continue
      fi
      "$HEARTH_LMS" unload bench-candidate >/dev/null 2>&1 || true
      [ "$EVICT" -eq 1 ] && "$HEARTH_LMS" unload --all >/dev/null 2>&1
      if ! "$HEARTH_LMS" load "$model" --identifier bench-candidate -c 65536 --gpu max -y </dev/null >/dev/null 2>&1; then
        echo "SKIP ${model} — load failed (too big beside local-big? try --evict)"; continue
      fi
      target=bench-candidate ;;
  esac
  echo "=== ${model} ==="
  safe=$(printf '%s' "$model" | tr ':/@' '___')
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

    stats=$("$AI_PY" -I - "$target" "${outfile}.prompt" "$HEARTH_URL" "$outfile" <<'PY'
import sys, json, os, time, urllib.request
model, prompt_path, base, out_path = sys.argv[1:5]
payload = json.dumps({
    "model": model, "stream": False,
    "messages": [{"role": "user", "content": open(prompt_path).read()}],
}).encode()
req = urllib.request.Request(base + "/chat/completions", data=payload, headers={
    "Content-Type": "application/json",
    "Authorization": "Bearer " + os.environ["LMSTUDIO_HOST_TOKEN"]})
t0 = time.monotonic()
try:
    with urllib.request.urlopen(req, timeout=1800) as r:
        d = json.load(r)
    secs = time.monotonic() - t0
    open(out_path, "w").write(d["choices"][0]["message"].get("content") or "")
    toks = (d.get("usage") or {}).get("completion_tokens", 0) or 0
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
          "$AI_PY" -I -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "${outfile}.code" \
            2>/dev/null && verdict="syntax-ok" || verdict="SYNTAX-FAIL"
        fi ;;
    esac

    # Tokens first, deliberately. On a memory-bandwidth-bound machine tok/s
    # barely varies between models, so wall-clock is driven by how MANY tokens
    # a model emits.
    tps=$("$AI_PY" -I -c "import sys; t,s=float(sys.argv[1]),float(sys.argv[2]); print(f'{t/s:.1f}' if s>0 else '0')" "$toks" "$secs")
    printf '%7s tok  %7ss  %6s tok/s  %s\n' "$toks" "$secs" "$tps" "$verdict"
    printf '%s\t%s\t%s\t%s\t%s\n' "$model" "$tid" "$toks" "$secs" "$verdict" >> "$TSV"
  done
  [ "$target" = "bench-candidate" ] && "$HEARTH_LMS" unload bench-candidate >/dev/null 2>&1
done

# ---------------------------------------------------------------- report
"$AI_PY" -I - "$TSV" "$OUT" "$STAMP" > "$REPORT" <<'PY'
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
print("Host: M4 Max, 64 GB. LM Studio on :1234. Seconds are wall time per request, including prefill.\n")
print("## Verbosity and speed\n")
print("Tokens emitted is the number that matters. Throughput barely varies between")
print("models on this machine — it is memory-bandwidth bound — so wall-clock is")
print("driven by how much a model chooses to say.\n")
print("| Model | tokens | total s | avg tok/s | syntax ok | syntax fail | errors |")
print("|---|---|---|---|---|---|---|")
ordered = sorted(agg.items(), key=lambda kv: kv[1]["toks"])
least = ordered[0][1]["toks"] if ordered and ordered[0][1]["toks"] else 1
for m, a in ordered:
    avg = a["toks"] / a["secs"] if a["secs"] > 0 else 0
    ratio = a["toks"] / least if least else 1
    print(f'| `{m}` | {a["toks"]} ({ratio:.1f}x) | {a["secs"]:.1f} | {avg:.1f} | {a["ok"]} | {a["bad"]} | {a["err"]} |')

print("\n## Per task\n")
print("| Model | Task | tok/s | verdict |")
print("|---|---|---|---|")
for r in rows:
    s = float(r["seconds"] or 0); t = int(r["tokens"] or 0)
    print(f'| `{r["model"]}` | {r["task"]} | {(t/s if s>0 else 0):.1f} | {r["verdict"]} |')

print(f"""
## Quality — read these yourself

Syntax checks prove a model emitted parseable code, nothing more.

- **03-refactor-judgment** hides a float-for-currency bug in money
  arithmetic. A weak model fixes the obvious `range(len())` and misses the one
  that matters. This is the task that should decide `local-big`.
- **04-long-context** feeds the repo's own docs in. It separates models that
  genuinely use long context from ones that skim the start and confabulate.

Outputs:

```
{out}
```

## Decision

If a candidate wins, also run `scripts/concurrency-bench.sh` against it, then
`scripts/swap-role.sh <role> <model key> <weights path>`, update
`docs/MODELS.md` and write an ADR. Nothing is promoted on speed alone.
""")
PY

echo
echo "Report: ${REPORT}"
