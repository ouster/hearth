#!/bin/bash
# Repoint an LM Studio role at a different model, safely.
#
#   scripts/swap-role.sh <role> <lms model key> <weights path> [ctx] [slots]
#
#   e.g. scripts/swap-role.sh local-big <key from `lms ls`> <dir under ~/.lmstudio/models>
#
# Bench first (scripts/bench.sh, scripts/concurrency-bench.sh) — rule 5. This
# script does the mechanical part and reverts on failure:
#
#   1. the key is downloaded and the weights path exists
#   2. config/roles.tsv row rewritten (ctx/slots kept unless given)
#   3. scripts/lms-load.sh reloads, then re-reads lms ps
#   4. tool-smoke passes against the role (chat roles only)
#
# Any failure restores the previous roles.tsv and reloads it. What it does
# NOT do, and prints for you: docs/MODELS.md, pin-digests, ADR, HISTORY row.
#
# Exit 0 swapped, 1 failed and reverted, 2 could not run.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"
ai_load_env
ROLES="${ROOT}/config/roles.tsv"

ROLE="${1:-}"; KEY="${2:-}"; W="${3:-}"; CTX="${4:-}"; SLOTS="${5:-}"
[ -n "$ROLE" ] && [ -n "$KEY" ] && [ -n "$W" ] || { sed -n '2,4p' "$0"; exit 2; }
hearth_lms_ok || { echo "could not run: LM Studio not running"; exit 2; }

row=$(hearth_roles lmstudio | awk -F'\t' -v r="$ROLE" '$1 == r')
[ -n "$row" ] || { echo "could not run: ${ROLE} is not an lmstudio role in roles.tsv"; exit 2; }
old_key=$(printf '%s' "$row" | cut -f3)
[ -n "$CTX" ]   || CTX=$(printf '%s' "$row" | cut -f4)
[ -n "$SLOTS" ] || SLOTS=$(printf '%s' "$row" | cut -f5)

"$HEARTH_LMS" ls --json 2>/dev/null | grep -qF "\"${KEY}\"" || { echo "could not run: ${KEY} not downloaded (lms get <url> -y)"; exit 2; }
[ -e "$HOME/.lmstudio/models/${W}" ] || { echo "could not run: weights ${W} not under ~/.lmstudio/models"; exit 2; }
[ "$KEY" = "$old_key" ] && [ "$CTX" = "$(printf '%s' "$row" | cut -f4)" ] && [ "$SLOTS" = "$(printf '%s' "$row" | cut -f5)" ] \
  && { echo "nothing to do: ${ROLE} is already ${KEY} ctx ${CTX} slots ${SLOTS}"; exit 0; }

BACKUP=$(mktemp)
cp "$ROLES" "$BACKUP"
revert() {
  echo "REVERTING: restoring roles.tsv and reloading ${old_key}"
  cp "$BACKUP" "$ROLES"
  "${ROOT}/scripts/lms-load.sh" >/dev/null 2>&1 || echo "  lms-load.sh failed after revert — run it by hand"
  rm -f "$BACKUP"
  exit 1
}

awk -F'\t' -v OFS='\t' -v r="$ROLE" -v k="$KEY" -v c="$CTX" -v s="$SLOTS" -v w="$W" \
  '/^[[:space:]]*#/ || $1 != r {print; next} {$3=k; $4=c; $5=s; $6=w; print}' "$BACKUP" > "$ROLES"
echo "roles.tsv: ${ROLE} ${old_key} → ${KEY} (ctx ${CTX}, ${SLOTS} slot(s))"

echo "loading…"
"${ROOT}/scripts/lms-load.sh" || revert

case "$KEY" in
  *embed*) : ;;
  *)
    echo "tool smoke…"
    OPENAI_API_KEY="${LMSTUDIO_HOST_TOKEN:-}" "${ROOT}/scripts/tool-smoke.sh" "$HEARTH_URL" "$ROLE" || revert ;;
esac

rm -f "$BACKUP"
cat <<EOF

Swapped ${ROLE} → ${KEY}. Still yours to do:
  1. docs/MODELS.md — same change, with source repo + revision (rule 1)
  2. scripts/pin-digests.sh — record the new weights (D4)
  3. ADR in docs/decisions/ and a row in docs/HISTORY.md
  4. Delete the old weights only after the new model has proven itself
EOF
