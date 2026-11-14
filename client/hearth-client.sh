# hearth client — source this on a laptop. ADR 0016, phase 4: SSH tunnel only.
#
#   echo 'source ~/.hearth-client.sh' >> ~/.zshrc      # macOS
#   echo 'source ~/.hearth-client.sh' >> ~/.bashrc     # Linux
#
# Portable: bash and zsh, macOS and Linux. No bash 4 syntax.
#
# The host's oMLX listens on 127.0.0.1:1234 only. This machine reaches it
# through an SSH tunnel — the same setup on and off the LAN, encrypted, and
# nothing on the host is exposed to the network.
#
# Set before sourcing (scripts/client-setup.sh on the host prints these):
#   HEARTH_SSH          user@host for the tunnel, e.g. colin@Colins-Mac-Studio.local
#   HEARTH_CLOUD_MODEL  the Gemini model id for ask-cloud (from the host's roles.tsv)
# Optional:
#   HEARTH_DUAL         1 on a machine that also runs its own brain (ADR 0040):
#                       the tunnel port defaults to 1235, commands get -remote
#   HEARTH_LOCAL_PORT   local end of the oMLX tunnel (default 1234; 1235 when dual)
#   HEARTH_SWAP_PORT    local end of hearth-swapd (default 1236 → host :1236)
#   HEARTH_SSH_ADMIN    fallback: ordinary SSH login on the host (not the tunnel
#                       key) when swapd is down (ADR 0048, 0049). Preferred
#                       path is POST to hearth-swapd over the tunnel with the
#                       laptop sub-key.
#   HEARTH_REMOTE_ROOT  the hearth repo on the host, relative to that
#                       login's home (default dev/hearth); SSH fallback only
#                       SearXNG is local on this machine (ADR 0045). An old
#                       HEARTH_SEARXNG_PORT or HEARTH_WEBUI_PORT is ignored.
#
# Secrets (files, mode 600 — never exported into this shell):
#   ~/.hearth-key         this machine's API key (laptop-<name>)
#   ~/.hearth-gemini-key  this machine's own Google API key, for ask-cloud only
#
# Commands: ai-tunnel, ai-tunnel-install, ai-tunnel-stop, ai-ping, ai-models,
#           ai-ask, ask and main-brain (the host's resident), ask-arch,
#           coding-brain and deep-brain / ask-deep (swap roles: loaded on
#           the host for the session), hearth-load, ask-cloud
#
# macOS: ai-tunnel-install once. launchd (com.hearth.tunnel) restarts the
# forwards when the session drops, and again at login. ai-tunnel then
# kickstarts that job instead of leaving a one-shot ssh -f behind. Linux
# stays on ssh -f. Do not run a second ssh -f while the agent holds the ports.

# Old gateway installs set HEARTH_GATEWAY to :4000, which no longer exists.
if [ -n "${HEARTH_GATEWAY:-}${AI_STACK_GATEWAY:-}" ]; then
  echo "hearth: HEARTH_GATEWAY is from the retired gateway and is ignored — set HEARTH_SSH instead." >&2
fi
if [ -z "${HEARTH_SSH:-}" ]; then
  echo "hearth: set HEARTH_SSH first (e.g. export HEARTH_SSH=you@your-host.local)" >&2
  echo "        or run scripts/client-setup.sh on the host for copy-paste instructions." >&2
  return 1 2>/dev/null || exit 1
fi

# HEARTH_DUAL=1: this machine also runs its own brain on 127.0.0.1:1234
# (ADR 0040). The tunnel then moves off the port the local oMLX uses, and
# this file's aider commands get a -remote suffix so the host aliases
# (scripts/aliases.zsh) keep ask, main-brain, ask-deep.
HEARTH_DUAL="${HEARTH_DUAL:-0}"
if [ "$HEARTH_DUAL" = 1 ]; then
  # Local oMLX keeps :1234; local hearth-swapd (if this machine is also a host)
  # keeps :1236. Tunnel ends move aside (ADR 0040, 0049).
  HEARTH_LOCAL_PORT="${HEARTH_LOCAL_PORT:-1235}"
  HEARTH_SWAP_PORT="${HEARTH_SWAP_PORT:-1237}"
else
  HEARTH_LOCAL_PORT="${HEARTH_LOCAL_PORT:-1234}"
  HEARTH_SWAP_PORT="${HEARTH_SWAP_PORT:-1236}"
fi
HEARTH_TUNNEL_URL="http://127.0.0.1:${HEARTH_LOCAL_PORT}/v1"
HEARTH_SWAP_URL="http://127.0.0.1:${HEARTH_SWAP_PORT}"

# Read a secret file without exporting it. Refuses a world-readable file.
_hearth_secret() {
  _f="$1"
  [ -f "$_f" ] || { echo "hearth: ${_f} missing" >&2; return 1; }
  case "$(ls -l "$_f" | cut -c5-10)" in
    ------) : ;;
    *) echo "hearth: ${_f} is readable by others — chmod 600 ${_f}" >&2; return 1 ;;
  esac
  tr -d '\r\n' < "$_f"
}

_hearth_port_open() {
  _p="$1"
  if command -v nc >/dev/null 2>&1; then
    nc -z 127.0.0.1 "$_p" >/dev/null 2>&1
  else
    curl -s -m 2 -o /dev/null "http://127.0.0.1:${_p}/" >/dev/null 2>&1
  fi
}

# Our ssh -L, not merely something listening. Two fixed-string greps so this
# function's own pipeline cannot match itself. ExitOnForwardFailure means that
# ssh is not still running if it failed to bind the local port.
_hearth_our_ssh() {
  ps axww -o command= 2>/dev/null \
    | grep -F "ssh " \
    | grep -F -- "-L 127.0.0.1:${HEARTH_LOCAL_PORT}:127.0.0.1:1234" \
    | grep -F -- "-L 127.0.0.1:${HEARTH_SWAP_PORT}:127.0.0.1:1236" \
    >/dev/null 2>&1
}

# The tunnel forwards oMLX and hearth-swapd (ADR 0045, 0049). An old ssh that
# also forwards SearXNG is still "up" for the model; _hearth_tunnel_stale says so.
_hearth_forwards_open() {
  _hearth_port_open "$HEARTH_LOCAL_PORT" && _hearth_port_open "$HEARTH_SWAP_PORT"
}

# 0 when it is safe to send the token. Prints the reason on failure.
# Does not start a tunnel. Callers that may start one use _hearth_connect.
_hearth_require_tunnel() {
  if _hearth_port_open "$HEARTH_LOCAL_PORT" && ! _hearth_our_ssh; then
    echo "127.0.0.1:${HEARTH_LOCAL_PORT} is open, but not the hearth ssh tunnel. Not sending the token." >&2
    return 1
  fi
  if ! _hearth_our_ssh || ! _hearth_port_open "$HEARTH_LOCAL_PORT"; then
    echo "DOWN — no tunnel on 127.0.0.1:${HEARTH_LOCAL_PORT}. Run: ai-tunnel"
    return 1
  fi
}

# Stranger on the local port: refuse. Otherwise bring the forwards up, then
# refuse again if the result is still not our ssh. A foreign listener must
# not be followed by an attempt to send the token.
_hearth_connect() {
  if _hearth_port_open "$HEARTH_LOCAL_PORT" && ! _hearth_our_ssh; then
    echo "127.0.0.1:${HEARTH_LOCAL_PORT} is open, but not the hearth ssh tunnel. Not sending the token." >&2
    return 1
  fi
  _hearth_forwards_open || ai-tunnel || return 1
  if ! _hearth_our_ssh || ! _hearth_port_open "$HEARTH_LOCAL_PORT"; then
    echo "DOWN — no tunnel on 127.0.0.1:${HEARTH_LOCAL_PORT}. Run: ai-tunnel"
    return 1
  fi
}

# One argv line per ssh argument. oMLX + hearth-swapd (ADR 0045, 0049).
_hearth_tunnel_argv() {
  printf '%s\n' /usr/bin/ssh -N \
    -o ExitOnForwardFailure=yes \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=3 \
    -L "127.0.0.1:${HEARTH_LOCAL_PORT}:127.0.0.1:1234" \
    -L "127.0.0.1:${HEARTH_SWAP_PORT}:127.0.0.1:1236" \
    "$HEARTH_SSH"
}

_hearth_tunnel_stale() {
  _plist="$(_hearth_tunnel_plist)"
  if [ -f "$_plist" ] && grep -F -- "127.0.0.1:3000" "$_plist" >/dev/null 2>&1; then
    echo "tunnel: this agent still forwards Open WebUI (:3000). Run: ai-tunnel-stop && ai-tunnel-install" >&2
  fi
  if [ -f "$_plist" ] && grep -F -- "127.0.0.1:8888" "$_plist" >/dev/null 2>&1; then
    echo "tunnel: this agent still forwards SearXNG. Search stays on this machine (ADR 0045). Run: ai-tunnel-stop && ai-tunnel-install" >&2
  fi
  if [ -f "$_plist" ] && ! grep -F -- "127.0.0.1:1236" "$_plist" >/dev/null 2>&1; then
    echo "tunnel: this agent has no hearth-swapd forward (:1236). Run: ai-tunnel-stop && ai-tunnel-install" >&2
  fi
  if ps axww -o command= 2>/dev/null \
      | grep -F -- "-L 127.0.0.1:${HEARTH_LOCAL_PORT}:127.0.0.1:1234" \
      | grep -F -- "127.0.0.1:8888" >/dev/null 2>&1; then
    echo "tunnel: this ssh still forwards SearXNG. Run: ai-tunnel-stop && ai-tunnel" >&2
  fi
  unset _plist
}

_hearth_tunnel_up_msg() {
  echo "tunnel: up (oMLX → 127.0.0.1:${HEARTH_LOCAL_PORT}, swapd → 127.0.0.1:${HEARTH_SWAP_PORT})"
  _hearth_tunnel_stale
}

_hearth_tunnel_plist() {
  printf '%s\n' "${HOME}/Library/LaunchAgents/com.hearth.tunnel.plist"
}

# Ours only when the plist forwards this client's oMLX port. An older agent
# that ran `ssh -N` with no -L is not this tunnel.
_hearth_plist_ours() {
  _plist="$(_hearth_tunnel_plist)"
  [ -f "$_plist" ] || return 1
  grep -F -- "127.0.0.1:${HEARTH_LOCAL_PORT}:127.0.0.1:1234" "$_plist" >/dev/null 2>&1 \
    && grep -F -- "127.0.0.1:${HEARTH_SWAP_PORT}:127.0.0.1:1236" "$_plist" >/dev/null 2>&1
}

_hearth_tunnel_names_ok() {
  case "${HEARTH_SSH}" in
    ''|*[!A-Za-z0-9@._:-]*)
      echo "tunnel: HEARTH_SSH must be a host alias or user@host (letters, digits, . _ - @ :)." >&2
      return 1
      ;;
  esac
  for _p in "$HEARTH_LOCAL_PORT" "$HEARTH_SWAP_PORT"; do
    case "$_p" in
      ''|*[!0-9]*)
        echo "tunnel: port '${_p}' is not a number." >&2
        return 1
        ;;
    esac
  done
  return 0
}

_hearth_write_tunnel_plist() {
  _plist="$(_hearth_tunnel_plist)"
  mkdir -p "${HOME}/Library/LaunchAgents" "${HOME}/Library/Logs" || return 1
  {
    cat <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.hearth.tunnel</string>
    <key>ProgramArguments</key>
    <array>
EOF
    _hearth_tunnel_argv | while IFS= read -r _arg; do
      printf '        <string>%s</string>\n' "$_arg"
    done
    cat <<EOF
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>10</integer>
    <key>StandardOutPath</key>
    <string>${HOME}/Library/Logs/hearth-tunnel.log</string>
    <key>StandardErrorPath</key>
    <string>${HOME}/Library/Logs/hearth-tunnel.error.log</string>
</dict>
</plist>
EOF
  } > "$_plist"
}

_hearth_wait_forwards() {
  _n=0
  while [ "$_n" -lt 20 ]; do
    if _hearth_forwards_open && _hearth_our_ssh; then
      return 0
    fi
    sleep 0.5
    _n=$((_n + 1))
  done
  return 1
}

# Load com.hearth.tunnel if needed and start it. No -f: launchd owns the ssh.
_hearth_launchd_start() {
  _dom="gui/$(id -u)"
  if ! launchctl print "${_dom}/com.hearth.tunnel" >/dev/null 2>&1; then
    launchctl bootstrap "$_dom" "$(_hearth_tunnel_plist)" || return 1
  fi
  launchctl kickstart -k "${_dom}/com.hearth.tunnel" || return 1
  if _hearth_wait_forwards; then
    return 0
  fi
  echo "tunnel: launchd did not bind the forwards." >&2
  echo "        If this host key is new, accept it once: ssh ${HEARTH_SSH}" >&2
  echo "        Log: ${HOME}/Library/Logs/hearth-tunnel.error.log" >&2
  return 1
}

_hearth_refuse_partial() {
  echo "tunnel: 127.0.0.1:${HEARTH_LOCAL_PORT} is open but this client's ssh is not the listener." >&2
  echo "        Run: ai-tunnel-stop && ai-tunnel" >&2
}

ai-tunnel-install() {
  if [ "$(uname -s)" != "Darwin" ]; then
    echo "tunnel: ai-tunnel-install is macOS (launchd). On Linux, use ai-tunnel." >&2
    return 1
  fi
  command -v launchctl >/dev/null 2>&1 || {
    echo "tunnel: launchctl not found." >&2
    return 1
  }
  _hearth_tunnel_names_ok || return 1
  # A one-shot ssh -f holds the ports and makes the agent's bind fail.
  pkill -f "ssh -f -N .*-L 127.0.0.1:${HEARTH_LOCAL_PORT}:127.0.0.1:1234" >/dev/null 2>&1 || true
  launchctl bootout "gui/$(id -u)/com.hearth.tunnel" >/dev/null 2>&1 || true
  _hearth_write_tunnel_plist || return 1
  _hearth_launchd_start || return 1
  echo "tunnel: installed com.hearth.tunnel — restarts when the session drops, and at login"
  _hearth_tunnel_up_msg
}

ai-tunnel() {
  if _hearth_port_open "$HEARTH_LOCAL_PORT" && ! _hearth_our_ssh; then
    echo "tunnel: 127.0.0.1:${HEARTH_LOCAL_PORT} is open, but not the hearth ssh tunnel. Refusing." >&2
    return 1
  fi
  if _hearth_port_open "$HEARTH_LOCAL_PORT"; then
    if _hearth_forwards_open; then
      echo "tunnel: already listening on 127.0.0.1:${HEARTH_LOCAL_PORT} and :${HEARTH_SWAP_PORT}"
      _hearth_tunnel_stale
      return 0
    fi
    _hearth_refuse_partial
    return 1
  fi
  # ExitOnForwardFailure: fail loudly instead of a half-open tunnel — so a
  # local port already in use fails the whole tunnel.
  if _hearth_plist_ours; then
    _hearth_launchd_start || return 1
    _hearth_tunnel_up_msg
    return 0
  fi
  ssh -f -N \
    -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
    -L "127.0.0.1:${HEARTH_LOCAL_PORT}:127.0.0.1:1234" \
    -L "127.0.0.1:${HEARTH_SWAP_PORT}:127.0.0.1:1236" \
    "$HEARTH_SSH" \
    && _hearth_tunnel_up_msg
}

ai-tunnel-stop() {
  _stopped=0
  if [ "$(uname -s)" = "Darwin" ]; then
    if launchctl bootout "gui/$(id -u)/com.hearth.tunnel" >/dev/null 2>&1; then
      _stopped=1
    fi
  fi
  if pkill -f "ssh -f -N .*-L 127.0.0.1:${HEARTH_LOCAL_PORT}:127.0.0.1:1234" >/dev/null 2>&1; then
    _stopped=1
  fi
  if [ "$_stopped" -eq 1 ]; then
    echo "tunnel: stopped"
  else
    echo "tunnel: none running"
  fi
}

ai-ping() {
  _hearth_require_tunnel || return 1
  _k=$(_hearth_secret "$HOME/.hearth-key") || return 1
  _c=$(printf 'header = "Authorization: Bearer %s"\n' "$_k" \
       | curl -s -m 8 -o /dev/null -w '%{http_code}' -K - "${HEARTH_TUNNEL_URL}/models")
  unset _k
  case "$_c" in
    200) echo "up" ;;
    401) echo "BAD TOKEN — ~/.hearth-key was refused (revoked, or wrong machine's token)" ;;
    000) echo "NO ANSWER — tunnel listening but the host did not reply (asleep? oMLX down? on the host: scripts/boot.sh)" ;;
    *)   echo "HTTP ${_c}" ;;
  esac
  [ "$_c" = "200" ]
}

ai-models() {
  _hearth_require_tunnel || return 1
  _k=$(_hearth_secret "$HOME/.hearth-key") || return 1
  printf 'header = "Authorization: Bearer %s"\n' "$_k" \
    | curl -s -m 8 -K - "${HEARTH_TUNNEL_URL}/models" \
    | python3 -c 'import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    print("no response — ai-ping"); raise SystemExit(1)
for m in d.get("data", []): print("  " + m["id"])'
  unset _k
}

ai-ask() {
  # One-shot question without aider:  ai-ask "question"
  [ $# -gt 0 ] || { echo "usage: ai-ask \"question\"" >&2; return 2; }
  _hearth_require_tunnel || return 1
  _k=$(_hearth_secret "$HOME/.hearth-key") || return 1
  # umask inside the substitution so the file is created mode 600. A later
  # redirect truncates it and keeps that mode.
  _body=$(umask 077 && mktemp "${TMPDIR:-/tmp}/hearth-ask.XXXXXX") || { unset _k; return 1; }
  python3 -c 'import json, sys; print(json.dumps({"model": "main-brain", "messages": [{"role": "user", "content": " ".join(sys.argv[1:])}]}))' "$@" \
    > "$_body"
  printf 'header = "Authorization: Bearer %s"\n' "$_k" \
    | curl -s -m 300 -K - -H 'Content-Type: application/json' \
        --data-binary @"$_body" "${HEARTH_TUNNEL_URL}/chat/completions" \
    | python3 -c 'import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    print("no response — ai-ping"); raise SystemExit(1)
if "error" in d: print("error:", d["error"]); raise SystemExit(1)
print((d["choices"][0]["message"].get("content") or "").strip())'
  _rc=$?
  rm -f "$_body"; unset _k _body
  return $_rc
}

# ---------------------------------------------------------------- aider
# The token is injected per invocation, never exported. The default role is
# main-brain, the resident on every host (ADR 0048). Clients call roles,
# never models.
_hearth_aider() {
  _hearth_connect || return 1
  _k=$(_hearth_secret "$HOME/.hearth-key") || return 1
  OPENAI_API_BASE="$HEARTH_TUNNEL_URL" OPENAI_API_KEY="$_k" \
    aider --model openai/main-brain --weak-model openai/main-brain "$@"
  _rc=$?; unset _k; return $_rc
}
_hearth_ask_arch() { _hearth_aider --architect --editor-model openai/main-brain "$@"; }

# Load or unload a swap role on the host (ADR 0048, 0049):
#   hearth-load coding-brain up      hearth-load deep-brain down
# Preferred: POST hearth-swapd over the tunnel with ~/.hearth-key.
# Fallback: HEARTH_SSH_ADMIN runs demand-load.sh on the host.
# Prints loaded, already, or restored <role>.
# While a swap role is in, main-brain on that host has no model of its own.
_hearth_load_ssh() {
  case "${HEARTH_REMOTE_ROOT:-dev/hearth}" in *[!A-Za-z0-9_./-]*)
    echo "hearth: HEARTH_REMOTE_ROOT has characters other than letters, digits, . _ / -" >&2; return 1 ;; esac
  /usr/bin/ssh "$HEARTH_SSH_ADMIN" "cd ${HEARTH_REMOTE_ROOT:-dev/hearth} && scripts/demand-load.sh $1 $2"
}

_hearth_load_http() {
  _k=$(_hearth_secret "$HOME/.hearth-key") || return 1
  _body=$(umask 077 && mktemp "${TMPDIR:-/tmp}/hearth-load.XXXXXX") || { unset _k; return 1; }
  printf '{"role":"%s","action":"%s"}\n' "$1" "$2" > "$_body"
  _resp=$(umask 077 && mktemp "${TMPDIR:-/tmp}/hearth-load-out.XXXXXX") || {
    rm -f "$_body"; unset _k _body; return 1
  }
  _code=$(printf 'header = "Authorization: Bearer %s"\n' "$_k" \
    | curl -s -m 600 -o "$_resp" -w '%{http_code}' -K - \
        -H 'Content-Type: application/json' \
        --data-binary @"$_body" \
        "${HEARTH_SWAP_URL}/v1/hearth/load")
  unset _k
  _out=$(tr -d '\r' < "$_resp" | sed -e 's/[[:space:]]*$//')
  rm -f "$_body" "$_resp"
  unset _body _resp
  case "$_code" in
    200)
      printf '%s\n' "$_out"
      unset _code _out
      return 0
      ;;
    000)
      echo "hearth: swapd did not answer on 127.0.0.1:${HEARTH_SWAP_PORT}" >&2
      unset _code _out
      return 1
      ;;
    *)
      echo "hearth: swapd HTTP ${_code}: ${_out}" >&2
      unset _code _out
      return 1
      ;;
  esac
}

_hearth_agent_http() {
  _k=$(_hearth_secret "$HOME/.hearth-key") || return 1
  _out=$(printf 'header = "Authorization: Bearer %s"\n' "$_k" \
    | curl -s -m 8 -K - "${HEARTH_SWAP_URL}/v1/hearth/agent") || {
    unset _k; return 1
  }
  unset _k
  printf '%s' "$_out" | python3 -c 'import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    raise SystemExit(1)
a = d.get("agent")
print(a if a else "")'
}

hearth-load() {
  case "${1:-}" in coding-brain|deep-brain) : ;; *)
    echo "usage: hearth-load coding-brain|deep-brain up|down" >&2; return 2 ;; esac
  case "${2:-}" in up|down) : ;; *)
    echo "usage: hearth-load coding-brain|deep-brain up|down" >&2; return 2 ;; esac
  _hearth_connect || return 1
  if _hearth_port_open "$HEARTH_SWAP_PORT"; then
    _hearth_load_http "$1" "$2" && return 0
  fi
  if [ -n "${HEARTH_SSH_ADMIN:-}" ]; then
    echo "hearth: swapd unreachable; falling back to HEARTH_SSH_ADMIN" >&2
    _hearth_load_ssh "$1" "$2"
    return $?
  fi
  echo "hearth: swapd down on 127.0.0.1:${HEARTH_SWAP_PORT}." >&2
  echo "        On the host: scripts/hearth-swapd.sh up" >&2
  echo "        Or set HEARTH_SSH_ADMIN and retry, or run scripts/demand-load.sh $1 $2 on the host." >&2
  return 1
}

# A swap role for one aider session (coding-brain, deep-brain). This laptop
# cannot load weights itself. hearth-load (swapd, else HEARTH_SSH_ADMIN) brings
# the role in; this call restores the resident if it did the loading.
# Without either path, ask whether the host already has the role loaded.
_hearth_swap_remote() {
  _role="$1"; shift
  _hearth_connect || return 1
  _state=""
  if _state=$(hearth-load "$_role" up); then
    # Strip host chatter; demand-load / swapd return one state token.
    _state=$(printf '%s\n' "$_state" | tail -1 | tr -d '\r')
    case "$_state" in
      loaded)  echo "${_role}: loaded on the host. If this session is killed: hearth-load ${_role} down" >&2 ;;
      already) echo "${_role}: already loaded on the host; this session will not unload it." >&2 ;;
      *)       echo "${_role}: unexpected answer from the host: ${_state}" >&2; unset _role _state; return 1 ;;
    esac
  else
    _agent=$(_hearth_agent_http 2>/dev/null) || _agent=""
    if [ "$_agent" = "$_role" ]; then
      _state=already
      echo "${_role}: already loaded on the host; this session will not unload it." >&2
    else
      echo "${_role} must already be loaded on the host: scripts/demand-load.sh ${_role} up" >&2
      echo "(hearth-load needs swapd on :${HEARTH_SWAP_PORT}, or HEARTH_SSH_ADMIN)." >&2
      printf 'Is it loaded? [y/N] ' >&2
      read -r _yn
      case "$_yn" in y|Y) : ;; *) unset _role _state _yn _agent; return 1 ;; esac
      unset _yn
      _state=""
    fi
    unset _agent
  fi
  _k=$(_hearth_secret "$HOME/.hearth-key") || { unset _role _state; return 1; }
  # weak-model is the same role: the resident is not loaded to answer it.
  OPENAI_API_BASE="$HEARTH_TUNNEL_URL" OPENAI_API_KEY="$_k" \
    aider --model "openai/${_role}" --weak-model "openai/${_role}" "$@"
  _rc=$?; unset _k
  [ "$_state" = loaded ] && hearth-load "$_role" down >&2
  unset _role _state
  return $_rc
}
_hearth_ask_coding() { _hearth_swap_remote coding-brain "$@"; }
_hearth_ask_deep()   { _hearth_swap_remote deep-brain "$@"; }

# Public names. Plain on a laptop; -remote on a machine that is also a host
# (ADR 0039 names, ADR 0040 dual mode). Dual mode leaves `ask` alone: there
# it belongs to the host aliases (scripts/aliases.zsh).
#
# `function name { }` and not `name() { }`: zsh expands aliases when it
# parses, and parses the whole if-block, so `ask() {` breaks on a host's
# `ask` alias even in the branch that does not run. Older copies of this
# file also defined ask as an alias; laptop mode drops that one.
[ "$HEARTH_DUAL" = 1 ] || unalias ask 2>/dev/null || true
if [ "$HEARTH_DUAL" = 1 ]; then
  function ask-remote          { _hearth_aider "$@"; }
  function coding-brain-remote { _hearth_ask_coding "$@"; }
  function main-brain-remote   { _hearth_aider "$@"; }
  function ask-arch-remote     { _hearth_ask_arch "$@"; }
  function ask-deep-remote     { _hearth_ask_deep "$@"; }
  function deep-brain-remote   { _hearth_ask_deep "$@"; }
else
  function ask          { _hearth_aider "$@"; }
  function coding-brain { _hearth_ask_coding "$@"; }
  function main-brain   { _hearth_aider "$@"; }
  function ask-arch     { _hearth_ask_arch "$@"; }
  function ask-deep     { _hearth_ask_deep "$@"; }
  function deep-brain   { _hearth_ask_deep "$@"; }
fi

# The only command that leaves for the cloud, with THIS machine's own key.
ask-cloud() {
  [ -n "${HEARTH_CLOUD_MODEL:-}" ] || { echo "hearth: set HEARTH_CLOUD_MODEL (client/install-client.sh writes it)" >&2; return 1; }
  _g=$(_hearth_secret "$HOME/.hearth-gemini-key") || return 1
  GEMINI_API_KEY="$_g" aider --model "gemini/${HEARTH_CLOUD_MODEL}" --weak-model "gemini/${HEARTH_CLOUD_MODEL}" "$@"
  _rc=$?; unset _g; return $_rc
}
