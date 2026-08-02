# Role-based aliases. Replaces the four model-name aliases in ~/.zshrc.
#
#   source ~/dev/ai-stack/scripts/aliases.zsh
#
# Nothing here names a model. Swapping what backs a role is a config.yaml
# change; these aliases never move. That is the whole point.

AI_STACK_GATEWAY="${AI_STACK_GATEWAY:-http://127.0.0.1:4000}"

# Load keys if present. Falls back to master key so things work pre-Postgres.
[ -f "$HOME/dev/ai-stack/litellm/.env" ] && {
  set -a; . "$HOME/dev/ai-stack/litellm/.env"; set +a
}

_ai_key() {
  # $1 = private | general
  case "$1" in
    private) printf '%s' "${LITELLM_PRIVATE_KEY:-$LITELLM_MASTER_KEY}" ;;
    *)       printf '%s' "${LITELLM_GENERAL_KEY:-$LITELLM_MASTER_KEY}" ;;
  esac
}

_aider_role() {
  local role="$1" scope="$2"; shift 2
  OPENAI_API_BASE="${AI_STACK_GATEWAY}/v1" \
  OPENAI_API_KEY="$(_ai_key "$scope")" \
  aider --model "openai/${role}" "$@"
}

# --- private: local models only, safe for client work ---
# ask-fast now means local-chat: local-fast was retired when qwen3-coder:30b
# (MoE, ~3B active) made a separate small coder pointless.
alias ask-fast='_aider_role local-chat private'
alias ask-local='_aider_role local-code private'
alias ask-big='_aider_role local-big private'
alias ask-chat='_aider_role local-chat private'   # general questions, not code

# `ask` now defaults LOCAL, not cloud. The old `ask` pointed at an Anthropic
# model with no API key set, so it was broken anyway. Deliberate: the safe
# default should be the private one, and reaching for cloud should be explicit.
alias ask='_aider_role local-code private'

# --- general: may reach cloud. Non-sensitive repos only ---
alias ask-cloud='_aider_role cloud-cheap general'

# Dormant until their roles are enabled in config.yaml:
# alias ask-claude='_aider_role cloud-code general'
# alias ask-frontier='_aider_role cloud-frontier general'

# --- utilities ---
alias ai-health='"$HOME/dev/ai-stack/scripts/healthcheck.sh"'
alias ai-audit='"$HOME/dev/ai-stack/scripts/audit-fallbacks.sh"'
alias ai-db='"$HOME/dev/ai-stack/scripts/db.sh"'
alias ai-restart='launchctl kickstart -k "gui/$(id -u)/com.colinnevin.litellm"'
alias ai-log='tail -f "$HOME/Library/Logs/litellm.error.log"'
alias ai-loaded='ollama ps'
alias ask-architect='_aider_role local-big private'
