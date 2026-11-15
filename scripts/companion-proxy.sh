#!/usr/bin/env bash
set -euo pipefail
# companion-proxy.sh — Launchd plist for model-proxy.py
# Run as: sudo scripts/companion-proxy.sh install
# Uninstall as: sudo scripts/companion-proxy.sh uninstall

PLIST_PATH="/Library/LaunchDaemons/com.hearth.model-proxy.plist"

usage() {
  echo "Usage: $0 {install|uninstall|status}"
  exit 1
}

install() {
  local repo_root
  repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  local python3_path
  python3_path="$(which python3)"

  if [[ ! -f "${repo_root}/scripts/model-proxy.py" ]]; then
    echo "ERROR: model-proxy.py not found at ${repo_root}/scripts/"
    exit 1
  fi

  # Create plist in repo (copy to launchd location)
  cat > "${PLIST_PATH}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.hearth.model-proxy</string>
  <key>ProgramArguments</key>
  <array>
    <string>${python3_path}</string>
    <string>${repo_root}/scripts/model-proxy.py</string>
    <string>--port</string>
    <string>1238</string>
    <string>--local</string>
  </array>
  <key>KeepAlive</key>
  <true/>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/var/log/hearth-model-proxy.log</string>
  <key>StandardErrorPath</key>
  <string>/var/log/hearth-model-proxy.err</string>
  <key>AbandonProcessGroup</key>
  <true/>
</dict>
</plist>
PLIST

  chmod 644 "${PLIST_PATH}"
  echo "Installed ${PLIST_PATH}"
  echo "Start with: sudo launchctl load ${PLIST_PATH}"
  echo "Stop with:  sudo launchctl unload ${PLIST_PATH}"
}

uninstall() {
  if [[ -f "${PLIST_PATH}" ]]; then
    sudo launchctl unload "${PLIST_PATH}" 2>/dev/null || true
    sudo rm "${PLIST_PATH}"
    echo "Uninstalled ${PLIST_PATH}"
  else
    echo "Not installed"
  fi
}

status() {
  if [[ -f "${PLIST_PATH}" ]]; then
    echo "Installed at ${PLIST_PATH}"
    launchctl list | grep model-proxy || echo "Not running"
  else
    echo "Not installed"
  fi
}

[[ $# -eq 1 ]] || usage
case "$1" in
  install) install ;;
  uninstall) uninstall ;;
  status) status ;;
  *) usage ;;
esac
