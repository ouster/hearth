#!/bin/bash
# Make the stack survive a reboot, and stop the Studio sleeping out from under
# the laptops.
#
#   scripts/install-autostart.sh --check     what is and is not set up
#   scripts/install-autostart.sh --apply     install the launchd agent
#   scripts/install-autostart.sh --remove
#
# Power settings need sudo, so they are PRINTED rather than run. A script that
# silently changes when your machine sleeps is not a script you want.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"

LABEL="$(ai_boot_label)"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"

ok()  { printf '  \033[32mOK\033[0m    %s\n' "$1"; }
gap() { printf '  \033[33mGAP\033[0m   %s\n' "$1"; }

check() {
  echo "What survives a reboot:"
  echo

  launchctl print "$(ai_litellm_agent)" >/dev/null 2>&1 \
    && ok "LiteLLM — launchd agent ($(ai_litellm_label)), KeepAlive" \
    || gap "LiteLLM — launchd agent not loaded (expected $(ai_litellm_label))"

  if [ -f "$HOME/Library/LaunchAgents/com.user.setollamahost.plist" ]; then
    ok "OLLAMA_HOST — set at login (localhost binding survives)"
  else
    gap "OLLAMA_HOST — not set at login; Ollama may reopen on all interfaces"
  fi

  if [ -f "$HOME/Library/LaunchAgents/$(ai_ollama_label).plist" ]; then
    ok "Ollama — launchd service ($(ai_ollama_label)), KeepAlive"
  elif osascript -e 'tell application "System Events" to get the name of every login item' 2>/dev/null | grep -qi ollama; then
    ok "Ollama — opens at login (app)"
  else
    gap "Ollama — no service and not a login item: scripts/install-ollama-service.sh --apply"
  fi

  if [ -f "$PLIST" ]; then
    ok "podman + containers — boot agent installed"
  else
    gap "podman machine — does NOT start itself. Everything containerised stays down"
  fi

  echo
  echo "Sleep:"
  if command -v pmset >/dev/null 2>&1; then
    s=$(pmset -g custom 2>/dev/null | awk '/^AC Power/,0' | awk '/ sleep/ {print $2; exit}')
    w=$(pmset -g custom 2>/dev/null | awk '/^AC Power/,0' | awk '/womp/ {print $2; exit}')
    [ "${s:-1}" = "0" ] && ok "system sleep disabled on AC" \
                        || gap "system sleep after ${s:-?} min — laptops lose the gateway"
    [ "${w:-0}" = "1" ] && ok "wake on network access enabled" \
                        || gap "wake on network disabled — a sleeping Studio stays asleep"
  fi
}

case "${1:---check}" in
  --check) check ;;

  --apply)
    cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${ROOT}/scripts/boot.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${HOME}/Library/Logs/hearth-boot.log</string>
    <key>StandardErrorPath</key>
    <string>${HOME}/Library/Logs/hearth-boot.log</string>
</dict>
</plist>
EOF
    launchctl unload "$PLIST" 2>/dev/null
    launchctl load "$PLIST" 2>/dev/null
    echo "installed ${PLIST}"
    echo "log: ~/Library/Logs/hearth-boot.log"
    echo
    echo "Running it now to confirm it works:"
    bash "${ROOT}/scripts/boot.sh"
    echo
    cat <<'EOF'
-------------------------------------------------------------
 Two things this script will NOT do for you
-------------------------------------------------------------

1. Ollama at boot

   The menu-bar app has no dependable "open at login" on every build, so
   run the server as a service instead:

     scripts/install-ollama-service.sh --apply

   That also puts OLLAMA_HOST in the plist, which makes the localhost
   binding deterministic rather than depending on a GUI app reading an
   environment variable — the thing that failed the first time round.

2. Sleep, which needs sudo

   A sleeping Studio means every laptop loses the gateway. On a desktop
   on mains power there is little reason to sleep:

     sudo pmset -c sleep 0        # never sleep on AC
     sudo pmset -c disksleep 0    # keep the disk spun up
     sudo pmset -a womp 1         # wake on network access

   `womp` is the interesting one: with it, a laptop reaching the Studio
   can wake it rather than failing. Without it, asleep means unavailable.

   Displays can still sleep — that costs nothing:
     sudo pmset -c displaysleep 10

   To undo: sudo pmset -c sleep 10
EOF
    ;;

  --remove)
    launchctl unload "$PLIST" 2>/dev/null
    rm -f "$PLIST"
    echo "removed ${PLIST}"
    echo "Power settings unchanged — revert manually with: sudo pmset -c sleep 10"
    ;;

  *) echo "usage: $0 {--check|--apply|--remove}"; exit 1 ;;
esac
