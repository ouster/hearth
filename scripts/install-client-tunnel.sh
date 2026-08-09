#!/bin/bash
# Permanent SSH tunnel from this laptop to the gateway host (:4000 only).
#
#   scripts/install-client-tunnel.sh --check
#   scripts/install-client-tunnel.sh --apply
#   scripts/install-client-tunnel.sh --remove
#
# Run on the LAPTOP. Creates ~/.ssh/config Host studio (if missing), a launchd
# agent that runs `ssh -N studio`, and tells you to point HEARTH_GATEWAY at
# http://127.0.0.1:4000.
#
# Overrides:
#   HEARTH_SSH_HOST          SSH Host alias (default: studio)
#   HEARTH_STUDIO_HOSTNAME   HostName (default: 192.168.50.154)
#   HEARTH_STUDIO_USER       User (default: colinnevin)
#   HEARTH_STUDIO_IDENTITY   IdentityFile (default: ~/.ssh/id_rsa)

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"

SSH_HOST="${HEARTH_SSH_HOST:-studio}"
STUDIO_HOSTNAME="${HEARTH_STUDIO_HOSTNAME:-192.168.50.154}"
STUDIO_USER="${HEARTH_STUDIO_USER:-colinnevin}"
STUDIO_IDENTITY="${HEARTH_STUDIO_IDENTITY:-~/.ssh/id_rsa}"

LABEL="com.hearth.tunnel"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
SSH_CONFIG="${HOME}/.ssh/config"
AGENT="gui/$(id -u)/${LABEL}"
LOG_OUT="${HOME}/Library/Logs/hearth-tunnel.log"
LOG_ERR="${HOME}/Library/Logs/hearth-tunnel.error.log"

ok()  { printf '  \033[32mOK\033[0m    %s\n' "$1"; }
gap() { printf '  \033[33mGAP\033[0m   %s\n' "$1"; }
bad() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; }

host_stanza_present() {
  [ -f "$SSH_CONFIG" ] || return 1
  grep -Eq "^Host[[:space:]]+([^[:space:]]+[[:space:]]+)*${SSH_HOST}([[:space:]]|$)" "$SSH_CONFIG"
}

host_has_local_forward() {
  [ -f "$SSH_CONFIG" ] || return 1
  # Rough: LocalForward 4000 appears somewhere after Host <alias> and before the next Host.
  awk -v h="$SSH_HOST" '
    $1 == "Host" {
      inhost = 0
      for (i = 2; i <= NF; i++) if ($i == h) inhost = 1
      next
    }
    inhost && $1 == "LocalForward" && $2 == "4000" { found = 1; exit }
    END { exit found ? 0 : 1 }
  ' "$SSH_CONFIG"
}

ensure_ssh_dir() {
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
}

ensure_host_stanza() {
  ensure_ssh_dir
  if host_stanza_present; then
    if ! host_has_local_forward; then
      cat <<EOF >&2
Host '${SSH_HOST}' already exists in ${SSH_CONFIG} but has no
  LocalForward 4000 127.0.0.1:4000
Add that line under the Host block (this script will not edit an existing Host).
EOF
      return 1
    fi
    return 0
  fi
  {
    echo ""
    echo "# hearth — gateway tunnel (scripts/install-client-tunnel.sh)"
    echo "Host ${SSH_HOST}"
    echo "  HostName ${STUDIO_HOSTNAME}"
    echo "  User ${STUDIO_USER}"
    echo "  IdentityFile ${STUDIO_IDENTITY}"
    echo "  LocalForward 4000 127.0.0.1:4000"
    echo "  ExitOnForwardFailure yes"
    echo "  ServerAliveInterval 30"
    echo "  ServerAliveCountMax 3"
  } >> "$SSH_CONFIG"
  chmod 600 "$SSH_CONFIG"
  echo "appended Host ${SSH_HOST} to ${SSH_CONFIG}"
}

ssh_batch_ok() {
  ssh -o BatchMode=yes -o ConnectTimeout=5 "$SSH_HOST" true 2>/dev/null
}

agent_loaded() {
  launchctl print "$AGENT" >/dev/null 2>&1
}

gateway_local_up() {
  curl -s -m 3 -o /dev/null "http://127.0.0.1:4000/health/readiness" 2>/dev/null
}

hearth_gateway_hint() {
  cat <<'EOF'

Point the client at the tunnel (not the Studio LAN IP):

  # ~/.zshrc
  export HEARTH_GATEWAY=http://127.0.0.1:4000
  source ~/.hearth-client.sh

Then open a new shell and run: ai-ping
EOF
  gw="${HEARTH_GATEWAY:-}"
  if [ -z "$gw" ]; then
    echo
    echo "HEARTH_GATEWAY is unset in this shell."
  elif [ "$gw" != "http://127.0.0.1:4000" ] && [ "$gw" != "http://localhost:4000" ]; then
    echo
    echo "HEARTH_GATEWAY is currently: ${gw}"
    echo "Change it to http://127.0.0.1:4000 so traffic uses the tunnel."
  fi
}

check() {
  echo "Laptop → Studio SSH tunnel (${SSH_HOST} → ${STUDIO_HOSTNAME}:4000)"
  echo

  if host_stanza_present; then
    if host_has_local_forward; then
      ok "SSH Host ${SSH_HOST} with LocalForward 4000"
    else
      gap "SSH Host ${SSH_HOST} present but missing LocalForward 4000"
    fi
  else
    gap "SSH Host ${SSH_HOST} not in ~/.ssh/config — scripts/install-client-tunnel.sh --apply"
  fi

  if ssh_batch_ok; then
    ok "ssh ${SSH_HOST} (BatchMode) succeeds"
  else
    gap "ssh ${SSH_HOST} failed — Studio awake? Remote Login on? key in authorized_keys?"
  fi

  if [ -f "$PLIST" ]; then
    ok "LaunchAgent plist ${LABEL}"
  else
    gap "LaunchAgent plist missing — scripts/install-client-tunnel.sh --apply"
  fi

  if agent_loaded; then
    ok "launchd agent loaded (${AGENT})"
  else
    gap "launchd agent not loaded"
  fi

  if gateway_local_up; then
    ok "gateway reachable on 127.0.0.1:4000"
  else
    gap "127.0.0.1:4000 not answering — tunnel down or Studio gateway down"
  fi

  gw="${HEARTH_GATEWAY:-}"
  case "$gw" in
    http://127.0.0.1:4000|http://localhost:4000)
      ok "HEARTH_GATEWAY=${gw}"
      ;;
    "")
      gap "HEARTH_GATEWAY unset — export HEARTH_GATEWAY=http://127.0.0.1:4000"
      ;;
    *)
      gap "HEARTH_GATEWAY=${gw} (want http://127.0.0.1:4000 for the tunnel)"
      ;;
  esac
}

apply() {
  ensure_host_stanza || exit 1

  if ! ssh_batch_ok; then
    cat <<EOF >&2
Cannot reach '${SSH_HOST}' with key auth (BatchMode).

Check:
  1. Studio is awake (ADR default HostName: ${STUDIO_HOSTNAME})
  2. System Settings → General → Sharing → Remote Login is on
  3. Your key is in the Studio's ~/.ssh/authorized_keys
  4. Override HostName if DHCP moved it:
       HEARTH_STUDIO_HOSTNAME=x.x.x.x $0 --apply

Test:  ssh -o BatchMode=yes -o ConnectTimeout=5 ${SSH_HOST} true
EOF
    exit 1
  fi

  mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"

  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/ssh</string>
        <string>-N</string>
        <string>${SSH_HOST}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>10</integer>
    <key>StandardOutPath</key>
    <string>${LOG_OUT}</string>
    <key>StandardErrorPath</key>
    <string>${LOG_ERR}</string>
</dict>
</plist>
EOF

  uid="$(id -u)"
  launchctl bootout "gui/${uid}/${LABEL}" 2>/dev/null || launchctl unload "$PLIST" 2>/dev/null || true
  launchctl bootstrap "gui/${uid}" "$PLIST" 2>/dev/null || launchctl load "$PLIST" 2>/dev/null
  launchctl enable "gui/${uid}/${LABEL}" 2>/dev/null || true
  launchctl kickstart -k "gui/${uid}/${LABEL}" 2>/dev/null || true

  echo "installed ${PLIST}"
  echo "logs: ${LOG_OUT}"
  echo "      ${LOG_ERR}"
  echo

  # Give the forward a moment, then probe.
  sleep 2
  if gateway_local_up; then
    ok "gateway answering on 127.0.0.1:4000"
  else
    gap "127.0.0.1:4000 still quiet — check Studio LiteLLM and ${LOG_ERR}"
  fi

  hearth_gateway_hint
}

remove() {
  uid="$(id -u)"
  launchctl bootout "gui/${uid}/${LABEL}" 2>/dev/null || launchctl unload "$PLIST" 2>/dev/null || true
  rm -f "$PLIST"
  echo "removed ${PLIST}"
  echo "SSH Host '${SSH_HOST}' left in ${SSH_CONFIG} — delete that block by hand if you want."
}

case "${1:---check}" in
  --check)  check ;;
  --apply)  apply ;;
  --remove) remove ;;
  *) echo "usage: $0 {--check|--apply|--remove}"; exit 1 ;;
esac
