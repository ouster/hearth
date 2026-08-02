#!/bin/bash
# Install rules/global-rules.md into ~/.claude/CLAUDE.md, and print the text to
# paste into Cursor's user rules.
#
#   scripts/install-global-rules.sh          # install / update
#   scripts/install-global-rules.sh --show   # print, change nothing
#
# Idempotent: the block is delimited by markers, so re-running REPLACES it
# rather than appending a second copy. Anything you wrote outside the markers
# is left alone.
#
# Cursor's global rules are NOT a file — they live in Settings -> Rules ->
# User Rules. This script prints them for pasting; it cannot install them.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${ROOT}/rules/global-rules.md"
DEST="${CLAUDE_GLOBAL:-$HOME/.claude/CLAUDE.md}"

BEGIN="<!-- BEGIN ai-stack global rules -->"
END="<!-- END ai-stack global rules -->"

[ -f "$SRC" ] || { echo "missing ${SRC}"; exit 1; }

if [ "${1:-}" = "--show" ]; then
  cat "$SRC"
  exit 0
fi

mkdir -p "$(dirname "$DEST")"
[ -f "$DEST" ] || : > "$DEST"

# Strip the file's own H1 and the "installed by" preamble — the destination
# already has its own structure.
BODY=$(awk 'NR>1' "$SRC" | awk '/^## /{p=1} p')

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

if grep -qF "$BEGIN" "$DEST" 2>/dev/null; then
  # Replace between the markers, preserving everything else.
  awk -v b="$BEGIN" -v e="$END" '
    index($0,b){skip=1; next}
    index($0,e){skip=0; next}
    !skip{print}
  ' "$DEST" > "$TMP"
  ACTION="updated"
else
  cp "$DEST" "$TMP"
  ACTION="added to"
fi

{
  # Collapse any trailing blank lines, then append one clean block.
  awk 'BEGIN{n=0} {lines[NR]=$0} END{
        last=NR; while (last>0 && lines[last] ~ /^[[:space:]]*$/) last--
        for(i=1;i<=last;i++) print lines[i]
      }' "$TMP"
  [ -s "$TMP" ] && echo
  echo "$BEGIN"
  echo "# Global engineering rules"
  echo
  echo "Source: ~/dev/ai-stack/rules/global-rules.md — edit there, then re-run"
  echo "scripts/install-global-rules.sh. Do not edit between these markers."
  echo
  printf '%s\n' "$BODY"
  echo "$END"
} > "${TMP}.new"

mv "${TMP}.new" "$DEST"
echo "${ACTION} ${DEST}"
echo

cat <<EOF
Cursor does not read a global rules file — its user rules live in the app.

  Cursor -> Settings -> Rules -> User Rules -> paste the block below

Project-level Cursor rules ARE files, and this repo is already covered: Cursor
reads AGENTS.md, which is a symlink to CLAUDE.md.

Print the text to paste with:
  scripts/install-global-rules.sh --show
EOF
