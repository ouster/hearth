#!/bin/bash
# Brake for agent loops (ADR 0036, 0043). Runs as a PreToolUse hook in
# VS Code (Local or Copilot harness) and Cline, and via an OpenCode plugin
# that shells out here. It reads the hook's JSON on stdin and answers in
# that client's format:
#
#   - the same tool call (name + arguments) HEARTH_LOOP_REPEAT times in a
#     row (default 3): the call is denied, and the reason tells the model
#     to stop repeating itself and ask the operator. Cline has no deny
#     without stopping, so there the task stops. OpenCode's plugin throws
#     the errorMessage and the tool never runs.
#   - more than HEARTH_LOOP_BUDGET tool calls in one session (default 80):
#     the run is stopped (OpenCode: same throw).
#
#   scripts/loop-guard.sh --format vscode   < hook.json
#   scripts/loop-guard.sh --format cline    < hook.json
#   scripts/loop-guard.sh --format opencode < hook.json
#   scripts/loop-guard.sh --self-test
#
# --workspace marks the copy wired into this repo (.github/hooks,
# .clinerules/hooks). When scripts/install-loop-guard.sh is installed too,
# both copies run for each call. Whichever runs second sees the same call
# logged by the other copy under 3 seconds ago, and allows it without
# counting it again.
#
# State: one file of call hashes per session under
# ${TMPDIR}/hearth-loop-guard. It resets after HEARTH_LOOP_IDLE_MIN idle
# minutes (default 30). The log records the tool name and a hash only,
# never the arguments: ~/Library/Logs/hearth-loop-guard.log
#
# Fails open. If jq is missing or the input cannot be read, the call is
# allowed. This is a brake, not a security control (ADR 0007).
#
# Exit 0 always, because VS Code denies a call when a hook errors. The
# self-test exits 1 on failure.

set -uo pipefail
case ":${PATH:-}:" in
  *:/opt/homebrew/bin:*) ;;
  *) PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}" ;;
esac

FORMAT="vscode"
SELF_TEST=0
SRC=global
while [ $# -gt 0 ]; do
  case "$1" in
    --format) FORMAT="${2:-vscode}"; shift ;;
    --format=*) FORMAT="${1#--format=}" ;;
    --self-test) SELF_TEST=1 ;;
    --workspace) SRC=workspace ;;
  esac
  shift
done

REPEAT="${HEARTH_LOOP_REPEAT:-3}"
BUDGET="${HEARTH_LOOP_BUDGET:-80}"
IDLE_MIN="${HEARTH_LOOP_IDLE_MIN:-30}"
STATE_ROOT="${HEARTH_LOOP_STATE:-${TMPDIR:-/tmp}/hearth-loop-guard}"
LOG="${HEARTH_LOOP_LOG:-$HOME/Library/Logs/hearth-loop-guard.log}"

allow() {
  case "$FORMAT" in
    cline) printf '{"cancel": false}\n' ;;
    opencode) jq -cn '{allow: true}' ;;
    *) printf '{}\n' ;;
  esac
  exit 0
}

# usage: block deny|stop "<reason>"
# VS Code: the deny goes both top-level (Copilot harness) and in
# hookSpecificOutput (Local harness). "stop" adds continue:false.
# OpenCode: the plugin throws errorMessage for both deny and stop.
block() {
  local kind="$1" reason="$2"
  log "$kind" "$reason"
  case "$FORMAT" in
    cline)
      jq -cn --arg r "$reason" '{cancel: true, errorMessage: $r}' ;;
    opencode)
      jq -cn --arg r "$reason" '{allow: false, errorMessage: $r}' ;;
    *)
      jq -cn --arg r "$reason" --arg k "$kind" '
        {permissionDecision: "deny", permissionDecisionReason: $r,
         hookSpecificOutput: {hookEventName: "PreToolUse",
           permissionDecision: "deny", permissionDecisionReason: $r}}
        + (if $k == "stop" then {continue: false, stopReason: $r} else {} end)' ;;
  esac
  exit 0
}

log() {
  mkdir -p "$(dirname "$LOG")" 2>/dev/null || return 0
  printf '%s %s %s session=%s tool=%s hash=%s: %s\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" "$FORMAT" "$1" "${SID:-?}" "${TOOL:-?}" "${HASH:-?}" "$2" \
    >> "$LOG" 2>/dev/null || true
}

guard() {
  command -v jq >/dev/null 2>&1 || allow
  local input f total distinct
  input="$(cat)"
  [ -n "$input" ] || allow

  # Every documented stdin shape (ADR 0036). Unknown shape → allow.
  TOOL="$(printf '%s' "$input" | jq -r '
    .tool_name // .toolName // .tool_call.name // .preToolUse.toolName // empty' 2>/dev/null)" || allow
  [ -n "$TOOL" ] || allow
  local args
  args="$(printf '%s' "$input" | jq -cS '
    .tool_input // .toolArgs // .tool_call.input // .preToolUse.parameters // null' 2>/dev/null)" || args="null"
  SID="$(printf '%s' "$input" | jq -r '
    .session_id // .sessionId // .taskId // .task_id // .preToolUse.taskId // empty' 2>/dev/null)" || SID=""
  [ -n "$SID" ] || SID="ppid${PPID}-$(pwd | cksum | cut -d' ' -f1)"
  SID="$(printf '%s' "$SID" | tr -c 'A-Za-z0-9._-' '_' | cut -c1-80)"
  HASH="$(printf '%s\n%s' "$TOOL" "$args" | cksum | cut -d' ' -f1)"

  ( umask 077; mkdir -p "$STATE_ROOT" ) 2>/dev/null || allow
  f="${STATE_ROOT}/${SID}"
  if [ -f "$f" ] && [ -n "$(find "$f" -mmin +"$IDLE_MIN" 2>/dev/null)" ]; then
    rm -f "$f"
  fi
  # Same call from the other copy (global vs workspace) a moment ago: the
  # one call, seen twice. Allow it uncounted.
  now=$(date +%s)
  last="$(tail -n 1 "$f" 2>/dev/null)"
  if [ -n "$last" ]; then
    set -- $last
    if [ "$1" = "$HASH" ] && [ "${2:-}" != "$SRC" ] && [ $(( now - ${3:-0} )) -lt 3 ]; then
      allow
    fi
  fi
  printf '%s %s %s\n' "$HASH" "$SRC" "$now" >> "$f" 2>/dev/null || allow

  total=$(wc -l < "$f" | tr -d ' ')
  if [ "$total" -gt "$BUDGET" ]; then
    block stop "Hearth loop guard: ${total} tool calls this session, over the budget of ${BUDGET}. Stop, summarise what is done and what is left, and ask the operator how to continue."
  fi
  if [ "$total" -ge "$REPEAT" ]; then
    distinct=$(tail -n "$REPEAT" "$f" | cut -d' ' -f1 | sort -u | wc -l | tr -d ' ')
    if [ "$distinct" -eq 1 ]; then
      block deny "Hearth loop guard: this exact ${TOOL} call has been made ${REPEAT} times in a row. Do not repeat it. State what you expected, what happened, and the options, then ask the operator."
    fi
  fi
  allow
}

self_test() {
  local tmp out fail=0 i
  tmp="$(mktemp -d)" || exit 1
  export HEARTH_LOOP_STATE="$tmp/state" HEARTH_LOOP_LOG="$tmp/log" HEARTH_LOOP_REPEAT=3 HEARTH_LOOP_BUDGET=4
  local me="${BASH_SOURCE[0]}"
  check() { # usage: check <label> <format> <json> <pattern> [extra arg]
    out="$(printf '%s' "$3" | "$me" --format "$2" ${5:-})"
    if printf '%s' "$out" | grep -q "$4"; then
      echo "ok     $1"
    else
      echo "FAIL   $1: got ${out}"; fail=1
    fi
  }
  local v='{"session_id":"t1","tool_name":"read_file","tool_input":{"path":"a"}}'
  check "vscode: 1st call allowed" vscode "$v" '^{}$'
  check "vscode: 2nd call allowed" vscode "$v" '^{}$'
  check "vscode: 3rd identical call denied" vscode "$v" '"permissionDecision":"deny"'
  check "vscode: different call allowed" vscode '{"session_id":"t1","tool_name":"read_file","tool_input":{"path":"b"}}' '^{}$'
  check "vscode: over budget stops" vscode '{"session_id":"t1","tool_name":"x","tool_input":{}}' '"continue":false'
  local c='{"taskId":"t2","preToolUse":{"toolName":"execute_command","parameters":{"command":"ls"}}}'
  check "cline: 1st call allowed" cline "$c" '"cancel": false'
  check "cline: 2nd call allowed" cline "$c" '"cancel": false'
  check "cline: 3rd identical call cancels" cline "$c" '"cancel":true'
  local o='{"session_id":"t5","tool_name":"read","tool_input":{"filePath":"a"}}'
  check "opencode: 1st call allowed" opencode "$o" '"allow":true'
  check "opencode: 2nd call allowed" opencode "$o" '"allow":true'
  check "opencode: 3rd identical call denied" opencode "$o" '"allow":false'
  check "copilot camelCase shape read" vscode '{"sessionId":"t3","toolName":"edit","toolArgs":"{}"}' '^{}$'
  check "unknown shape allowed" vscode '{"hello":1}' '^{}$'
  check "empty input allowed" cline '' '"cancel": false'
  check "log holds no arguments" vscode "$v" '"permissionDecision":"deny"'
  local w='{"session_id":"t4","tool_name":"read_file","tool_input":{"path":"w"}}'
  check "global + workspace, call 1 (global)" vscode "$w" '^{}$'
  check "global + workspace, call 1 (workspace): not counted" vscode "$w" '^{}$' --workspace
  check "global + workspace, call 2 (global)" vscode "$w" '^{}$'
  check "global + workspace, call 2 (workspace): not counted" vscode "$w" '^{}$' --workspace
  check "global + workspace, call 3 (global): denied" vscode "$w" '"permissionDecision":"deny"'
  if grep -q '"path"' "$tmp/log" 2>/dev/null; then echo "FAIL   log contains tool arguments"; fail=1; fi
  rm -rf "$tmp"
  [ "$fail" -eq 0 ] && echo "loop-guard self-test passed" || echo "loop-guard self-test FAILED"
  exit "$fail"
}

[ "$SELF_TEST" -eq 1 ] && self_test
guard
