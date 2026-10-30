#!/bin/bash
# Kill an Ollama MLX runner that has accepted a prompt and produced no tokens
# while sitting on a graphics footprint the 64 GB Mac cannot spare.
#
#   scripts/mlx-watchdog.sh            # one check (what launchd runs)
#   scripts/mlx-watchdog.sh --apply    # install the launchd agent
#   scripts/mlx-watchdog.sh --check
#   scripts/mlx-watchdog.sh --remove
#
# A healthy 64K load of local-big is ~26 GB. The stall we hit was mlx_eval
# blocked in MetalAllocator::malloc at a 38–43 GB footprint, with the prompt
# received and zero bytes sent back. ollama stop then sat on "Stopping…".
# See ADR 0015.
#
# False positive: a real prefill that is also silent and ≥38 GB for 30 s
# gets killed too. That is the trade for not waiting out an allocator hang.

set -uo pipefail

LABEL="com.hearth.mlx-watchdog"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
LOG="${HOME}/Library/Logs/hearth-mlx-watchdog.log"
STATE="${TMPDIR:-/tmp}/hearth-mlx-watchdog.state"
# Gigabytes of process footprint (footprint(1)), not `ollama ps` SIZE.
LIMIT_GB=38
# Seconds the prompt must sit with no output before a kill.
STALL_S=30
# Ignore a runner that just started; weight load is not a stall.
MIN_AGE_S=45

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >> "$LOG"
}

etime_s() {
  # ps etime: [[dd-]hh:]mm:ss
  local e="$1" d h m s
  d=0; h=0
  case "$e" in
    *-*) d="${e%%-*}"; e="${e#*-}" ;;
  esac
  case "$e" in
    *:*:*)
      h="${e%%:*}"
      e="${e#*:}"
      m="${e%%:*}"
      s="${e#*:}"
      ;;
    *:*)
      m="${e%%:*}"
      s="${e#*:}"
      ;;
    *)
      printf '0'
      return
      ;;
  esac
  # Strip leading zeros so 08 is not octal.
  d=$((10#$d)); h=$((10#$h)); m=$((10#$m)); s=$((10#$s))
  printf '%s' $((d * 86400 + h * 3600 + m * 60 + s))
}

footprint_gb() {
  local pid="$1" line n unit
  line=$(footprint -p "$pid" 2>/dev/null | awk '/Footprint:/ {print; exit}')
  n=$(printf '%s' "$line" | awk '{print $(NF-1)}')
  unit=$(printf '%s' "$line" | awk '{print $NF}')
  case "$unit" in
    GB) printf '%s' "$n" ;;
    MB) printf '%s' $((n / 1024)) ;;
    *) printf '0' ;;
  esac
}

# Largest received connection on the runner. Prints "rx tx".
data_bytes() {
  local pid="$1" port rx tx best_rx best_tx
  best_rx=0
  best_tx=0
  port=$(lsof -nP -p "$pid" -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {print $9; exit}')
  port="${port##*:}"
  [ -n "$port" ] || { printf '0 0'; return; }
  # netstat -anv: rxbytes is field 7, txbytes field 8. See the header.
  while read -r rx tx; do
    [ -n "$rx" ] || continue
    if [ "$rx" -gt "$best_rx" ] 2>/dev/null; then
      best_rx=$rx
      best_tx=$tx
    fi
  done <<EOF
$(netstat -anv -p tcp 2>/dev/null | awk -v p=".${port}" '
  $4 ~ p"$" && $6 == "ESTABLISHED" { print $7, $8 }
')
EOF
  printf '%s %s' "$best_rx" "$best_tx"
}

check_once() {
  local pid etime age gb rx tx now first
  pid=$(ps -axo pid=,etime=,command= | awk '/ollama runner/ && !/awk/ {print $1; exit}')
  if [ -z "${pid:-}" ]; then
    rm -f "$STATE"
    return 0
  fi
  etime=$(ps -o etime= -p "$pid" | tr -d ' ')
  age=$(etime_s "$etime")
  gb=$(footprint_gb "$pid")
  if [ "${gb:-0}" -lt "$LIMIT_GB" ] || [ "${age:-0}" -lt "$MIN_AGE_S" ]; then
    rm -f "$STATE"
    return 0
  fi
  # shellcheck disable=SC2086
  set -- $(data_bytes "$pid")
  rx="${1:-0}"
  tx="${2:-0}"
  # No prompt yet, or tokens are flowing.
  if [ "$rx" -lt 10000 ] || [ "$tx" -gt 0 ]; then
    rm -f "$STATE"
    return 0
  fi
  now=$(date +%s)
  first=$now
  if [ -f "$STATE" ]; then
    read -r first oldpid < "$STATE" || first=$now
    if [ "${oldpid:-}" != "$pid" ]; then
      first=$now
    fi
  fi
  printf '%s %s\n' "$first" "$pid" > "$STATE"
  if [ $((now - first)) -lt "$STALL_S" ]; then
    return 0
  fi
  log "killing runner ${pid}: footprint ${gb} GB, rx ${rx}, tx ${tx}, age ${age}s"
  kill "$pid" 2>/dev/null || true
  sleep 2
  if ps -p "$pid" >/dev/null 2>&1; then
    kill -9 "$pid" 2>/dev/null || true
    log "kill -9 ${pid}"
  fi
  rm -f "$STATE"
}

case "${1:-}" in
  --check)
    echo "mlx watchdog"
    echo "  limit      : ${LIMIT_GB} GB footprint, tx=0 for ${STALL_S}s, age ≥ ${MIN_AGE_S}s"
    echo "  log        : ${LOG}"
    if [ -f "$PLIST" ]; then
      launchctl print "gui/$(id -u)/${LABEL}" >/dev/null 2>&1 \
        && echo "  launchd    : loaded" || echo "  launchd    : installed, not loaded"
    else
      echo "  launchd    : not installed"
    fi
    ;;
  --apply)
    mkdir -p "${HOME}/Library/LaunchAgents" "${HOME}/Library/Logs"
    abs=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
    cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${abs}</string>
    </array>
    <key>StartInterval</key>
    <integer>15</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${LOG}</string>
    <key>StandardErrorPath</key>
    <string>${LOG}</string>
</dict>
</plist>
EOF
    launchctl unload "$PLIST" 2>/dev/null || true
    launchctl load "$PLIST"
    echo "loaded ${LABEL} (every 15s)"
    ;;
  --remove)
    launchctl unload "$PLIST" 2>/dev/null || true
    rm -f "$PLIST"
    echo "removed ${LABEL}"
    ;;
  "")
    check_once
    ;;
  *)
    echo "usage: $0 [--check|--apply|--remove]" >&2
    exit 1
    ;;
esac
