#!/bin/bash
# Run Rapid-MLX as a launchd service for local-big (agent / reasoning).
#
#   scripts/install-rapid-mlx-service.sh --check
#   scripts/install-rapid-mlx-service.sh --apply
#   scripts/install-rapid-mlx-service.sh --remove
#
# Serves one MLX model at a time on 127.0.0.1:8000. Default alias matches
# local-big in litellm/config.yaml — see docs/decisions/0012.
#
# bash 3.2 compatible.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"

LABEL="$(ai_rapid_mlx_label)"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
BIND="${RAPID_MLX_BIND:-127.0.0.1}"
PORT="${RAPID_MLX_PORT:-8000}"
ALIAS="${RAPID_MLX_ALIAS:-qwen3.6-35b-4bit}"
RAPID=""

find_rapid() {
  if [ -n "${RAPID_MLX_BIN:-}" ] && [ -x "$RAPID_MLX_BIN" ]; then
    RAPID="$RAPID_MLX_BIN"
    return 0
  fi
  for p in "$(command -v rapid-mlx 2>/dev/null)" \
           "${HOME}/.local/bin/rapid-mlx" \
           /opt/homebrew/bin/rapid-mlx; do
    [ -n "$p" ] && [ -x "$p" ] && { RAPID="$p"; return 0; }
  done
  return 1
}

health_url() {
  printf 'http://%s:%s/v1/models' "$BIND" "$PORT"
}

case "${1:---check}" in
  --check)
    echo "Rapid-MLX service"
    echo
    if find_rapid; then
      echo "  binary       : ${RAPID}"
      "${RAPID}" --version 2>/dev/null | head -1 || true
    else
      echo "  binary       : NOT FOUND (scripts/mlx-bench.sh --install-rapid)"
    fi
    echo "  would serve  : ${ALIAS}"
    echo "  listen       : ${BIND}:${PORT}"
    echo
    if [ -f "$PLIST" ]; then
      echo "  launchd agent: installed"
      launchctl print "gui/$(id -u)/${LABEL}" >/dev/null 2>&1 \
        && echo "  loaded       : yes" || echo "  loaded       : NO"
    else
      echo "  launchd agent: not installed"
    fi
    echo
    echo -n "  responding   : "
    curl -s -m 3 -o /dev/null "$(health_url)" && echo "yes" || echo "no"
    ;;

  --apply)
    find_rapid || {
      echo "rapid-mlx not found — run: scripts/mlx-bench.sh --install-rapid"
      exit 1
    }

    cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${RAPID}</string>
        <string>serve</string>
        <string>${ALIAS}</string>
        <string>--host</string>
        <string>${BIND}</string>
        <string>--port</string>
        <string>${PORT}</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${HOME}/.local/bin</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>30</integer>
    <key>StandardOutPath</key>
    <string>${HOME}/Library/Logs/rapid-mlx.log</string>
    <key>StandardErrorPath</key>
    <string>${HOME}/Library/Logs/rapid-mlx.error.log</string>
</dict>
</plist>
EOF
    echo "wrote ${PLIST}"

    launchctl unload "$PLIST" 2>/dev/null
    launchctl load "$PLIST" 2>/dev/null

    printf 'waiting for rapid-mlx'
    i=0
    while [ "$i" -lt 120 ]; do
      curl -s -m 2 -o /dev/null "$(health_url)" && break
      printf '.'; sleep 2; i=$((i+1))
    done
    echo

    if curl -s -m 3 -o /dev/null "$(health_url)"; then
      echo "  responding on ${BIND}:${PORT}"
      curl -s -m 3 "$(health_url)" 2>/dev/null \
        | "$AI_PY" -c "import sys,json; d=json.load(sys.stdin); print('  models:', [m['id'] for m in d.get('data',[])][:3])" 2>/dev/null \
        || true
    else
      echo "  NOT responding — first load can take minutes. Check:"
      echo "    tail -f ~/Library/Logs/rapid-mlx.error.log"
      exit 1
    fi

    cat <<EOF

Done. Rapid-MLX now starts at login as ${LABEL}.

  restart:  launchctl kickstart -k gui/\$(id -u)/${LABEL}
  logs:     tail -f ~/Library/Logs/rapid-mlx.error.log

local-big routes here via the gateway. Ensure RAPID_MLX_API_KEY is in
~/.config/litellm/env (see litellm/service-env.example), then restart LiteLLM.
EOF
    ;;

  --remove)
    launchctl unload "$PLIST" 2>/dev/null
    rm -f "$PLIST"
    echo "removed ${PLIST}"
    echo "Rapid-MLX will no longer start at login."
    ;;

  *) echo "usage: $0 {--check|--apply|--remove}"; exit 1 ;;
esac
