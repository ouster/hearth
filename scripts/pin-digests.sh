#!/bin/bash
# Record and verify the digest behind every local role.
#
#   scripts/pin-digests.sh           record current digests (after a bench)
#   scripts/pin-digests.sh --check   compare live against recorded, exit 1 on drift
#
# Ollama tags are MUTABLE POINTERS, not versions. `ollama pull qwen3-coder:30b`
# fetches whatever that tag points at today, which may be a different
# quantisation than the one you benched. Nothing warns you.
#
# Ollama has no way to pin a tag to a digest in the model name, so "pinning"
# here means RECORD + DETECT, not enforce: we store the digest that was in place
# when the role was blessed, and fail loudly when the live one differs. That is
# weaker than true pinning and it is the strongest thing available.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"
ai_python_or_die || exit 2

CFG="${ROOT}/litellm/config.yaml"
PINS="${ROOT}/pins/digests.tsv"
MODE="${1:-record}"

live_models() {
  "$AI_PY" - "$CFG" <<'PY'
import sys, yaml
cfg = yaml.safe_load(open(sys.argv[1])) or {}
for m in cfg.get('model_list', []):
    t = m['litellm_params']['model']
    if t.startswith(('ollama/', 'ollama_chat/')):
        print(m['model_name'] + "\t" + t.split('/', 1)[1])
PY
}

digest_of() {
  ollama list 2>/dev/null | awk -v n="$1" 'NR>1 && ($1==n || $1==n":latest"){print $2; exit}'
}

if [ "$MODE" = "--check" ]; then
  if [ ! -f "$PINS" ]; then
    echo "no pins recorded — run scripts/pin-digests.sh"
    exit 2
  fi
  drift=0; missing=0
  while IFS=$'\t' read -r role model; do
    [ -z "${role:-}" ] && continue
    live="$(digest_of "$model")"
    pinned=$(awk -F'\t' -v m="$model" '$2==m{print $3; exit}' "$PINS")
    if [ -z "$live" ]; then
      printf '  %-12s %-24s NOT PULLED\n' "$role" "$model"; missing=$((missing+1))
    elif [ -z "$pinned" ]; then
      printf '  %-12s %-24s no pin recorded\n' "$role" "$model"; missing=$((missing+1))
    elif [ "$live" != "$pinned" ]; then
      printf '  %-12s %-24s DRIFT  pinned=%s live=%s\n' "$role" "$model" "$pinned" "$live"
      drift=$((drift+1))
    else
      printf '  %-12s %-24s ok  %s\n' "$role" "$model" "$live"
    fi
  done <<< "$(live_models)"

  echo
  if [ "$drift" -gt 0 ]; then
    echo "${drift} role(s) drifted — the weights changed under a benched role."
    echo "Re-bench, then re-record with: scripts/pin-digests.sh"
    exit 1
  fi
  [ "$missing" -gt 0 ] && { echo "${missing} role(s) unpinned or unpulled"; exit 2; }
  echo "all roles match their recorded digest"
  exit 0
fi

# ---------------------------------------------------------------- record
mkdir -p "$(dirname "$PINS")"
TODAY="$(date +%Y-%m-%d)"
TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT

{
  echo "# role	model	digest	recorded"
  echo "# Written by scripts/pin-digests.sh. Ollama tags are mutable pointers;"
  echo "# this records what was in place when each role was blessed so drift is"
  echo "# detectable. scripts/preflight.sh checks it."
} > "$TMP"

n=0
while IFS=$'\t' read -r role model; do
  [ -z "${role:-}" ] && continue
  d="$(digest_of "$model")"
  if [ -z "$d" ]; then
    echo "  SKIP ${role} -> ${model} (not pulled)"
    continue
  fi
  printf '%s\t%s\t%s\t%s\n' "$role" "$model" "$d" "$TODAY" >> "$TMP"
  printf '  %-12s %-24s %s\n' "$role" "$model" "$d"
  n=$((n+1))
done <<< "$(live_models)"

mv "$TMP" "$PINS"
echo
echo "recorded ${n} role(s) to pins/digests.tsv — commit this"
