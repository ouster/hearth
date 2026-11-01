#!/bin/bash
# Load or unload a role marked load=demand in config/roles.tsv (ADR 0020).
#
#   scripts/demand-load.sh <role> up            # load beside the resident roles, if it fits
#   scripts/demand-load.sh <role> up --evict    # unload the resident roles first
#   scripts/demand-load.sh <role> down          # unload it; reload resident roles
#
# `up` prints "loaded" or "already". With JIT off, LM Studio answers a
# request for an unloaded role with whatever IS loaded, so `up` confirms the
# role is really loaded before it returns 0.
#
# Memory guard, from the 2026-11-01 measurement (ADR 0020): beside local-main,
# a ~30K-token prompt to this role grew its cache by ~8 GB while local-main's
# own three slots grew by ~8.4 GB, peaking at 49.9 GB — over the ~48 GB
# ceiling, macOS swapped, and local-main's requests timed out while this role
# read its prompt. So without --evict, `up` refuses when LM Studio's
# footprint now + the weights + HEARTH_DEMAND_KV_GB (8) + HEARTH_RESIDENT_GROWTH_GB
# (9) would pass 44 GB (4 GB headroom). With --evict only the first three count.
#
# Exit 0 ok, 1 refused or failed, 2 could not run.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"

ROLE="${1:-}"; ACTION="${2:-}"; EVICT=0
[ "${3:-}" = "--evict" ] && EVICT=1
LIMIT_GB=44
KV_GB="${HEARTH_DEMAND_KV_GB:-8}"
GROWTH_GB="${HEARTH_RESIDENT_GROWTH_GB:-9}"
[ -n "$ROLE" ] && { [ "$ACTION" = up ] || [ "$ACTION" = down ]; } || { sed -n '2,6p' "$0"; exit 2; }
hearth_lms_ok || { echo "could not run: LM Studio not running (scripts/boot.sh)" >&2; exit 2; }
hearth_demand_roles | grep -qxF "$ROLE" || { echo "could not run: ${ROLE} is not a load=demand role in roles.tsv" >&2; exit 2; }

is_loaded() {
  "$HEARTH_LMS" ps --json 2>/dev/null | /usr/bin/python3 -I -c '
import json, sys
sys.exit(0 if any(m.get("identifier") == sys.argv[1] and m.get("modelKey") == sys.argv[2]
                  for m in json.load(sys.stdin)) else 1)' "$ROLE" "$1"
}

if [ "$ACTION" = down ]; then
  "$HEARTH_LMS" unload "$ROLE" >/dev/null 2>&1 || { echo "unload ${ROLE} failed" >&2; exit 1; }
  # Brings local-main back after --evict; a no-op when it never left.
  "${ROOT}/scripts/lms-load.sh" >/dev/null 2>&1 || { echo "lms-load.sh failed — run it by hand" >&2; exit 1; }
  exit 0
fi

row=$(awk -F'\t' -v r="$ROLE" '!/^[[:space:]]*#/ && $1 == r' "${ROOT}/config/roles.tsv")
key=$(printf '%s' "$row" | cut -f3); ctx=$(printf '%s' "$row" | cut -f4); slots=$(printf '%s' "$row" | cut -f5)

if is_loaded "$key"; then echo "already"; exit 0; fi

size=$("$HEARTH_LMS" ls --json 2>/dev/null | /usr/bin/python3 -I -c '
import json, sys
print(next(("%.1f" % (m["sizeBytes"] / 1e9) for m in json.load(sys.stdin) if m.get("modelKey") == sys.argv[1]), ""))' "$key")
[ -n "$size" ] || { echo "could not run: ${key} not downloaded" >&2; exit 2; }

if [ "$EVICT" -eq 1 ]; then
  echo "unloading resident roles for this session (Zed, aider and laptops have no local-main until down)…" >&2
  for r in $(hearth_resident_roles | cut -f1); do "$HEARTH_LMS" unload "$r" >/dev/null 2>&1; done
  GROWTH_GB=0
fi

used=$(hearth_footprint_gb)
if awk -v u="$used" -v s="$size" -v k="$KV_GB" -v g="$GROWTH_GB" -v l="$LIMIT_GB" 'BEGIN {exit !(u + s + k + g > l)}'; then
  echo "not loading ${ROLE}: LM Studio uses ${used} GB; + ${size} GB weights + ${KV_GB} GB cache + ${GROWTH_GB} GB for local-main under load would pass ${LIMIT_GB} GB (~48 GB ceiling, 4 GB headroom)." >&2
  echo "Use --evict to unload local-main for the session (ask-deep always does)." >&2
  exit 1
fi

echo "loading ${ROLE} (${size} GB; LM Studio at ${used} GB)…" >&2
"$HEARTH_LMS" load "$key" --identifier "$ROLE" -c "$ctx" --parallel "$slots" --gpu max -y </dev/null >/dev/null 2>&1
if ! is_loaded "$key"; then
  echo "load ${ROLE} failed — not in lms ps" >&2
  [ "$EVICT" -eq 1 ] && "${ROOT}/scripts/lms-load.sh" >/dev/null 2>&1
  exit 1
fi
echo "loaded"
