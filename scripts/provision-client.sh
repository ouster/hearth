#!/bin/bash
# Provision another machine on the LAN to use this gateway.
#
# Run this on the GATEWAY HOST for real values (key + this host's LAN IP):
#
#   scripts/provision-client.sh lan            # local roles + cloud-cheap
#   scripts/provision-client.sh lan-cloud      # wider scope: adds the cloud roles
#   scripts/provision-client.sh lan --install user@laptop
#   scripts/provision-client.sh lan --windows  # PowerShell instructions
#
# On a laptop clone (or anywhere), print the same shape with placeholders:
#
#   scripts/provision-client.sh lan --example
#
# The client needs no Ollama, no models, no Podman. Inference stays on the
# gateway host; the laptop only sends requests.
#
# Both keys are for LAN clients. The difference between them is how much CLOUD
# they can reach, not where they can be used from. (Reachability of :4000 is
# what actually bounds them — there is no IP ACL on the key.)

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"
ai_load_env "$ROOT"

WINDOWS=false
EXAMPLE=false
INSTALL_TARGET=""
SCOPE=""
prev=""
for a in "$@"; do
  case "$a" in
    --windows) WINDOWS=true ;;
    --example) EXAMPLE=true ;;
    --install) prev="--install" ;;
    lan|lan-cloud)
      if [ -z "$SCOPE" ]; then SCOPE="$a"; else
        echo "usage: $0 {lan|lan-cloud} [--example] [--install user@host] [--windows]" >&2
        exit 1
      fi
      ;;
    *)
      if [ "$prev" = "--install" ]; then
        INSTALL_TARGET="$a"
        prev=""
      else
        echo "usage: $0 {lan|lan-cloud} [--example] [--install user@host] [--windows]" >&2
        exit 1
      fi
      ;;
  esac
done
SCOPE="${SCOPE:-lan}"

case "$SCOPE" in
  lan)  KEY_VAR=LITELLM_LAN_KEY;       DESC="local roles + cloud-cheap" ;;
  lan-cloud) KEY_VAR=LITELLM_LAN_CLOUD_KEY; DESC="local roles + all live cloud roles" ;;
  *) echo "usage: $0 {lan|lan-cloud} [--example] [--install user@host] [--windows]" >&2; exit 1 ;;
esac

# Are we on the gateway host?
_label="$(ai_litellm_label)"
_uid="$(id -u)"
_is_host=false
if [ "$(_hearth_env HEARTH_PROVISION_FORCE AI_STACK_PROVISION_FORCE)" = "1" ]; then
  _is_host=true
elif launchctl print "gui/${_uid}/${_label}" >/dev/null 2>&1; then
  _is_host=true
elif [ -f "$HOME/Library/LaunchAgents/${_label}.plist" ]; then
  _is_host=true
elif curl -s -m 2 -o /dev/null "http://127.0.0.1:4000/health/readiness" 2>/dev/null; then
  _is_host=true
fi
unset _label _uid

if ! $_is_host; then
  if [ -n "$INSTALL_TARGET" ]; then
    cat <<'EOF' >&2
--install needs the gateway host (key + this machine's LAN IP).

On the gateway host:
  scripts/provision-client.sh lan --install user@laptop

For placeholder copy-paste on this machine:
  scripts/provision-client.sh lan --example
EOF
    exit 1
  fi
  # Laptop / fresh clone: always show the template (same as --example).
  EXAMPLE=true
fi

if $EXAMPLE; then
  KEY="<${KEY_VAR}>"
  LANIP="<LAN-IP>"
  SCP_USER="<user>"
  HOST_REPO_REMOTE="<hearth-repo>"
  GATEWAY="http://${LANIP}:4000"
  BANNER_NOTE="EXAMPLE — placeholders only. On the gateway host, omit --example for real values."
else
  eval "KEY=\"\${${KEY_VAR}:-}\""
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
  SCP_USER="$(whoami)"
  HOST_REPO_REMOTE="${ROOT}"
  case "$ROOT" in
    "$HOME"/*) HOST_REPO_REMOTE="~${ROOT#"$HOME"}" ;;
  esac
  BANNER_NOTE=""
fi

if [ -n "$INSTALL_TARGET" ]; then
  TARGET="$INSTALL_TARGET"
  echo "Installing to ${TARGET}..."
  scp "${ROOT}/client/hearth-client.sh" "${TARGET}:~/.hearth-client.sh" || exit 1
  # Key via stdin — never on the ssh argv (visible in ps on both ends).
  printf '%s' "$KEY" | ssh "$TARGET" 'cat > ~/.hearth-key && chmod 600 ~/.hearth-key' || exit 1
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
${BANNER_NOTE:+
${BANNER_NOTE}
}

Three ways, easiest first.

A. WSL or Git Bash — the .sh works unchanged
   Follow the normal instructions: scripts/provision-client.sh ${SCOPE}${EXAMPLE:+ --example}

B. Native PowerShell (5.1 or 7+, no WSL needed)

   1. Copy the client
      scp ${SCP_USER}@${LANIP}:${HOST_REPO_REMOTE}/client/hearth-client.ps1 \$HOME\.hearth-client.ps1

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
  ssh -N -L 4000:127.0.0.1:4000 ${SCP_USER}@${LANIP}
  \$env:HEARTH_GATEWAY = "http://127.0.0.1:4000"
EOF
exit 0
fi

cat <<EOF
=============================================================
 hearth client setup — ${SCOPE} key (${DESC})
=============================================================
${BANNER_NOTE:+
${BANNER_NOTE}
}

Run these ON THE LAPTOP. Works on macOS (zsh) and Linux (bash).

1. Install the client shim

   scp ${SCP_USER}@${LANIP}:${HOST_REPO_REMOTE}/client/hearth-client.sh ~/.hearth-client.sh

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
   ask-chat "say hello"     # one-shot via the gateway (no aider)

5. Optional — aider (repo editing; OPENAI_* are already set by the shim)

   pipx install aider-chat      # or: pip install --user aider-chat
   aider                        # uses openai/local-code from ~/.aider.conf.yml

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
laptop, not billing. Check usage from the gateway host with:
  scripts/usage.sh --keys

If this laptop is lost or the key leaks, rotate it on the gateway host:
  scripts/create-keys.sh --force
then re-run this script and reinstall on the machines you keep.

-------------------------------------------------------------
 Privacy note
-------------------------------------------------------------
Traffic between this laptop and the gateway is plain HTTP on your
LAN. Fine at home; do NOT use it on cafe or hotel wifi. For that,
tunnel over SSH instead:

  ssh -N -L 4000:127.0.0.1:4000 ${SCP_USER}@${LANIP}
  export HEARTH_GATEWAY=http://127.0.0.1:4000

and never port-forward :4000 to the internet.
EOF

if $EXAMPLE && ! $_is_host; then
  cat <<'EOF'

-------------------------------------------------------------
 Getting real values
-------------------------------------------------------------
On the gateway host (Studio):
  scripts/provision-client.sh lan

That fills in the LAN IP, SSH user, repo path, and the live key.
EOF
fi
