#!/bin/bash
# Install the loop guard (scripts/loop-guard.sh, ADR 0036) as a global
# PreToolUse hook, so it covers repos other than this one.
#
#   scripts/install-loop-guard.sh            # install / update
#   scripts/install-loop-guard.sh --check    # report, change nothing
#   scripts/install-loop-guard.sh --remove
#
# Writes two files, both pointing at this checkout's loop-guard.sh:
#   Cline:   ~/Documents/Cline/Hooks/PreToolUse
#   VS Code: ~/.copilot/hooks/hearth-loop-guard.json  (Copilot harness user path)
# VS Code's Local harness may not read ~/.copilot/hooks. If a repo shows no
# guard, add that folder to `chat.hookFilesLocations` (docs/IDES.md).
#
# Never overwrites a file it did not write: those carry no hearth marker.
# Exit 0 installed / removed, 1 missing or stale (--check) or refused,
# 2 could not run.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="${ROOT}/scripts/loop-guard.sh"
CLINE_HOOK="${CLINE_HOOKS_GLOBAL:-$HOME/Documents/Cline/Hooks}/PreToolUse"
VSCODE_HOOK="${COPILOT_HOME:-$HOME/.copilot}/hooks/hearth-loop-guard.json"
MARK="hearth loop guard"
MODE="install"
case "${1:-}" in
  --check) MODE="check" ;;
  --remove) MODE="remove" ;;
  "") ;;
  *) echo "usage: $0 [--check|--remove]"; exit 2 ;;
esac

[ -x "$GUARD" ] || { echo "could not run: ${GUARD} missing or not executable"; exit 2; }

cline_body() {
  printf '#!/bin/bash\n# %s (ADR 0036). Written by scripts/install-loop-guard.sh.\nexec "%s" --format cline\n' "$MARK" "$GUARD"
}
vscode_body() {
  # JSON has no comments; the marker is the hook's own description field.
  jq -n --arg c "\"${GUARD}\" --format vscode" --arg m "$MARK" \
    '{version: 1, description: $m, hooks: {PreToolUse: [{type: "command", command: $c, timeout: 5}]}}'
}

rc=0
# usage: one <path> <body> <mode-bits>
one() {
  local path="$1" body="$2" bits="$3"
  case "$MODE" in
    check)
      if [ ! -f "$path" ]; then echo "MISSING ${path}"; rc=1
      elif [ "$(cat "$path")" = "$body" ]; then echo "ok      ${path}"
      else echo "STALE   ${path} — run scripts/install-loop-guard.sh"; rc=1; fi ;;
    remove)
      if [ ! -f "$path" ]; then echo "absent  ${path}"
      elif grep -qF "$MARK" "$path"; then rm -f "$path"; echo "removed ${path}"
      else echo "REFUSED ${path}: not written by this script"; rc=1; fi ;;
    install)
      if [ -f "$path" ] && ! grep -qF "$MARK" "$path"; then
        echo "REFUSED ${path}: exists and was not written by this script"; rc=1; return
      fi
      mkdir -p "$(dirname "$path")" || { echo "could not create $(dirname "$path")"; rc=2; return; }
      printf '%s\n' "$body" > "$path" && chmod "$bits" "$path" && echo "wrote   ${path}" ;;
  esac
}

command -v jq >/dev/null 2>&1 || { echo "could not run: jq not found"; exit 2; }
one "$CLINE_HOOK" "$(cline_body)" 755
one "$VSCODE_HOOK" "$(vscode_body)" 644
exit "$rc"
