#!/bin/bash
# Set up this machine as a client of a Hearth host (ADR 0040). Laptop-safe:
# it never reads a key or token, never touches the host, and only writes
# ~/.hearth-client.sh, a "Host hearth" block in ~/.ssh/config, and one
# marked block in your shell rc.
#
#   client/install-client.sh --host you@studio.local     # first time
#   client/install-client.sh                             # update / re-run
#   client/install-client.sh --check                     # report, change nothing
#
# Options:
#   --host user@host   the Hearth host, for the ~/.ssh/config entry (first time)
#   --dual             this machine also runs its own brain on 127.0.0.1:1234:
#                      the tunnel moves to 1235 and
#                      the client's aider commands get a -remote suffix
#   --laptop           force client-only mode (tunnel on 1234)
#   Without either, dual is chosen when ~/.config/hearth/env exists (a host
#   token means this machine is also a host).
#
# Exit 0 done / all ok, 1 something missing (--check) or refused, 2 could not run.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${ROOT}/client/hearth-client.sh"
DEST="${HOME}/.hearth-client.sh"
SSHCFG="${HOME}/.ssh/config"
PLIST="${HOME}/Library/LaunchAgents/com.hearth.tunnel.plist"
BEGIN="# BEGIN hearth client (client/install-client.sh)"
END="# END hearth client"

CHECK=0 HOST="" MODE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK=1 ;;
    --host) HOST="${2:-}"; shift ;;
    --host=*) HOST="${1#--host=}" ;;
    --dual) MODE=dual ;;
    --laptop) MODE=laptop ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "unknown option: $1"; exit 2 ;;
  esac
  shift
done
[ -f "$SRC" ] || { echo "could not run: ${SRC} missing"; exit 2; }
if [ -z "$MODE" ]; then
  if [ -f "${HOME}/.config/hearth/env" ]; then MODE=dual; else MODE=laptop; fi
fi
case "$HOST" in
  ''|*[!A-Za-z0-9@._-]*) [ -z "$HOST" ] || { echo "--host must be user@host (letters, digits, . _ - @)"; exit 2; } ;;
esac

case "${SHELL:-}" in
  */bash) RC="${HOME}/.bashrc" ;;
  *) RC="${HOME}/.zshrc" ;;
esac

CLOUD=$(awk -F'\t' '$1 == "cloud-cheap" {print $3; exit}' "${ROOT}/config/roles.tsv")

rc=0
ok()   { printf 'ok      %s\n' "$1"; }
todo() { printf 'TODO    %s\n' "$1"; rc=1; }
did()  { printf 'wrote   %s\n' "$1"; }

block() {
  printf '%s\n' "$BEGIN"
  printf 'export HEARTH_SSH=hearth\n'
  [ -n "$CLOUD" ] && printf 'export HEARTH_CLOUD_MODEL=%s\n' "$CLOUD"
  [ "$MODE" = dual ] && printf 'export HEARTH_DUAL=1\n'
  printf 'source ~/.hearth-client.sh\n'
  printf '%s\n' "$END"
}

echo "mode: ${MODE}  (tunnel on 127.0.0.1:$([ "$MODE" = dual ] && echo 1235 || echo 1234))"

# 1. client script
if [ -f "$DEST" ] && cmp -s "$SRC" "$DEST"; then
  ok "~/.hearth-client.sh is current"
elif [ "$CHECK" -eq 1 ]; then
  todo "~/.hearth-client.sh $([ -f "$DEST" ] && echo "is stale" || echo "is missing")"
else
  [ -f "$DEST" ] && cp -p "$DEST" "${DEST}.bak"
  cp "$SRC" "$DEST" && did "~/.hearth-client.sh$([ -f "${DEST}.bak" ] && echo " (old copy: .bak)")"
fi

# 2. ssh config
if [ -f "$SSHCFG" ] && grep -qE '^[[:space:]]*Host[[:space:]]+hearth([[:space:]]|$)' "$SSHCFG"; then
  ok "~/.ssh/config has Host hearth"
elif [ "$CHECK" -eq 1 ]; then
  todo "~/.ssh/config has no Host hearth entry"
elif [ -z "$HOST" ]; then
  todo "~/.ssh/config has no Host hearth entry — re-run with --host user@host.local"
else
  mkdir -p "${HOME}/.ssh" && chmod 700 "${HOME}/.ssh"
  u="${HOST%%@*}"; h="${HOST#*@}"; [ "$u" = "$HOST" ] && u="$(id -un)"
  printf '\nHost hearth\n  HostName %s\n  User %s\n  IdentityFile ~/.ssh/hearth_tunnel\n  IdentitiesOnly yes\n  ServerAliveInterval 30\n  ServerAliveCountMax 3\n' "$h" "$u" >> "$SSHCFG"
  chmod 600 "$SSHCFG"; did "~/.ssh/config: Host hearth → ${u}@${h}"
fi

# 3. shell rc block. Older setups appended loose lines; those are commented
# out (backup kept) so the block is the only source of truth.
# WEBUI_PORT and SEARXNG_PORT stay in the pattern so an old export is
# commented out (ADR 0044, 0045). The client ignores both.
loose='^[[:space:]]*(export[[:space:]]+HEARTH_(SSH|CLOUD_MODEL|DUAL|LOCAL_PORT|WEBUI_PORT|SEARXNG_PORT)=|(source|\.)[[:space:]]+~/\.hearth-client\.sh)'
want="$(block)"
have=""
[ -f "$RC" ] && have="$(awk -v b="$BEGIN" -v e="$END" '$0==b{p=1} p{print} $0==e{p=0}' "$RC")"
outside=0
[ -f "$RC" ] && outside=$(awk -v b="$BEGIN" -v e="$END" '$0==b{p=1} !p{print} $0==e{p=0}' "$RC" | grep -cE "$loose" || true)
if [ "$have" = "$want" ] && [ "$outside" -eq 0 ]; then
  ok "${RC/#$HOME/~} hearth block is current"
elif [ "$CHECK" -eq 1 ]; then
  todo "${RC/#$HOME/~} hearth block $([ -n "$have" ] && echo "is out of date" || echo "is missing")$([ "$outside" -gt 0 ] && echo "; ${outside} loose hearth line(s) outside it")"
else
  [ -f "$RC" ] && cp -p "$RC" "${RC}.hearth.bak"
  tmp="$(mktemp)"
  if [ -f "$RC" ]; then
    awk -v b="$BEGIN" -v e="$END" -v re="$loose" '
      $0==b {skip=1; next}
      skip && $0==e {skip=0; next}
      skip {next}
      $0 ~ re {print "# (moved into the hearth block) " $0; next}
      {print}' "$RC" > "$tmp"
  fi
  printf '\n%s\n' "$want" >> "$tmp"
  mv "$tmp" "$RC"
  did "${RC/#$HOME/~} hearth block (backup: ${RC/#$HOME/~}.hearth.bak$([ "$outside" -gt 0 ] && echo "; ${outside} loose line(s) commented out"))"
fi

# 4. secrets: presence and mode only. Never read.
mode_ok() { [ -f "$1" ] && [ "$(ls -l "$1" | cut -c5-10)" = "------" ] && [ -s "$1" ]; }
if mode_ok "${HOME}/.ssh/hearth_tunnel"; then ok "~/.ssh/hearth_tunnel present, mode 600"
else todo "tunnel key: ssh-keygen -t ed25519 -f ~/.ssh/hearth_tunnel -C hearth-tunnel-<short-name>, then on the host: scripts/client-setup.sh <short-name> --authorize hearth_tunnel.pub"; fi
if mode_ok "${HOME}/.hearth-key"; then ok "~/.hearth-key present, mode 600"
else todo "token: on the host scripts/omlx.sh sub-key add laptop-<short-name>; then here, in your own terminal: umask 077; read -rs t && printf '%s' \"\$t\" > ~/.hearth-key && unset t"; fi

# 5. launchd tunnel on the right port
port=1234; [ "$MODE" = dual ] && port=1235
if [ "$(uname -s)" = Darwin ]; then
  if [ -f "$PLIST" ] && grep -qF -- "127.0.0.1:8888" "$PLIST"; then
    todo "launchd tunnel still forwards SearXNG — in a new shell: ai-tunnel-stop && ai-tunnel-install"
  fi
  if [ -f "$PLIST" ] && grep -qF -- "127.0.0.1:${port}:127.0.0.1:1234" "$PLIST"; then
    ok "launchd tunnel forwards 127.0.0.1:${port}"
  elif [ -f "$PLIST" ]; then
    todo "launchd tunnel uses another port — in a new shell: ai-tunnel-stop && ai-tunnel-install"
  else
    todo "no launchd tunnel — in a new shell: ai-tunnel (accept the host fingerprint once), then ai-tunnel-install"
  fi
fi

echo
if [ "$MODE" = dual ]; then
  echo "hearth: this machine's brain on 127.0.0.1:1234 (ask / coding-brain / ask-deep)."
  echo "hearth-remote: optional, the other host on 127.0.0.1:1235"
  echo "(ask-remote / coding-brain-remote / ask-deep-remote)."
else
  echo "Client only: the tunnel is 127.0.0.1:1234. No local hearth, and no hearth-remote, until this machine runs its own brain (client/install-client.sh --dual)."
fi
echo
echo "Then, in a new shell: ai-ping (expect: up) and ai-models."
exit "$rc"
