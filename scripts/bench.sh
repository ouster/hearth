#!/bin/bash
# Run bench/tasks against loaded roles and write a comparison report.
# oMLX on :1234 (ADR 0026).
#
#   scripts/bench.sh                         every resident role in roles.tsv
#   scripts/bench.sh main-brain              one loaded role
#
# A name that is not a resident role is refused. Put candidate weights under
# ~/.hearth/models, point a role at them, and load with scripts/omlx.sh up.
# Nothing becomes a role until this (and scripts/concurrency-bench.sh) says
# it should — rule 5.
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
[ -n "${OMLX_HOST_TOKEN:-}" ] || { echo "could not run: OMLX_HOST_TOKEN not set"; exit 2; }
code=$(hearth_http /models || true)
[ "$code" != "000" ] || { echo "could not run: oMLX is not answering (scripts/omlx.sh up)"; exit 2; }
export OMLX_HOST_TOKEN

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
  MODELS=$(hearth_resident_roles | awk -F'\t' '$3 !~ /embed/ {print $1}' | tr '\n' ' ')
fi
ROLE_NAMES=" $(hearth_resident_roles | cut -f1 | tr '\n' ' ') "
for m in $MODELS; do
  case "$ROLE_NAMES" in
    *" ${m} "*) ;;
    *) echo "could not run: ${m} is not a resident role. Bench a loaded role."; exit 2 ;;
  esac
done

echo "Models: ${MODELS}"
echo "Server: ${HEARTH_URL}"
echo

body()      { awk 'BEGIN{n=0} /^---$/{n++; next} n>=2{print}' "$1"; }
meta()      { awk -v k="$2" -F': *' '/^---$/{n++} n==1 && $1==k {print $2; exit}' "$1"; }

for model in $MODELS; do
  target="$model"
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
    "Authorization": "Bearer " + os.environ["OMLX_HOST_TOKEN"]})
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
        # A fence-less answer is checked as written. An empty file passes
        # bash -n and ast.parse, so no code at all must not count as a pass.
        grep -q '```' "$outfile" || cp "$outfile" "${outfile}.code"
        if ! grep -q '[^[:space:]]' "${outfile}.code"; then
          verdict="NO-CODE"
        elif [ "$check" = "bash-syntax" ]; then
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
    elif v in ("SYNTAX-FAIL", "NO-CODE"): a["bad"] += 1
    elif v == "error":     a["err"] += 1

print(f"# Bench — {stamp}\n")
import subprocess
def _sysctl(k):
    try:
        return subprocess.run(["/usr/sbin/sysctl", "-n", k], capture_output=True, text=True).stdout.strip()
    except OSError:
        return ""
_chip = _sysctl("machdep.cpu.brand_string").replace("Apple ", "") or "unknown chip"
_ram = _sysctl("hw.memsize")
_ram = "%d GB" % (int(_ram) // 1073741824) if _ram.isdigit() else "unknown RAM"
print(f"Host: {_chip}, {_ram}. oMLX on :1234. Seconds are wall time per request, including prefill.\n")
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
  that matters. This is the task that should decide `main-brain`.
- **04-long-context** feeds the repo's own docs in. It separates models that
  genuinely use long context from ones that skim the start and confabulate.

Outputs:

```
{out}
```

## Decision

If a candidate wins, also run `scripts/concurrency-bench.sh` against it, then
point the role at those weights in `config/roles.tsv`, update `docs/MODELS.md`,
and write an ADR. Nothing is promoted on speed alone.
""")
PY

echo
echo "Report: ${REPORT}"
