# Shared helpers. Source, don't execute.
#
#   . "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# ---- host identity (shareable defaults; override via env) --------------------
#
# Scripts never hardcode a LAN IP or a personal launchd label. Discovery order:
#   1. explicit env override
#   2. whatever agent/plist is already installed (keeps existing hosts working)
#   3. generic com.hearth.* default for fresh installs

# HEARTH_* is canonical; AI_STACK_* still accepted during the rename.
_hearth_env() {
  # usage: _hearth_env HEARTH_FOO AI_STACK_FOO
  eval "printf '%s' \"\${$1:-\${$2:-}}\""
}

# Primary LAN IPv4. Empty string if none — callers must treat that as
# INCONCLUSIVE, never as "secure". An unreachable probe looks identical to a
# closed port and is the same false-pass class as the leak-test bug.
ai_lan_ip() {
  local v
  v="$(_hearth_env HEARTH_LAN_IP AI_STACK_LAN_IP)"
  if [ -n "$v" ]; then
    printf '%s' "$v"
    return 0
  fi
  if command -v ipconfig >/dev/null 2>&1; then
    ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true
    return 0
  fi
  # Linux fallback
  hostname -I 2>/dev/null | awk '{print $1; exit}'
}

# Resolve a launchd label: env → loaded agent → on-disk plist → default.
_ai_resolve_label() {
  local env_val="$1" default="$2"
  shift 2
  if [ -n "$env_val" ]; then
    printf '%s' "$env_val"
    return 0
  fi
  local c uid
  uid="$(id -u)"
  for c in "$@"; do
    if launchctl print "gui/${uid}/${c}" >/dev/null 2>&1; then
      printf '%s' "$c"
      return 0
    fi
  done
  for c in "$@"; do
    if [ -f "$HOME/Library/LaunchAgents/${c}.plist" ]; then
      printf '%s' "$c"
      return 0
    fi
  done
  printf '%s' "$default"
}

ai_litellm_label() {
  # Prefer generic, then any pre-existing personal/legacy label so upgrades don't break.
  _ai_resolve_label "$(_hearth_env HEARTH_LITELLM_LABEL AI_STACK_LITELLM_LABEL)" \
    "com.hearth.litellm" \
    "com.hearth.litellm" "com.ai-stack.litellm" "com.colinnevin.litellm"
}

ai_ollama_label() {
  _ai_resolve_label "$(_hearth_env HEARTH_OLLAMA_LABEL AI_STACK_OLLAMA_LABEL)" \
    "com.hearth.ollama" \
    "com.hearth.ollama" "com.ai-stack.ollama" "com.colinnevin.ollama"
}

ai_boot_label() {
  _ai_resolve_label "$(_hearth_env HEARTH_BOOT_LABEL AI_STACK_BOOT_LABEL)" \
    "com.hearth.boot" \
    "com.hearth.boot" "com.ai-stack.boot" \
    "com.colinnevin.hearth-boot" "com.colinnevin.ai-stack-boot"
}

# gui/<uid>/<label> — what launchctl kickstart wants.
ai_litellm_agent() {
  printf 'gui/%s/%s' "$(id -u)" "$(ai_litellm_label)"
}

# Podman container name for a logical service. Prefers an already-running
# legacy ai-stack-* container so a rename does not orphan Postgres data.
# Fresh installs get hearth-*.
ai_container() {
  local kind="$1" c
  for c in "hearth-${kind}" "ai-stack-${kind}"; do
    if command -v podman >/dev/null 2>&1 && podman container exists "$c" 2>/dev/null; then
      printf '%s' "$c"
      return 0
    fi
  done
  printf 'hearth-%s' "$kind"
}

ai_volume() {
  local kind="$1" v
  for v in "hearth-${kind}" "ai-stack-${kind}"; do
    if command -v podman >/dev/null 2>&1 && podman volume exists "$v" 2>/dev/null; then
      printf '%s' "$v"
      return 0
    fi
  done
  printf 'hearth-%s' "$kind"
}

# macOS system python3 has no PyYAML and you cannot pip into it without
# --break-system-packages. LiteLLM's own pipx venv already has yaml, so prefer
# that over asking the user to install anything.
ai_python() {
  local p
  for p in \
    "$HOME/.local/pipx/venvs/litellm/bin/python" \
    /opt/homebrew/bin/python3 \
    /usr/local/bin/python3 \
    python3
  do
    if command -v "$p" >/dev/null 2>&1 && "$p" -c 'import yaml' >/dev/null 2>&1; then
      printf '%s' "$p"; return 0
    fi
  done
  return 1
}

AI_PY="$(ai_python || true)"

# Load both env files, service first then repo.
#
#   ~/.config/litellm/env      what launchd gives the gateway — master key,
#                              provider keys, DATABASE_URL
#   <repo>/litellm/.env        script-only — POSTGRES_PASSWORD, virtual keys
#
# Scripts need both, and requiring the caller to `source` by hand before every
# invocation is a trap: it fails at the worst moment, mid-deploy.
ai_load_env() {
  local root="${1:-${ROOT:-}}"
  set -a
  # Repo .env FIRST. It is copied from .env.example and routinely still holds
  # placeholders, so it must never win over the service env.
  [ -n "$root" ] && [ -f "${root}/litellm/.env" ] && . "${root}/litellm/.env"
  # Service env LAST — authoritative for anything launchd also sees.
  [ -f "$HOME/.config/litellm/env" ] && . "$HOME/.config/litellm/env"
  set +a

  # Drop untouched .env.example placeholders. An unset var produces a clear
  # "not found" error; a placeholder produces a 401 against a healthy gateway,
  # which is far harder to diagnose.
  local v val
  for v in LITELLM_MASTER_KEY LITELLM_PRIVATE_KEY LITELLM_GENERAL_KEY \
           LITELLM_LAN_KEY LITELLM_LAN_CLOUD_KEY GOOGLE_API_KEY ANTHROPIC_API_KEY \
           OPENROUTER_API_KEY MOONSHOT_API_KEY FIREWORKS_API_KEY \
           POSTGRES_PASSWORD DATABASE_URL
  do
    eval "val=\${${v}:-}"
    case "$val" in
      ''|*...|CHANGEME|*CHANGEME*) unset "$v" ;;
    esac
  done
  return 0
}

# Report placeholder values still sitting in the repo .env.
#
# Must strip inline comments the way the shell does. .env.example writes
#   LITELLM_MASTER_KEY=sk-...            # admin. Was hardcoded ...
# where sourcing yields "sk-..." but a naive read yields the comment too, so
# the placeholder silently fails to match.
ai_placeholders() {
  local f="${1:?}" out="" k v
  [ -f "$f" ] || return 0
  while IFS='=' read -r k v; do
    k="${k#"${k%%[![:space:]]*}"}"          # ltrim key
    case "$k" in ''|\#*) continue ;; esac
    k="${k#export }"
    v="${v%%#*}"                            # drop inline comment
    v="${v%"${v##*[![:space:]]}"}"          # rtrim
    v="${v#\"}"; v="${v%\"}"                # unquote
    case "$v" in
      *...|CHANGEME|*CHANGEME*) out="${out} ${k}" ;;
    esac
  done < "$f"
  printf '%s' "$out"
}

ai_python_or_die() {
  if [ -z "${AI_PY:-}" ]; then
    cat >&2 <<'EOF'
No python3 with PyYAML found.

This is a tooling problem, not a config problem — no conclusion below is valid.

Fix with any one of:
  brew install python                          # then pip3 install pyyaml
  pip3 install --user --break-system-packages pyyaml
  "$HOME/.local/pipx/venvs/litellm/bin/pip" install pyyaml
EOF
    return 1
  fi
  return 0
}
