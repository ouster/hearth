#!/bin/bash
# Download candidate models for benching. Does NOT change any role —
# candidates sit on disk until scripts/bench.sh and concurrency-bench.sh say
# they win, then scripts/swap-role.sh.
#
#   scripts/pull-candidates.sh <hugging face URL> ...          # plan + cost
#   scripts/pull-candidates.sh --pull <hugging face URL> ...   # download
#
# No model names live in this script (rule 1): keep any shortlist in
# docs/MODELS.md and pass the URLs here. An exact URL picks an exact build;
# a bare staff-pick name with `lms get -y` can pick another quantisation.
#
# Exit 0 ok, 1 a candidate will not fit, 2 could not run.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"

GPU_CEILING_GB=48     # macOS caps GPU memory at ~75% of 64 GB
HEADROOM_GB=4         # phase 1 gate: peak footprint ≥ 4 GB under the ceiling
PULL=0
[ "${1:-}" = "--pull" ] && { PULL=1; shift; }
[ $# -gt 0 ] || { sed -n '2,12p' "$0"; exit 2; }
[ -x "$HEARTH_LMS" ] || { echo "could not run: lms not found"; exit 2; }

free_gb=$(df -g "$HOME/.lmstudio/models" 2>/dev/null | awk 'NR==2 {print $4}')
resident_gb=$(for p in $(pgrep -f '\.lmstudio/|LM Studio'); do footprint -p "$p" 2>/dev/null | grep -o 'Footprint: [0-9.]* [KMG]B' | head -1; done \
  | awk '{v=$2; if ($3=="MB") v/=1024; if ($3=="KB") v/=1048576; s+=v} END {printf "%.1f", s}')
echo "Disk free: ${free_gb:-?} GB   LM Studio footprint now: ${resident_gb:-?} GB   GPU ceiling: ~${GPU_CEILING_GB} GB"
echo

rc=0; total=0
for url in "$@"; do
  repo=$(printf '%s' "$url" | sed -E 's#^https?://huggingface.co/##; s#/(tree|blob|resolve)/.*##')
  file=$(printf '%s' "$url" | sed -nE 's#.*/(blob|resolve)/[^/]+/(.*)$#\2#p')
  bytes=$(curl -s -m 20 "https://huggingface.co/api/models/${repo}?blobs=true" | /usr/bin/python3 -I -c '
import json, sys
try:
    d = json.load(sys.stdin)
except ValueError:
    print(0); sys.exit()
f = sys.argv[1]
print(sum(s.get("size", 0) for s in d.get("siblings", []) if not f or s["rfilename"] == f))
' "$file")
  gb=$(( ${bytes:-0} / 1000000000 ))
  if [ "${bytes:-0}" -eq 0 ]; then
    echo "??   ${repo}${file:+/$file} — size unknown (private, wrong URL, or HF unreachable)"; rc=1; continue
  fi
  verdict="fits"
  if [ $(( gb + HEADROOM_GB )) -gt "$GPU_CEILING_GB" ]; then
    verdict="TOO BIG for the GPU ceiling on its own"; rc=1
  elif [ $(( gb + HEADROOM_GB )) -gt $(( GPU_CEILING_GB - ${resident_gb%.*} )) ]; then
    verdict="fits only with bench.sh --evict (not beside the current roles)"
  fi
  printf '%4s GB  %s%s — %s\n' "$gb" "$repo" "${file:+/$file}" "$verdict"
  total=$(( total + gb ))
done
echo
echo "Candidates total: ${total} GB on disk (weights only; KV cache at 64K adds several GB per slot)."
[ -n "$free_gb" ] && [ "$total" -gt "$free_gb" ] && { echo "NOT ENOUGH DISK"; rc=1; }

if [ "$PULL" -ne 1 ]; then
  echo "Nothing downloaded. Re-run with --pull."
  exit "$rc"
fi
[ "$rc" -eq 0 ] || { echo "Refusing to pull: fix the problems above first."; exit 1; }
for url in "$@"; do
  echo "lms get ${url}"
  "$HEARTH_LMS" get "$url" -y </dev/null || { echo "  FAILED — if 'WebSocket connection closed', see docs/RUNBOOK.md (first-time setup, step 3)"; rc=1; }
done
exit "$rc"
