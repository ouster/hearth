#!/bin/bash
# Install the loop guard (scripts/loop-guard.sh, ADR 0036, 0043) as a global
# PreToolUse hook / OpenCode plugin, so it covers repos other than this one.
#
#   scripts/install-loop-guard.sh            # install / update
#   scripts/install-loop-guard.sh --check    # report, change nothing
#   scripts/install-loop-guard.sh --remove
#
# Writes three places, all pointing at this checkout's loop-guard.sh:
#   Cline:    ~/Documents/Cline/Hooks/PreToolUse
#   VS Code:  ~/.copilot/hooks/hearth-loop-guard.json  (Copilot harness user path)
#   OpenCode: ~/.config/opencode/plugins/hearth-loop-guard/index.js
# VS Code's Local harness may not read ~/.copilot/hooks. If a repo shows no
# guard, add that folder to `chat.hookFilesLocations` (docs/IDES.md).
# OpenCode discovers ~/.config/opencode/plugins/ at startup; restart OpenCode
# after install.
#
# Never overwrites a file it did not write: those carry no hearth marker.
# Exit 0 installed / removed, 1 missing or stale (--check) or refused,
# 2 could not run.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="${ROOT}/scripts/loop-guard.sh"
CLINE_HOOK="${CLINE_HOOKS_GLOBAL:-$HOME/Documents/Cline/Hooks}/PreToolUse"
VSCODE_HOOK="${COPILOT_HOME:-$HOME/.copilot}/hooks/hearth-loop-guard.json"
OPENCODE_PLUGIN="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}/plugins/hearth-loop-guard/index.js"
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
opencode_body() {
  # Absolute GUARD path so a reduced PATH cannot miss the script.
  # Escapes for embedding in a JS string literal.
  local g
  g=$(printf '%s' "$GUARD" | sed 's/\\/\\\\/g; s/"/\\"/g')
  cat <<EOF
// ${MARK} (ADR 0043). Written by scripts/install-loop-guard.sh.
import { spawnSync } from "node:child_process"

const MARK = "${MARK}"
const GUARD = process.env.HEARTH_LOOP_GUARD || "${g}"

function check(tool, args, sessionID) {
  if (!tool) return
  const input = JSON.stringify({
    session_id: sessionID || "opencode",
    tool_name: tool,
    tool_input: args && typeof args === "object" ? args : {},
  })
  const r = spawnSync(GUARD, ["--format", "opencode"], {
    input,
    encoding: "utf8",
    timeout: 5000,
    env: {
      ...process.env,
      PATH: \`/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:\${process.env.PATH || ""}\`,
    },
  })
  if (r.error || r.status !== 0) return
  let out
  try {
    out = JSON.parse((r.stdout || "").trim() || "{}")
  } catch {
    return
  }
  if (out.allow === false) {
    throw new Error(out.errorMessage || \`\${MARK}: denied\`)
  }
}

function before(input, output) {
  const tool = input?.tool || input?.toolName || ""
  const args = output?.args ?? input?.args ?? input?.tool_input ?? {}
  const sid = input?.sessionID || input?.sessionId || input?.session_id || ""
  check(tool, args, sid)
}

export const HearthLoopGuard = async () => ({
  "tool.execute.before": before,
})

export default {
  id: "hearth-loop-guard",
  name: MARK,
  server() {
    return { "tool.execute.before": before }
  },
  async setup(ctx) {
    if (!ctx?.tool?.hook) return
    await ctx.tool.hook("execute.before", (event) => {
      check(event?.tool, event?.input ?? event?.args, event?.sessionID)
    })
  },
}
EOF
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
      elif grep -qF "$MARK" "$path"; then
        rm -f "$path"
        echo "removed ${path}"
        # Drop empty plugin dir left behind.
        rmdir "$(dirname "$path")" 2>/dev/null || true
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
one "$OPENCODE_PLUGIN" "$(opencode_body)" 644
exit "$rc"
