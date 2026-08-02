#!/bin/bash
# Phase 3 — bind Ollama to localhost so the gateway is the only way in.
#
#   scripts/lock-ollama.sh --check     what is the current exposure (read-only)
#   scripts/lock-ollama.sh --apply     bind to 127.0.0.1 and verify
#   scripts/lock-ollama.sh --revert    back to all interfaces
#
# BREAKING: other machines on the LAN lose direct access to :11434 and must be
# repointed at the gateway on :4000 with the `lan` key. See the end of --apply.
#
# Ollama defaults to 0.0.0.0:11434 with NO authentication of any kind. On a
# shared network that means any device can use the GPU, read the model list,
# and bypass every routing rule, spend cap and privacy scope in this stack.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"

PLIST="$HOME/Library/LaunchAgents/com.user.setollamahost.plist"
LABEL="com.user.setollamahost"
BIND="127.0.0.1:11434"

check() {
  local ip; ip="$(ai_lan_ip)"
  echo "Current exposure:"
  echo "  launchctl OLLAMA_HOST : $(launchctl getenv OLLAMA_HOST || echo '<unset — defaults to 0.0.0.0:11434>')"
  echo -n "  listening             : "
  lsof -nP -iTCP:11434 -sTCP:LISTEN 2>/dev/null | awk 'NR>1{print $9}' | tr '\n' ' '; echo

  echo -n "  localhost reachable   : "
  curl -s -m 3 -o /dev/null "http://127.0.0.1:11434/api/tags" && echo "yes" || echo "NO"

  if [ -n "$ip" ]; then
    echo -n "  LAN (${ip}) reachable : "
    if curl -s -m 3 -o /dev/null "http://${ip}:11434/api/tags" 2>/dev/null; then
      echo "YES  <-- open to the whole network, no auth"
    else
      echo "no   <-- good"
    fi
  fi
}

case "${1:---check}" in
  --check) check ;;

  --apply)
    echo "Binding Ollama to ${BIND}"
    echo

    # Mirrors the pattern already used by com.user.setollamamodels.plist.
    cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/launchctl</string>
        <string>setenv</string>
        <string>OLLAMA_HOST</string>
        <string>${BIND}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF
    echo "  wrote ${PLIST}"

    launchctl unload "$PLIST" 2>/dev/null
    launchctl load "$PLIST" 2>/dev/null
    launchctl setenv OLLAMA_HOST "$BIND"
    echo "  set OLLAMA_HOST=${BIND} for this session and at login"

    cat <<'EOF'

  TWO controls, and the app one wins.

  macOS GUI apps do not inherit shell environment, so Ollama added an in-app
  network toggle. It overrides OLLAMA_HOST. Setting the variable alone does
  nothing to the running app — which is why this step is manual.

    1. Ollama menu-bar icon -> Settings
    2. Turn OFF "Expose Ollama to the network" (local only)
    3. Quit Ollama completely, then reopen it

  The launchctl variable set above still matters: it governs `ollama serve`
  started from a terminal, and survives reboots.

EOF
    read -r -p "  Press Enter once the toggle is off and Ollama has restarted... " _

    echo
    for _ in $(seq 1 15); do
      curl -s -m 2 -o /dev/null "http://127.0.0.1:11434/api/tags" && break
      sleep 1
    done

    echo "After:"
    check

    ip="$(ai_lan_ip)"
    if [ -n "$ip" ] && curl -s -m 3 -o /dev/null "http://${ip}:11434/api/tags" 2>/dev/null; then
      cat <<'EOF'

STILL EXPOSED — and if OLLAMA_HOST reads 127.0.0.1:11434 above while the
listener still shows *:11434, the in-app toggle is the thing overriding it.

  Ollama menu-bar icon -> Settings -> turn OFF network exposure
  Then Quit (not just close the window) and reopen.

Confirm it actually quit: `pgrep -l ollama` should return nothing before you
relaunch. A lingering server process keeps the old binding.
EOF
      exit 1
    fi

    cat <<EOF

Done. Ollama is now local-only.

LAN machines must be repointed at the gateway. On each one:

  export OPENAI_API_BASE=http://${ip:-<LAN-IP>}:4000/v1
  export OPENAI_API_KEY=<the lan key from litellm/.env>

They then address roles — local-chat, local-code, local-big, cloud-cheap —
rather than model names, and their usage is logged and capped.

Verify from another machine:
  curl http://${ip:-<LAN-IP>}:11434/api/tags          # should now FAIL
  curl http://${ip:-<LAN-IP>}:4000/v1/models \\
    -H "Authorization: Bearer <lan key>"       # should list roles
EOF
    ;;

  --revert)
    launchctl unload "$PLIST" 2>/dev/null
    rm -f "$PLIST"
    launchctl unsetenv OLLAMA_HOST
    echo "Reverted. Restart Ollama.app, then re-run --check."
    ;;

  *) echo "usage: $0 {--check|--apply|--revert}"; exit 1 ;;
esac
