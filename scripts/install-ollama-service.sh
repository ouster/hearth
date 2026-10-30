#!/bin/bash
# Run `ollama serve` as a launchd service instead of depending on Ollama.app.
#
#   scripts/install-ollama-service.sh --check
#   scripts/install-ollama-service.sh --apply
#   scripts/install-ollama-service.sh --remove
#
# Why bother:
#
#   - The menu-bar app has no reliable "open at login" on every build, and a
#     GUI app is the wrong shape for something the whole LAN depends on.
#   - OLLAMA_HOST goes IN THE PLIST, so the localhost binding is deterministic.
#     No more depending on launchctl setenv reaching a GUI process — the thing
#     that cost us a round trip when the app ignored it.
#   - KeepAlive restarts it if it dies.
#
# The CLI (`ollama list`, `ollama pull`) talks to whichever server is on
# :11434, so it keeps working exactly as before.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"

# Fresh installs get com.hearth.ollama; an existing personal label is reused.
LABEL="$(ai_ollama_label)"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
BIND="${OLLAMA_BIND:-127.0.0.1:11434}"
MODELS="${OLLAMA_MODELS:-/Users/Shared/Ollama/models}"
# Memory envelope knobs (ADR 0011). Override via env when re-running --apply.
FLASH="${OLLAMA_FLASH_ATTENTION:-1}"
KV_CACHE="${OLLAMA_KV_CACHE_TYPE:-q8_0}"
MAX_LOADED="${OLLAMA_MAX_LOADED_MODELS:-1}"
# 10m, not -1. A bad first load (native 256K) never expired under -1.
# An in-flight allocator stall is the watchdog's job. ADR 0015.
KEEP_ALIVE="${OLLAMA_KEEP_ALIVE:-10m}"
NUM_PARALLEL="${OLLAMA_NUM_PARALLEL:-1}"

find_ollama() {
  for p in /opt/homebrew/bin/ollama /usr/local/bin/ollama \
           /Applications/Ollama.app/Contents/Resources/ollama \
           "$(command -v ollama 2>/dev/null)"; do
    [ -x "$p" ] && { printf '%s' "$p"; return 0; }
  done
  return 1
}

BIN="$(find_ollama || true)"

case "${1:---check}" in
  --check)
    echo "Ollama service"
    echo
    [ -n "$BIN" ] && echo "  binary       : ${BIN}" || echo "  binary       : NOT FOUND"
    echo "  would bind to: ${BIND}"
    echo "  models dir   : ${MODELS}"
    echo "  flash attn   : ${FLASH}"
    echo "  kv cache     : ${KV_CACHE}"
    echo "  max loaded   : ${MAX_LOADED}"
    echo "  keep alive   : ${KEEP_ALIVE}"
    echo "  num parallel : ${NUM_PARALLEL}"
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
    curl -s -m 3 -o /dev/null "http://127.0.0.1:11434/api/tags" && echo "yes" || echo "no"
    echo -n "  app running  : "
    pgrep -f "Ollama.app" >/dev/null 2>&1 && echo "YES — quit it before --apply" || echo "no"
    ;;

  --apply)
    [ -n "$BIN" ] || { echo "ollama binary not found"; exit 1; }

    if pgrep -f "Ollama.app" >/dev/null 2>&1; then
      echo "Ollama.app is running and would fight the service for :11434."
      echo "Quit it from the menu bar, then re-run this."
      echo "Also untick any 'launch at login' option it does have."
      exit 1
    fi

    mkdir -p "$MODELS" 2>/dev/null
    cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${BIN}</string>
        <string>serve</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>OLLAMA_HOST</key>
        <string>${BIND}</string>
        <key>OLLAMA_MODELS</key>
        <string>${MODELS}</string>
        <key>OLLAMA_FLASH_ATTENTION</key>
        <string>${FLASH}</string>
        <key>OLLAMA_KV_CACHE_TYPE</key>
        <string>${KV_CACHE}</string>
        <key>OLLAMA_MAX_LOADED_MODELS</key>
        <string>${MAX_LOADED}</string>
        <key>OLLAMA_KEEP_ALIVE</key>
        <string>${KEEP_ALIVE}</string>
        <key>OLLAMA_NUM_PARALLEL</key>
        <string>${NUM_PARALLEL}</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>10</integer>
    <key>StandardOutPath</key>
    <string>${HOME}/Library/Logs/ollama.log</string>
    <key>StandardErrorPath</key>
    <string>${HOME}/Library/Logs/ollama.error.log</string>
</dict>
</plist>
EOF
    echo "wrote ${PLIST}"

    launchctl unload "$PLIST" 2>/dev/null
    launchctl load "$PLIST" 2>/dev/null

    printf 'waiting for ollama'
    i=0
    while [ "$i" -lt 30 ]; do
      curl -s -m 2 -o /dev/null "http://127.0.0.1:11434/api/tags" && break
      printf '.'; sleep 1; i=$((i+1))
    done
    echo

    if curl -s -m 3 -o /dev/null "http://127.0.0.1:11434/api/tags"; then
      echo "  responding on 127.0.0.1:11434"
      n=$(ollama list 2>/dev/null | awk 'NR>1' | wc -l | tr -d ' ')
      echo "  models visible: ${n}"
      [ "$n" = "0" ] && echo "  WARNING: no models — is OLLAMA_MODELS right? (${MODELS})"
    else
      echo "  NOT responding — check ~/Library/Logs/ollama.error.log"
      exit 1
    fi

    # The binding is the whole point, so verify it rather than assume.
    LANIP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "")
    if [ -n "$LANIP" ]; then
      if curl -s -m 3 -o /dev/null "http://${LANIP}:11434/api/tags" 2>/dev/null; then
        echo "  *** still reachable on ${LANIP} — binding did not take ***"
        exit 1
      else
        echo "  not reachable from the LAN — correct"
      fi
    fi

    cat <<EOF

Done. Ollama now starts at login as a service, with the localhost binding set
in the plist rather than relying on the app reading an environment variable.

  restart:  launchctl kickstart -k gui/\$(id -u)/${LABEL}
  logs:     tail -f ~/Library/Logs/ollama.error.log

You can still open Ollama.app to browse models, but do not let it start at
login — two servers will fight over :11434.

com.user.setollamahost.plist is now redundant. Harmless, but you can remove it:
  launchctl unload ~/Library/LaunchAgents/com.user.setollamahost.plist
  rm ~/Library/LaunchAgents/com.user.setollamahost.plist
EOF
    ;;

  --remove)
    launchctl unload "$PLIST" 2>/dev/null
    rm -f "$PLIST"
    echo "removed ${PLIST}"
    echo "Ollama will no longer start at login. Open the app, or run 'ollama serve'."
    ;;

  *) echo "usage: $0 {--check|--apply|--remove}"; exit 1 ;;
esac
