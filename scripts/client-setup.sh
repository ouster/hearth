#!/bin/bash
# Print (or install) the setup for another machine on the LAN.
#
#   scripts/client-setup.sh lan            # local roles + cloud-cheap
#   scripts/client-setup.sh lan-cloud      # wider scope: adds the cloud roles
#   scripts/client-setup.sh lan --install user@laptop   # scp and wire it up
#   scripts/client-setup.sh lan --windows               # PowerShell instructions
#
# The client needs no Ollama, no models, no Podman. Everything runs on this
# machine; the laptop just points at the gateway.
#
# Both keys are LAN-ONLY. The difference between them is how much CLOUD they
# can reach, not where they can be used from.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"
ai_load_env "$ROOT"

WINDOWS=false
for a in "$@"; do [ "$a" = "--windows" ] && WINDOWS=true; done

SCOPE="${1:-lan}"
case "$SCOPE" in
  lan)  KEY="${LITELLM_LAN_KEY:-}";  DESC="local roles + cloud-cheap" ;;
  lan-cloud) KEY="${LITELLM_LAN_CLOUD_KEY:-}"; DESC="local roles + all live cloud roles" ;;
  *) echo "usage: $0 {lan|lan-cloud} [--install user@host]"; exit 1 ;;
esac

if [ -z "$KEY" ]; then
  echo "No ${SCOPE} key found in litellm/.env."
  echo "Run scripts/create-keys.sh, then paste the values in."
  exit 1
fi

LANIP="$(ai_lan_ip)"
if [ -z "$LANIP" ]; then
  echo "No LAN IP detected. Connect to a network, or set HEARTH_LAN_IP."
  exit 1
fi
GATEWAY="http://${LANIP}:4000"
# Path on this host as seen by scp (tilde form when under $HOME).
HOST_REPO_REMOTE="${ROOT}"
case "$ROOT" in
  "$HOME"/*) HOST_REPO_REMOTE="~${ROOT#"$HOME"}" ;;
esac

if [ "${2:-}" = "--install" ] && [ -n "${3:-}" ]; then
  TARGET="$3"
  echo "Installing to ${TARGET}..."
  scp "${ROOT}/client/hearth-client.sh" "${TARGET}:~/.hearth-client.sh" || exit 1
  ssh "$TARGET" "printf '%s' '${KEY}' > ~/.hearth-key && chmod 600 ~/.hearth-key"
  ssh "$TARGET" "grep -q hearth-client \$HOME/.zshrc 2>/dev/null || echo 'export HEARTH_GATEWAY=${GATEWAY}; source ~/.hearth-client.sh' >> \$HOME/.zshrc"
  ssh "$TARGET" "grep -q hearth-client \$HOME/.bashrc 2>/dev/null || echo 'export HEARTH_GATEWAY=${GATEWAY}; source ~/.hearth-client.sh' >> \$HOME/.bashrc"
  echo "done. On ${TARGET}: open a new shell, then 'ai-ping' and 'ai-models'."
  exit 0
fi

if $WINDOWS; then
cat <<EOF
=============================================================
 hearth client setup — WINDOWS — ${SCOPE} key (${DESC})
=============================================================

Three ways, easiest first.

A. WSL or Git Bash — the .sh works unchanged
   Follow the normal instructions: scripts/client-setup.sh ${SCOPE}

B. Native PowerShell (5.1 or 7+, no WSL needed)

   1. Copy the client
      scp $(whoami)@${LANIP}:${HOST_REPO_REMOTE}/client/hearth-client.ps1 \$HOME\.hearth-client.ps1

   2. Store the key
      '${KEY}' | Out-File -NoNewline \$HOME\.hearth-key

      Then lock it down (Windows has no chmod):
      icacls \$HOME\.hearth-key /inheritance:r /grant:r "\$env:USERNAME:(R)"

   3. Load it every session
      notepad \$PROFILE
      # add these two lines:
      \$env:HEARTH_GATEWAY = "${GATEWAY}"
      . "\$HOME\.hearth-client.ps1"

      If \$PROFILE does not exist:
      New-Item -ItemType File -Path \$PROFILE -Force

   4. Open a new PowerShell and check
      ai-ping
      ai-models
      ask-chat "say hello"

   Note: if the profile will not load, PowerShell's execution policy is
   blocking it. Per-user fix:
      Set-ExecutionPolicy -Scope CurrentUser RemoteSigned

C. Nothing installed at all — just point any OpenAI-compatible tool at:
      base URL: ${GATEWAY}/v1
      api key:  ${KEY}
      model:    local-chat   (or local-code, local-big, cloud-cheap)

-------------------------------------------------------------
 Same caveats as any client
-------------------------------------------------------------
No Ollama, no models, no containers on this machine — inference happens
on the gateway host. If it is asleep, nothing works.

Traffic is plain HTTP on your LAN. Fine at home, wrong on public wifi.
Off-network, tunnel instead:
  ssh -N -L 4000:127.0.0.1:4000 $(whoami)@${LANIP}
  \$env:HEARTH_GATEWAY = "http://127.0.0.1:4000"
EOF
exit 0
fi

cat <<EOF
=============================================================
 hearth client setup — ${SCOPE} key (${DESC})
=============================================================

Run these ON THE OTHER MACHINE. Works on macOS (zsh) and Linux (bash).

1. Install the client shim

   mkdir -p ~/.local
   scp $(whoami)@${LANIP}:${HOST_REPO_REMOTE}/client/hearth-client.sh ~/.hearth-client.sh

   (or copy the file by any means — it is plain shell, no dependencies)

2. Store the key, readable only by you

   printf '%s' '${KEY}' > ~/.hearth-key
   chmod 600 ~/.hearth-key

3. Wire it into your shell

   # macOS
   echo 'export HEARTH_GATEWAY=${GATEWAY}' >> ~/.zshrc
   echo 'source ~/.hearth-client.sh'       >> ~/.zshrc

   # Linux
   echo 'export HEARTH_GATEWAY=${GATEWAY}' >> ~/.bashrc
   echo 'source ~/.hearth-client.sh'       >> ~/.bashrc

4. Open a new shell and check

   ai-ping                  # is the gateway reachable
   ai-models                # which roles this key may use
   ai-ask "say hello"       # one-shot, no aider needed

5. Optional — aider

   pipx install aider-chat      # or: pip install --user aider-chat
   ask "explain this repo"      # -> local-code, runs on the gateway host

-------------------------------------------------------------
 What this machine does NOT need
-------------------------------------------------------------
No Ollama. No models downloaded. No Podman, no Postgres. Inference
happens on the gateway host; the laptop only sends requests.

If that host is asleep or off, nothing works. That is the trade for
not duplicating tens of GB of weights onto every device.

-------------------------------------------------------------
 Scope of the ${SCOPE} key
-------------------------------------------------------------
${DESC}.

Spend cap applies — it is a fuse against a runaway loop or a lost
laptop, not billing. Check usage from the Studio with:
  scripts/usage.sh --keys

If this laptop is lost or the key leaks, rotate it on the Studio:
  scripts/create-keys.sh --force
then re-run this script and reinstall on the machines you keep.

-------------------------------------------------------------
 Privacy note
-------------------------------------------------------------
Traffic between this laptop and the gateway is plain HTTP on your
LAN. Fine at home; do NOT use it on cafe or hotel wifi. For that,
tunnel over SSH instead:

  ssh -N -L 4000:127.0.0.1:4000 $(whoami)@${LANIP}
  export HEARTH_GATEWAY=http://127.0.0.1:4000

and never port-forward :4000 to the internet.
EOF
