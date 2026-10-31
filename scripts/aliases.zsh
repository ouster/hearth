# Role-based aliases. Replaces model-name aliases in ~/.zshrc.
#
#   source /path/to/hearth/scripts/aliases.zsh
#
# Nothing here names a model. Swapping what backs a role is a config/roles.tsv
# change; these aliases never move. That is the whole point.

# Repo root: prefer HEARTH_ROOT (or legacy AI_STACK_ROOT), else this file's dir.
if [ -n "${HEARTH_ROOT:-}" ]; then
  :
elif [ -n "${AI_STACK_ROOT:-}" ]; then
  HEARTH_ROOT="$AI_STACK_ROOT"
elif [ -n "${BASH_SOURCE[0]:-}" ]; then
  HEARTH_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
elif [ -n "${ZSH_VERSION:-}" ]; then
  HEARTH_ROOT="$(cd "$(dirname "${(%):-%x}")/.." && pwd)"
else
  HEARTH_ROOT="${HOME}/hearth"
fi
export HEARTH_ROOT

# LM Studio (llmster) on localhost — ADR 0016. Every local alias is
# local-big (D1); there is no router, so a role name is an LM Studio
# --identifier and nothing can fall back anywhere.
HEARTH_LOCAL="${HEARTH_LOCAL:-http://127.0.0.1:1234/v1}"
HEARTH_LMS="${HEARTH_LMS:-$HOME/.lmstudio/bin/lms}"
. "${HEARTH_ROOT}/scripts/lib.sh"

# Read one NAME=value from ~/.config/hearth/env WITHOUT sourcing it. Sourcing
# would export every secret in it into this shell and every process started
# from it — aider, any agent it spawns, any npm
# postinstall. Each alias injects only the one secret it needs, per call.
_hearth_var() {
  local name="$1" f line val
  for f in "$HOME/.config/hearth/env"; do
    [ -f "$f" ] || continue
    line=$(grep -E "^[[:space:]]*(export[[:space:]]+)?${name}=" "$f" | tail -1)
    [ -n "$line" ] || continue
    val="${line#*=}"; val="${val%\"}"; val="${val#\"}"; val="${val%\'}"; val="${val#\'}"
    case "$val" in ''|*...|CHANGEME|*CHANGEME*) continue ;; esac
    printf '%s' "$val"; return 0
  done
  printf '%s is not set in ~/.config/hearth/env.\n' "$name" >&2
  return 1
}

_aider_local() {
  local tok; tok="$(_hearth_var LMSTUDIO_HOST_TOKEN)" || return 1
  OPENAI_API_BASE="$HEARTH_LOCAL" \
  OPENAI_API_KEY="$tok" \
  aider --model openai/local-big "$@"
}

# --- local: stays on this machine, safe for client / sensitive work ---
# ask-fast, ask-local, ask-chat, ask-big and ask-architect are kept as names
# so muscle memory still works; they all mean local-big now (D1).
alias ask='_aider_local'
alias ask-fast='_aider_local'
alias ask-local='_aider_local'
alias ask-chat='_aider_local'
alias ask-big='_aider_local'
alias ask-architect='_aider_local'

# Architect mode with the same model on both sides: the design step stays
# visible, and nothing is evicted because there is only one model.
ask-arch() { _aider_local --architect --editor-model openai/local-big "$@"; }

# --- cloud: the only alias that can leave the host. Non-sensitive repos only.
# Model id comes from config/roles.tsv so this file never names a model.
ask-cloud() {
  local id key
  id=$(awk -F'\t' '$1 == "cloud-cheap" && $2 == "gemini" {print $3; exit}' "${HEARTH_ROOT}/config/roles.tsv")
  [ -n "$id" ] || { echo "cloud-cheap missing from config/roles.tsv" >&2; return 1; }
  key="$(_hearth_var GOOGLE_API_KEY)" || return 1
  # --weak-model too: ~/.aider.conf.yml says openai/local-big, which without
  # OPENAI_API_BASE would send commit messages to api.openai.com.
  GEMINI_API_KEY="$key" aider --model "gemini/${id}" --weak-model "gemini/${id}" "$@"
}

# --- utilities ---
alias ai-health='"${HEARTH_ROOT}/scripts/healthcheck.sh"'
alias ai-status='"${HEARTH_ROOT}/scripts/status.sh"'
alias ai-boot='"${HEARTH_ROOT}/scripts/boot.sh"'
alias ai-load='"${HEARTH_ROOT}/scripts/lms-load.sh"'
alias ai-loaded='"$HEARTH_LMS" ps'
ai-restart() { "$HEARTH_LMS" server stop; "$HEARTH_LMS" server start --bind 127.0.0.1 -p 1234; }
alias ai-log='"$HEARTH_LMS" log stream'
