#!/bin/bash
# Record and verify the weights behind every local role (D4).
#
#   scripts/pin-digests.sh                  # record, after a bench you trust
#   scripts/pin-digests.sh --check          # fast: file count, bytes, newest mtime
#   scripts/pin-digests.sh --check --deep   # re-hash everything (~20 GB, ~30 s)
#
# Hashes the `weights` path of this host's rows in config/roles.tsv (its RAM
# tier, ADR 0032) under ~/.hearth/models. Records are keyed by weights path, so
# hosts on different tiers share one file; recording keeps other tiers' rows.
# sha256 of every file, then sha256 of the sorted "path sha" list. Written to
# pins/digests.tsv, git-tracked, so drift shows in a diff. preflight.sh runs
# the fast check.
#
# This detects; it does not enforce. oMLX loads whatever is on disk.
# Re-record only after re-benching.
#
# Exit 0 match / recorded, 1 drift, 2 could not run.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"

PINS="${ROOT}/pins/digests.tsv"
MODELS="$HOME/.hearth/models"
weight_path() {
  printf '%s\n' "${MODELS}/${1}"
}
MODE=record; DEEP=0
for a in "$@"; do
  case "$a" in
    --check) MODE=check ;;
    --deep)  DEEP=1 ;;
    *) echo "usage: $0 [--check [--deep]]"; exit 2 ;;
  esac
done
# --deep alone used to fall through to record and bless whatever is on disk.
if [ "$DEEP" -eq 1 ] && [ "$MODE" != "check" ]; then
  echo "usage: $0 --check --deep" >&2
  echo "--deep re-hashes. It does not record. Recording is the default, with no flags, after a bench you trust." >&2
  exit 2
fi

# Prints: files<TAB>bytes<TAB>newest_mtime for a file or directory.
quick() {
  find "$1" -type f ! -name '.DS_Store' -print0 \
    | xargs -0 stat -f '%z %m' \
    | awk '{n++; b+=$1; if ($2>m) m=$2} END {printf "%d\t%d\t%d\n", n, b, m}'
}

# Prints the combined sha256 for a file or directory.
deep() {
  local p="$1"
  if [ -f "$p" ]; then
    shasum -a 256 "$p" | awk '{print $1}'
  else
    (cd "$p" && find . -type f ! -name '.DS_Store' | LC_ALL=C sort \
       | while IFS= read -r f; do printf '%s %s\n' "$f" "$(shasum -a 256 "$f" | awk '{print $1}')"; done) \
      | shasum -a 256 | awk '{print $1}'
  fi
}

rows=$(hearth_roles omlx)
[ -n "$rows" ] || { echo "could not run: no omlx rows in config/roles.tsv fit this host's RAM tier (ADR 0032)"; exit 2; }

if [ "$MODE" = record ]; then
  tmp=$(mktemp)
  {
    echo "# role	model_key	weights	files	bytes	newest_mtime	sha256	recorded"
    echo "# Written by scripts/pin-digests.sh (D4). Hash of the weights on disk"
    echo "# under ~/.hearth/models. Detects drift; does not enforce."
  } > "$tmp"
  # Keep records for weights this host does not serve (other tiers), and for
  # an optional role whose weights are not installed here.
  mine=""
  while IFS="$(printf '\t')" read -r role _ _ _ _ w; do
    [ -n "$role" ] || continue
    if [ -e "$(weight_path "$w")" ] || ! hearth_role_optional "$role"; then mine="${mine}${w}|"; fi
  done <<EOF
$rows
EOF
  if [ -f "$PINS" ]; then
    awk -F'\t' -v mine="$mine" 'BEGIN { n = split(mine, a, "|"); for (i = 1; i <= n; i++) if (a[i] != "") m[a[i]] = 1 }
      !/^#/ && NF && !($3 in m)' "$PINS" >> "$tmp"
  fi
  while IFS="$(printf '\t')" read -r role _ key _ _ w; do
    [ -n "$role" ] || continue
    p="$(weight_path "$w")"
    if [ ! -e "$p" ] && hearth_role_optional "$role"; then echo "skip ${role}: not installed (optional)"; continue; fi
    [ -n "$w" ] && [ "$w" != "-" ] && [ -e "$p" ] || { echo "could not run: ${role}: weights '${w}' not found under ${MODELS}"; rm -f "$tmp"; exit 2; }
    printf 'hashing %s (%s)… ' "$role" "$w"
    q=$(quick "$p"); h=$(deep "$p")
    echo "${h:0:12}"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$role" "$key" "$w" "$q" "$h" "$(date +%Y-%m-%d)" >> "$tmp"
  done <<EOF
$rows
EOF
  mkdir -p "$(dirname "$PINS")"; mv "$tmp" "$PINS"
  echo "recorded → pins/digests.tsv"
  exit 0
fi

[ -f "$PINS" ] || { echo "could not run: ${PINS} missing (record first)"; exit 2; }
rc=0
while IFS="$(printf '\t')" read -r role _ key _ _ w; do
  [ -n "$role" ] || continue
  rec=$(awk -F'\t' -v w="$w" '!/^#/ && $3 == w' "$PINS" | head -1)
  if [ -z "$rec" ]; then echo "DRIFT  ${role}: ${w} not recorded"; rc=1; continue; fi
  if [ "$(printf '%s' "$rec" | cut -f2,3)" != "$(printf '%s\t%s' "$key" "$w")" ]; then
    echo "DRIFT  ${role}: roles.tsv now ${key} / ${w}; recorded $(printf '%s' "$rec" | cut -f2,3 | tr '\t' ' ')"; rc=1; continue
  fi
  p="$(weight_path "$w")"
  if [ ! -e "$p" ]; then
    if hearth_role_optional "$role"; then echo "skip   ${role}: not installed (optional)"
    else echo "DRIFT  ${role}: weights missing at ${p}"; rc=1; fi
    continue
  fi
  want_q=$(printf '%s' "$rec" | cut -f4-6); got_q=$(quick "$p")
  if [ "$want_q" != "$got_q" ]; then
    echo "DRIFT  ${role}: files/bytes/mtime changed (recorded $(printf '%s' "$want_q" | tr '\t' '/'), now $(printf '%s' "$got_q" | tr '\t' '/'))"; rc=1; continue
  fi
  if [ "$DEEP" -eq 1 ]; then
    want_h=$(printf '%s' "$rec" | cut -f7); got_h=$(deep "$p")
    [ "$want_h" = "$got_h" ] || { echo "DRIFT  ${role}: sha256 ${got_h:0:12} ≠ recorded ${want_h:0:12}"; rc=1; continue; }
    echo "ok     ${role}: sha256 ${got_h:0:12} matches"
  else
    echo "ok     ${role}: files, bytes and mtime match (scripts/pin-digests.sh --check --deep re-hashes)"
  fi
done <<EOF
$rows
EOF
exit "$rc"
