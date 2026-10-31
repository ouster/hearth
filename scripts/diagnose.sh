#!/bin/bash
# Dump what LM Studio actually has, for when healthcheck says something is
# wrong. Read-only. Capture this BEFORE restarting anything — a restart
# destroys the evidence (plan, phase 6).
#
#   scripts/diagnose.sh > /tmp/hearth-diag.txt

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"

sec() { printf '\n===== %s =====\n' "$1"; }

sec "time"; date
sec "daemon owner"; hearth_daemon_owner; echo; "$HEARTH_LMS" daemon status 2>&1 | sed 's/\x1b\[[0-9;]*m//g'
sec "server"; "$HEARTH_LMS" server status 2>&1 | sed 's/\x1b\[[0-9;]*m//g'
sec "listeners :${HEARTH_PORT}"; lsof -nP -iTCP:"$HEARTH_PORT" -sTCP:LISTEN 2>/dev/null
sec "saved server settings"; cat "$LMS_SERVER_CFG" 2>/dev/null; echo
sec "loaded (lms ps --json)"; "$HEARTH_LMS" ps --json 2>/dev/null
sec "roles.tsv drift"; "${ROOT}/scripts/lms-load.sh" --check 2>&1
sec "footprint (GPU memory, not RSS)"
for p in $(pgrep -f '\.lmstudio/|LM Studio'); do
  printf '%-7s %-28s %s\n' "$p" "$(ps -p "$p" -o comm= | awk -F/ '{print $NF}' | cut -c1-28)" \
    "$(footprint -p "$p" 2>/dev/null | grep -o 'Footprint: [0-9.]* [KMG]B' | head -1)"
done
sec "GPU limit"; sysctl iogpu.wired_limit_mb 2>/dev/null
sec "memory pressure"; memory_pressure 2>/dev/null | tail -3
sec "latest server log (last 40 lines)"
lg=$(ls -t "$HOME"/.lmstudio/server-logs/*/* "$HOME"/.lmstudio/server-logs/* 2>/dev/null | head -1)
[ -n "$lg" ] && [ -f "$lg" ] && { echo "$lg"; tail -40 "$lg"; } || echo "(none found — run: lms log stream)"
sec "boot log (last 15)"; tail -15 "$HOME/Library/Logs/hearth-boot.log" 2>/dev/null
echo
echo "Live request stream: lms log stream    Load bench: scripts/concurrency-bench.sh"
