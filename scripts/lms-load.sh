#!/bin/bash
# Load exactly the LM Studio roles in config/roles.tsv. Idempotent.
#
#   scripts/lms-load.sh           # unload anything unlisted, load each role
#   scripts/lms-load.sh --check   # report drift only, change nothing
#
# Each `lmstudio` row is loaded with --identifier <role>, so clients ask for
# the role name, never a model. model_key is the modelKey from `lms ls
# --json`, with @variant (e.g. @f16) when several quantisations are on disk;
# `lms load` does not accept a file path.
# slots > 1 becomes --parallel (concurrent predictions is a load flag in
# llmster 0.0.27). No --ttl: a resident role never auto-unloads.
#
# Exit 0 in sync, 1 drift (--check) or a load failed, 2 could not run.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROLES="${ROOT}/config/roles.tsv"
LMS="${LMS:-$HOME/.lmstudio/bin/lms}"
CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

[ -x "$LMS" ] || { echo "could not run: lms not found at $LMS" >&2; exit 2; }
[ -f "$ROLES" ] || { echo "could not run: $ROLES missing" >&2; exit 2; }
"$LMS" daemon status >/dev/null 2>&1 || { echo "could not run: LM Studio is not running (open the app; do not start headless llmster)" >&2; exit 2; }

# role<TAB>key<TAB>ctx<TAB>slots for lmstudio rows.
want=$(awk -F'\t' '!/^[[:space:]]*(#|$)/ && $2 == "lmstudio" {print $1 "\t" $3 "\t" $4 "\t" $5}' "$ROLES")
[ -n "$want" ] || { echo "could not run: no lmstudio rows in $ROLES" >&2; exit 2; }

# identifier<TAB>path<TAB>modelKey<TAB>ctx<TAB>parallel for loaded models.
loaded() {
  "$LMS" ps --json 2>/dev/null | /usr/bin/python3 -I -c '
import json, sys
try:
    rows = json.load(sys.stdin)
except ValueError:
    sys.exit(2)
for m in rows:
    print("\t".join(str(m.get(k) if m.get(k) is not None else "") for k in
                    ("identifier", "path", "modelKey", "contextLength", "parallel")))
'
}

have=$(loaded) || { echo "could not run: lms ps --json unreadable" >&2; exit 2; }
rc=0

# Unload anything not listed.
while IFS="$(printf '\t')" read -r id _ _ _ _; do
  [ -n "$id" ] || continue
  if ! printf '%s\n' "$want" | awk -F'\t' -v r="$id" '$1 == r {f=1} END {exit !f}'; then
    if [ "$CHECK" = 1 ]; then
      echo "DRIFT  ${id}: loaded but not in roles.tsv"; rc=1
    else
      echo "unload ${id} (not in roles.tsv)"
      "$LMS" unload "$id" >/dev/null 2>&1 || { echo "FAIL   unload ${id}"; rc=1; }
    fi
  fi
done <<EOF
$have
EOF

while IFS="$(printf '\t')" read -r role key ctx slots; do
  [ -n "$role" ] || continue
  cur=$(printf '%s\n' "$have" | awk -F'\t' -v r="$role" '$1 == r')
  if [ -n "$cur" ]; then
    cpath=$(printf '%s' "$cur" | cut -f2)
    ckey=$(printf '%s' "$cur" | cut -f3)
    cctx=$(printf '%s' "$cur" | cut -f4)
    cpar=$(printf '%s' "$cur" | cut -f5)
    [ -n "$cpar" ] || cpar=1
    if { [ "$cpath" = "$key" ] || [ "$ckey" = "$key" ]; } && [ "$cctx" = "$ctx" ] && [ "$cpar" = "$slots" ]; then
      echo "ok     ${role}: ctx ${ctx}, ${slots} slot(s)"
      continue
    fi
    if [ "$CHECK" = 1 ]; then
      echo "DRIFT  ${role}: loaded ${cpath} ctx ${cctx} parallel ${cpar}; want ${key} ctx ${ctx} parallel ${slots}"
      rc=1; continue
    fi
    echo "reload ${role}: settings differ"
    "$LMS" unload "$role" >/dev/null 2>&1 || true
  elif [ "$CHECK" = 1 ]; then
    echo "DRIFT  ${role}: not loaded"; rc=1; continue
  fi
  par=()
  [ "$slots" -gt 1 ] 2>/dev/null && par=(--parallel "$slots")
  echo "load   ${role}: ctx ${ctx}, ${slots} slot(s)"
  if ! "$LMS" load "$key" --identifier "$role" -c "$ctx" --gpu max ${par[@]+"${par[@]}"} -y </dev/null >/dev/null 2>&1; then
    echo "FAIL   load ${role}"; rc=1
  fi
done <<EOF
$want
EOF

if [ "$CHECK" = 0 ] && [ "$rc" = 0 ]; then
  # Keep Zed's model-picker labels in step with what is loaded. Best effort:
  # a missing Zed config must not fail a load.
  [ -x "${ROOT}/scripts/zed-sync.sh" ] && "${ROOT}/scripts/zed-sync.sh" >/dev/null 2>&1 || true
  # Re-read: a load that returns 0 and loads nothing is the failure to catch.
  exec "$0" --check
fi
exit "$rc"
