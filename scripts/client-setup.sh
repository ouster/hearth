#!/bin/bash
# Set up a laptop to use this host's oMLX over an SSH tunnel.
#
#   scripts/client-setup.sh m5-air                       # print the steps
#   scripts/client-setup.sh laptop-m5-air                # same machine
#   scripts/client-setup.sh m5-air --windows             # PowerShell steps
#   scripts/client-setup.sh m5-air --authorize <pub>     # tunnel-only SSH key
#   scripts/client-setup.sh m5-air --install user@laptop # scp the client
#   scripts/client-setup.sh --update-keys                # refresh hearth-tunnel-* lines
#
# The sub-key argument is laptop-<short>, e.g. laptop-m5-air. Pass m5-air or
# laptop-m5-air; a single leading laptop- is stripped. Letters, digits, hyphen,
# underscore. sub-key list prints names only. Already listed: skip add and use
# the laptop's existing ~/.hearth-key. A lost token cannot be reprinted.
#
# The host stays bound to 127.0.0.1 (ADR 0016, phase 4 decision: tunnel only).
# Each laptop gets:
#   - its own host token, laptop-<short> (laptop-m5-air), registered with
#     scripts/omlx.sh sub-key add — revoke one machine without touching
#     the others. A reboot runs scripts/omlx.sh up, which keeps sub-keys
#     already registered.
#   - its own SSH key, authorized here with `restrict` + permitopen + a
#     permitlisten that matches nothing, so that key can forward to
#     127.0.0.1:1234 (oMLX), :3000 (Open WebUI) and :8888 (SearXNG, for a
#     laptop's SearXNG MCP — ADR 0022) and do nothing else — no shell, no -R,
#     no other ports. --update-keys brings an older restriction up to date and
#     keeps only options that narrow access (from=, expiry-time=, no-*);
#     granting ones (pty, agent-forwarding, …) would undo `restrict` and are
#     dropped. A hearth-tunnel-*
#     line with no tunnel restriction is a full shell key: reported, left
#     unchanged, exit 1. Options must not contain spaces.
#   - its own Google API key for ask-cloud. The host holds none (ADR 0038).
#
# Exit 0 ok, 1 failed, 2 could not run.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"

_hearth_setup_usage() {
  cat <<'EOF'
scripts/client-setup.sh m5-air                       # print the steps
scripts/client-setup.sh laptop-m5-air                # same machine
scripts/client-setup.sh m5-air --windows             # PowerShell steps
scripts/client-setup.sh m5-air --authorize <pub>     # tunnel-only SSH key
scripts/client-setup.sh m5-air --install user@laptop # scp the client
scripts/client-setup.sh --update-keys                # refresh hearth-tunnel-* lines

Sub-key argument: laptop-<short>, e.g. laptop-m5-air
  letters, digits, hyphen, underscore.
  Already in sub-key list: skip add. The laptop uses ~/.hearth-key.
  Lost token: sub-key list cannot show it. revoke, then add a new one.
EOF
}

AK="$HOME/.ssh/authorized_keys"
# permitlisten="none:1" is an allowlist entry that no real -R request matches
# (sshd compares the listen host literally; clients send localhost or
# 127.0.0.1). Port 0 is rejected as "invalid permission port" on OpenSSH 10.5,
# so the dummy port is 1. permitopen limits -L only. Without permitlisten,
# port-forwarding re-enables remote forwards.
RESTRICT='command="/usr/bin/false",restrict,port-forwarding,permitopen="127.0.0.1:1234",permitopen="127.0.0.1:3000",permitopen="127.0.0.1:8888",permitlisten="none:1"'
TUNNEL_PREFIX='command="/usr/bin/false",restrict,port-forwarding,'

# Comma-separated options this script does not own, in their original order.
# Quotes can contain commas. Empty if the field is only our restriction.
_hearth_extra_opts() {
  /usr/bin/python3 -I -c '
import sys
s = sys.argv[1]
parts, buf, q = [], [], False
for ch in s:
    if ch == chr(34):
        q = not q
        buf.append(ch)
    elif ch == "," and not q:
        parts.append("".join(buf))
        buf = []
    else:
        buf.append(ch)
if buf:
    parts.append("".join(buf))
# Keep only options that narrow access. Anything after `restrict` that grants
# (pty, agent-forwarding, x11-forwarding, user-rc, environment=, ...) would
# switch that feature back on, so it is dropped.
narrowing_prefix = ("from=", "expiry-time=", "no-")
keep = [p for p in parts if p.startswith(narrowing_prefix)]
sys.stdout.write(",".join(keep))
' "$1"
}

_hearth_opts_new() {
  local extra
  extra=$(_hearth_extra_opts "$1")
  if [ -n "$extra" ]; then
    printf '%s,%s' "$RESTRICT" "$extra"
  else
    printf '%s' "$RESTRICT"
  fi
}

# ---------------------------------------------------------------- --update-keys
# The comment is the last field (hearth-tunnel-<name>, no spaces). A tunnel
# line's first field is the options. Keys are never printed.
if [ "${1:-}" = "--update-keys" ]; then
  [ -f "$AK" ] || { echo "could not run: no ${AK}"; exit 2; }
  umask 077
  tmp=$(mktemp "${AK}.tmp.XXXXXX") || { echo "could not run: mktemp failed"; exit 2; }
  total=0; changed=0; unsafe=0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|'#'*) printf '%s\n' "$line" >> "$tmp"; continue ;;
    esac
    comment="${line##* }"
    case "$comment" in
      hearth-tunnel-*) ;;
      *) printf '%s\n' "$line" >> "$tmp"; continue ;;
    esac
    total=$((total + 1))
    opts="${line%% *}"
    case "$opts" in
      "$TUNNEL_PREFIX"*)
        new=$(_hearth_opts_new "$opts")
        if [ "$opts" = "$new" ]; then
          printf '%s\n' "$line" >> "$tmp"
        else
          printf '%s %s\n' "$new" "${line#* }" >> "$tmp"
          changed=$((changed + 1))
        fi
        ;;
      *)
        printf '%s\n' "$line" >> "$tmp"
        unsafe=$((unsafe + 1))
        ;;
    esac
  done < "$AK"
  if [ "$changed" -eq 0 ]; then
    rm -f "$tmp"
    if [ "$unsafe" -eq 0 ]; then
      echo "all ${total} hearth-tunnel key(s) already have the current restriction"
      exit 0
    fi
    echo "REFUSING: ${unsafe} hearth-tunnel-* line(s) have no tunnel restriction (full shell). Left unchanged."
    exit 1
  fi
  cp -p "$AK" "${AK}.bak-$(date +%Y%m%d%H%M%S)"
  mv "$tmp" "$AK"
  chmod 600 "$AK"
  echo "updated ${changed} of ${total} hearth-tunnel key(s) (extra options kept, backup kept); ${unsafe} full-shell line(s) left unchanged"
  [ "$unsafe" -eq 0 ] || exit 1
  exit 0
fi

NAME="${1:-}"; shift || true
case "$NAME" in
  laptop-*) NAME="${NAME#laptop-}" ;;
esac
case "$NAME" in ''|-*) _hearth_setup_usage; exit 2 ;; esac
case "$NAME" in
  *[!A-Za-z0-9_-]*)
    echo "laptop name: letters, digits, - and _ only (m5-air → sub-key laptop-m5-air)"
    exit 2
    ;;
esac
WINDOWS=0; AUTH=""; INSTALL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --windows)   WINDOWS=1; shift ;;
    --authorize) AUTH="${2:?--authorize needs a public key file or string}"; shift 2 ;;
    --install)   INSTALL="${2:?--install needs user@laptop}"; shift 2 ;;
    *) echo "unknown option $1"; exit 2 ;;
  esac
done

HOSTNAME_LOCAL="$(scutil --get LocalHostName 2>/dev/null || hostname -s).local"
USER_NAME="$(id -un)"
CLOUD_MODEL=$(hearth_roles gemini | awk -F'\t' '$1 == "cloud-cheap" {print $3; exit}')

# ---------------------------------------------------------------- --authorize
if [ -n "$AUTH" ]; then
  pub="$AUTH"; [ -f "$AUTH" ] && pub=$(cat "$AUTH")
  case "$pub" in ssh-ed25519\ *|ecdsa-sha2-*\ *|ssh-rsa\ *) ;; *) echo "not an SSH public key"; exit 2 ;; esac
  keybody=$(printf '%s' "$pub" | awk '{print $1" "$2}')
  mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"; touch "$AK"; chmod 600 "$AK"
  if grep -qF "$keybody" "$AK"; then
    # Any unrestricted copy of this key is a full shell, even if another
    # line already has the current restriction. Do not rewrite those.
    unsafe_copy=0
    needs_update=0
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in *"$keybody"*) ;; *) continue ;; esac
      opts="${line%% *}"
      case "$opts" in
        "$TUNNEL_PREFIX"*)
          [ "$opts" = "$(_hearth_opts_new "$opts")" ] || needs_update=1
          ;;
        *) unsafe_copy=1 ;;
      esac
    done < "$AK"
    if [ "$unsafe_copy" -eq 1 ]; then
      echo "REFUSING: that key is already in ${AK} WITHOUT restrictions (full shell)."
      echo "Generate a separate tunnel key on the laptop (step 2 below) and authorize that."
      exit 1
    fi
    if [ "$needs_update" -eq 0 ]; then
      echo "already authorized (tunnel-only, current restriction) for ${NAME}"; exit 0
    fi
    umask 077
    cp -p "$AK" "${AK}.bak-$(date +%Y%m%d%H%M%S)"
    tmp=$(mktemp "${AK}.tmp.XXXXXX") || exit 1
    while IFS= read -r line || [ -n "$line" ]; do
      if case "$line" in *"$keybody"*) true ;; *) false ;; esac; then
        opts="${line%% *}"
        case "$opts" in
          "$TUNNEL_PREFIX"*)
            new=$(_hearth_opts_new "$opts")
            if [ "$opts" != "$new" ]; then
              printf '%s %s\n' "$new" "${line#* }" >> "$tmp"
              continue
            fi
            ;;
        esac
      fi
      printf '%s\n' "$line" >> "$tmp"
    done < "$AK"
    mv "$tmp" "$AK"
    chmod 600 "$AK"
    echo "updated ${NAME} to the current tunnel-only restriction (extra options kept, backup kept)"
    exit 0
  fi
  cp -p "$AK" "${AK}.bak-$(date +%Y%m%d%H%M%S)"
  printf '%s %s hearth-tunnel-%s\n' "$RESTRICT" "$keybody" "$NAME" >> "$AK"
  echo "authorized tunnel-only key for ${NAME} in ${AK} (backup kept)"
  echo "  can forward to 127.0.0.1:1234, :3000 and :8888; no shell, no commands, no other ports"
  exit 0
fi

# ---------------------------------------------------------------- --install
if [ -n "$INSTALL" ]; then
  src="${ROOT}/client/hearth-client.sh"; dst='~/.hearth-client.sh'
  [ "$WINDOWS" -eq 1 ] && { src="${ROOT}/client/hearth-client.ps1"; dst='.hearth-client.ps1'; }
  scp -q "$src" "${INSTALL}:${dst}" && echo "copied $(basename "$src") → ${INSTALL}:${dst}" || { echo "scp failed"; exit 1; }
  exit 0
fi

# ---------------------------------------------------------------- instructions
[ -n "$CLOUD_MODEL" ] || CLOUD_MODEL="<cloud-cheap id from config/roles.tsv>"
cat <<EOF
Laptop setup: ${NAME}   (host ${USER_NAME}@${HOSTNAME_LOCAL}, tunnel only)
  sub-key add argument: laptop-${NAME}
  SSH key comment:      hearth-tunnel-${NAME}

Letters, digits, hyphen, underscore. Example: m5-air → laptop-m5-air.
scripts/client-setup.sh laptop-${NAME} prints this same page.
Leave oMLX on 127.0.0.1. A reboot runs scripts/omlx.sh up, which keeps
sub-keys already registered.

1. ON THIS HOST — oMLX is listening (scripts/omlx.sh status). Pick one path.

   NEW — laptop-${NAME} is absent from scripts/omlx.sh sub-key list.
   Ask the host user to type a token (the command does not invent one):
     scripts/omlx.sh sub-key add laptop-${NAME}
   The prompt says "paste the token for laptop-${NAME}" and does not echo.
   That same string is stored on the laptop as ~/.hearth-key.
   sub-key list prints the name only. It never prints the token back.

   ALREADY REGISTERED — laptop-${NAME} is in that list.
   Skip sub-key add. A different token fails with
   "sub-key laptop-${NAME} already exists".
   The laptop uses the token already in ~/.hearth-key.
   If that file is gone, the host cannot show the old token. Then:
     scripts/omlx.sh sub-key revoke laptop-${NAME}
     scripts/omlx.sh sub-key add laptop-${NAME}

EOF
if [ "$WINDOWS" -eq 0 ]; then cat <<EOF
2. ON THE LAPTOP — the tunnel SSH key. Pick one path.

   NEW — no ~/.ssh/hearth_tunnel yet:
     ssh-keygen -t ed25519 -f ~/.ssh/hearth_tunnel -C hearth-tunnel-${NAME}
     printf 'Host hearth\n  HostName %s\n  User %s\n  IdentityFile ~/.ssh/hearth_tunnel\n  IdentitiesOnly yes\n  ServerAliveInterval 30\n  ServerAliveCountMax 3\n' "${HOSTNAME_LOCAL}" "${USER_NAME}" >> ~/.ssh/config
   Copy ~/.ssh/hearth_tunnel.pub to this host, then HERE:
     scripts/client-setup.sh ${NAME} --authorize /path/to/hearth_tunnel.pub

   ALREADY AUTHORIZED — the laptop still has ~/.ssh/hearth_tunnel, and
   --authorize prints "already authorized". Leave the key. Skip ssh-keygen.
   If the private key is gone, generate a new one and authorize that .pub.

3. ON THE LAPTOP — the client, from a clone of this repo (do not append
   loose HEARTH_* lines to the rc; the installer writes one marked block):
     client/install-client.sh --host ${USER_NAME}@${HOSTNAME_LOCAL}
   Dual (this laptop also runs a brain on 1234): add --dual, then
   scripts/install-host.sh (docs/LAPTOP.md → *A laptop that is also a host*).
   Store a token only when ~/.hearth-key is missing or this is a new token:
     umask 077
     read -rs t && printf '%s' "\$t" > ~/.hearth-key && unset t        # laptop-${NAME}
     read -rs t && printf '%s' "\$t" > ~/.hearth-gemini-key && unset t # this laptop's OWN Google key (optional)

4. ON THE LAPTOP — prove it, in a new shell. The first ai-tunnel accepts the host fingerprint.
     ai-tunnel            # one ssh -N -L (1234, or 1235 when dual)
     ai-tunnel-install    # macOS: launchd keeps those forwards up, and at login
     ai-ping              # up / BAD TOKEN / NO ANSWER / DOWN
     ai-models            # main-brain
     ask                  # aider on main-brain (ask-remote when dual)
     ask-cloud            # Gemini with the laptop's own key
     ai-webui             # the host's Open WebUI
   Linux: skip ai-tunnel-install. ai-tunnel-stop unloads the LaunchAgent too.
EOF
else cat <<EOF
2. ON THE LAPTOP (PowerShell) — the tunnel SSH key. Pick one path.

   NEW — no \$HOME\\.ssh\\hearth_tunnel yet:
     ssh-keygen -t ed25519 -f \$HOME\\.ssh\\hearth_tunnel -C hearth-tunnel-${NAME}
     Add-Content \$HOME\\.ssh\\config "Host hearth\`n  HostName ${HOSTNAME_LOCAL}\`n  User ${USER_NAME}\`n  IdentityFile ~/.ssh/hearth_tunnel\`n  IdentitiesOnly yes\`n  ServerAliveInterval 30\`n  ServerAliveCountMax 3"
   Copy hearth_tunnel.pub to this host, then HERE:
     scripts/client-setup.sh ${NAME} --authorize /path/to/hearth_tunnel.pub

   ALREADY AUTHORIZED — the laptop still has hearth_tunnel, and --authorize
   prints "already authorized". Leave the key. Skip ssh-keygen.
   If the private key is gone, generate a new one and authorize that .pub.

3. ON THE LAPTOP — the client. Copy it even when the token already exists:
     scp ${USER_NAME}@${HOSTNAME_LOCAL}:${ROOT}/client/hearth-client.ps1 \$HOME\\.hearth-client.ps1
     Add to \$PROFILE:
       \$env:HEARTH_SSH = "hearth"
       \$env:HEARTH_CLOUD_MODEL = "${CLOUD_MODEL}"
       . "\$HOME\\.hearth-client.ps1"
   Store a token only when .hearth-key is missing or this is a new token:
     Read-Host -AsSecureString "token" | ConvertFrom-SecureString -AsPlainText | Set-Content \$HOME\\.hearth-key      # PowerShell 7, laptop-${NAME}
     Read-Host -AsSecureString "gemini" | ConvertFrom-SecureString -AsPlainText | Set-Content \$HOME\\.hearth-gemini-key

4. ON THE LAPTOP — prove it: ai-tunnel, ai-ping, ai-models, ask, ask-cloud, ai-webui
   Windows stays on one-shot ai-tunnel. There is no LaunchAgent.
EOF
fi
cat <<EOF

5. Zed on the laptop: docs/LAPTOP.md (api_url http://127.0.0.1:1234/v1 through
   the tunnel; the laptop-${NAME} token via the UI). On macOS, ai-tunnel-install
   starts the tunnel at login. A Gemini provider is allowed on the laptop (D3).

Revoke a laptop: run
  scripts/omlx.sh sub-key revoke laptop-${NAME}
and delete its hearth-tunnel-${NAME} line in ${AK}.
EOF
