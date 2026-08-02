# Shared helpers. Source, don't execute.
#
#   . "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

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
           LITELLM_LAN_KEY LITELLM_ROAM_KEY GOOGLE_API_KEY ANTHROPIC_API_KEY \
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
