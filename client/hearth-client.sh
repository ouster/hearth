# hearth client — source this on a laptop. ADR 0016, phase 4: SSH tunnel only.
#
#   echo 'source ~/.hearth-client.sh' >> ~/.zshrc      # macOS
#   echo 'source ~/.hearth-client.sh' >> ~/.bashrc     # Linux
#
# Portable: bash and zsh, macOS and Linux. No bash 4 syntax.
#
# The host's LM Studio listens on 127.0.0.1:1234 only. This machine reaches it
# through an SSH tunnel — the same setup on and off the LAN, encrypted, and
# nothing on the host is exposed to the network.
#
# Set before sourcing (scripts/client-setup.sh on the host prints these):
#   HEARTH_SSH          user@host for the tunnel, e.g. colin@Colins-Mac-Studio.local
#   HEARTH_CLOUD_MODEL  the Gemini model id for ask-cloud (from the host's roles.tsv)
# Optional:
#   HEARTH_LOCAL_PORT   local end of the tunnel (default 1234)
#   HEARTH_WEBUI_PORT   local end for Open WebUI (default 3000)
#
# Secrets (files, mode 600 — never exported into this shell):
#   ~/.hearth-key         this machine's LM Studio token (laptop-<name>)
#   ~/.hearth-gemini-key  this machine's own Google API key, for ask-cloud only
#
# Commands: ai-tunnel, ai-tunnel-stop, ai-ping, ai-models, ai-ask, ai-webui,
#           ask (and ask-big/-local/-chat/-fast, all local-big), ask-arch, ask-cloud

# Old gateway installs set HEARTH_GATEWAY to :4000, which no longer exists.
if [ -n "${HEARTH_GATEWAY:-}${AI_STACK_GATEWAY:-}" ]; then
  echo "hearth: HEARTH_GATEWAY is from the retired gateway and is ignored — set HEARTH_SSH instead." >&2
fi
if [ -z "${HEARTH_SSH:-}" ]; then
  echo "hearth: set HEARTH_SSH first (e.g. export HEARTH_SSH=you@your-host.local)" >&2
  echo "        or run scripts/client-setup.sh on the host for copy-paste instructions." >&2
  return 1 2>/dev/null || exit 1
fi

HEARTH_LOCAL_PORT="${HEARTH_LOCAL_PORT:-1234}"
HEARTH_WEBUI_PORT="${HEARTH_WEBUI_PORT:-3000}"
HEARTH_URL="http://127.0.0.1:${HEARTH_LOCAL_PORT}/v1"

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

_hearth_tunnel_up() {
  # A listener on the local port is not proof the tunnel works, but no
  # listener is proof it does not.
  if command -v nc >/dev/null 2>&1; then
    nc -z 127.0.0.1 "$HEARTH_LOCAL_PORT" >/dev/null 2>&1
  else
    curl -s -m 2 -o /dev/null "http://127.0.0.1:${HEARTH_LOCAL_PORT}/" >/dev/null 2>&1
  fi
}

ai-tunnel() {
  if _hearth_tunnel_up; then
    echo "tunnel: already listening on 127.0.0.1:${HEARTH_LOCAL_PORT}"
    return 0
  fi
  # ExitOnForwardFailure: fail loudly instead of a half-open tunnel.
  ssh -f -N \
    -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
    -L "127.0.0.1:${HEARTH_LOCAL_PORT}:127.0.0.1:1234" \
    -L "127.0.0.1:${HEARTH_WEBUI_PORT}:127.0.0.1:3000" \
    "$HEARTH_SSH" \
    && echo "tunnel: up (LM Studio → 127.0.0.1:${HEARTH_LOCAL_PORT}, WebUI → 127.0.0.1:${HEARTH_WEBUI_PORT})"
}

ai-tunnel-stop() {
  pkill -f "ssh -f -N .*-L 127.0.0.1:${HEARTH_LOCAL_PORT}:127.0.0.1:1234" && echo "tunnel: stopped" || echo "tunnel: none running"
}

ai-ping() {
  _k=$(_hearth_secret "$HOME/.hearth-key") || return 1
  if ! _hearth_tunnel_up; then
    echo "DOWN — no tunnel on 127.0.0.1:${HEARTH_LOCAL_PORT}. Run: ai-tunnel"
    unset _k; return 1
  fi
  _c=$(printf 'header = "Authorization: Bearer %s"\n' "$_k" \
       | curl -s -m 8 -o /dev/null -w '%{http_code}' -K - "${HEARTH_URL}/models")
  unset _k
  case "$_c" in
    200) echo "up" ;;
    401) echo "BAD TOKEN — ~/.hearth-key was refused (revoked, or wrong machine's token)" ;;
    000) echo "NO ANSWER — tunnel listening but the host did not reply (asleep? LM Studio down? on the host: scripts/boot.sh)" ;;
    *)   echo "HTTP ${_c}" ;;
  esac
  [ "$_c" = "200" ]
}

ai-models() {
  _k=$(_hearth_secret "$HOME/.hearth-key") || return 1
  printf 'header = "Authorization: Bearer %s"\n' "$_k" \
    | curl -s -m 8 -K - "${HEARTH_URL}/models" \
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
  _k=$(_hearth_secret "$HOME/.hearth-key") || return 1
  python3 -c 'import json, sys; print(json.dumps({"model": "local-big", "messages": [{"role": "user", "content": " ".join(sys.argv[1:])}]}))' "$@" \
    > "${TMPDIR:-/tmp}/hearth-ask.$$"
  printf 'header = "Authorization: Bearer %s"\n' "$_k" \
    | curl -s -m 300 -K - -H 'Content-Type: application/json' \
        --data-binary @"${TMPDIR:-/tmp}/hearth-ask.$$" "${HEARTH_URL}/chat/completions" \
    | python3 -c 'import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    print("no response — ai-ping"); raise SystemExit(1)
if "error" in d: print("error:", d["error"]); raise SystemExit(1)
print((d["choices"][0]["message"].get("content") or "").strip())'
  rm -f "${TMPDIR:-/tmp}/hearth-ask.$$"; unset _k
}

ai-webui() {
  _hearth_tunnel_up || ai-tunnel || return 1
  _u="http://127.0.0.1:${HEARTH_WEBUI_PORT}"
  echo "Open WebUI: ${_u}  (the host's instance — same login and history)"
  command -v open >/dev/null 2>&1 && open "$_u" || { command -v xdg-open >/dev/null 2>&1 && xdg-open "$_u" >/dev/null 2>&1; }
  unset _u
}

# ---------------------------------------------------------------- aider
# The token is injected per invocation, never exported. Every local alias is
# local-big (D1); clients call roles, never models.
_hearth_aider() {
  _k=$(_hearth_secret "$HOME/.hearth-key") || return 1
  _hearth_tunnel_up || ai-tunnel || { unset _k; return 1; }
  OPENAI_API_BASE="$HEARTH_URL" OPENAI_API_KEY="$_k" \
    aider --model openai/local-big --weak-model openai/local-big "$@"
  _rc=$?; unset _k; return $_rc
}
alias ask='_hearth_aider'
alias ask-big='_hearth_aider'
alias ask-local='_hearth_aider'
alias ask-chat='_hearth_aider'
alias ask-fast='_hearth_aider'
ask-arch() { _hearth_aider --architect --editor-model openai/local-big "$@"; }

# The only command that leaves for the cloud, with THIS machine's own key.
ask-cloud() {
  [ -n "${HEARTH_CLOUD_MODEL:-}" ] || { echo "hearth: set HEARTH_CLOUD_MODEL (scripts/client-setup.sh prints it)" >&2; return 1; }
  _g=$(_hearth_secret "$HOME/.hearth-gemini-key") || return 1
  GEMINI_API_KEY="$_g" aider --model "gemini/${HEARTH_CLOUD_MODEL}" --weak-model "gemini/${HEARTH_CLOUD_MODEL}" "$@"
  _rc=$?; unset _g; return $_rc
}
