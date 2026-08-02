# Role-based aliases. Replaces model-name aliases in ~/.zshrc.
#
#   source /path/to/hearth/scripts/aliases.zsh
#
# Nothing here names a model. Swapping what backs a role is a config.yaml
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

HEARTH_GATEWAY="${HEARTH_GATEWAY:-${AI_STACK_GATEWAY:-http://127.0.0.1:4000}}"

# Load keys WITHOUT exporting them. `set -a` here would put the master key, all
# four virtual keys and POSTGRES_PASSWORD into the environment of every process
# started from this shell — aider, any agent it spawns, any npm postinstall.
# The aliases below inject only the one key a command needs, per invocation.
if [ -f "${HEARTH_ROOT}/litellm/.env" ]; then
  . "${HEARTH_ROOT}/litellm/.env"
fi
. "${HEARTH_ROOT}/scripts/lib.sh"

# No fallback to the master key. It used to fall back so things worked before
# Postgres existed, and the cost was that `ask` — labelled private — would run
# on an unscoped, uncapped, unattributable credential whenever the scoped key
# was missing. Scope is meant to be structural (see rule 3); a boundary that
# quietly reverts to intent when a variable is unset is not one. Fail loudly.
_ai_key() {
  local want val
  case "$1" in
    private) want=LITELLM_PRIVATE_KEY ;;
    *)       want=LITELLM_GENERAL_KEY ;;
  esac
  eval "val=\${${want}:-}"
  if [ -z "$val" ]; then
    printf '%s is not set.\n' "$want" >&2
    printf 'Refusing to fall back to the master key: it can reach every role.\n' >&2
    printf 'Fix: scripts/create-keys.sh, then paste the value into litellm/.env\n' >&2
    return 1
  fi
  printf '%s' "$val"
}

_aider_role() {
  local role="$1" scope="$2" key; shift 2
  key="$(_ai_key "$scope")" || return 1
  OPENAI_API_BASE="${HEARTH_GATEWAY}/v1" \
  OPENAI_API_KEY="$key" \
  aider --model "openai/${role}" "$@"
}

# --- private: local models only, safe for client / sensitive work ---
# ask-fast now means local-chat: local-fast was retired when the coding MoE
# made a separate small coder pointless.
alias ask-fast='_aider_role local-chat private'
alias ask-local='_aider_role local-code private'
alias ask-big='_aider_role local-big private'
alias ask-chat='_aider_role local-chat private'   # general questions, not code

# Architect mode: local-big reasons about the change, local-code writes the
# diff. Both roles stay resident so nothing evicts. Keeps the design decision
# visible instead of buried in a patch. See docs/IDES.md.
#
# Distinct from ask-architect, which just points aider at local-big normally.
ask-arch() {
  local key; key="$(_ai_key private)" || return 1
  OPENAI_API_BASE="${HEARTH_GATEWAY}/v1" \
  OPENAI_API_KEY="$key" \
  aider --architect --model openai/local-big --editor-model openai/local-code "$@"
}

# `ask` defaults LOCAL, not cloud. Deliberate: the safe default should be the
# private one; reaching for cloud should be explicit.
alias ask='_aider_role local-code private'

# --- general: may reach cloud. Non-sensitive repos only ---
alias ask-cloud='_aider_role cloud-cheap general'

# Dormant until their roles are enabled in config.yaml:
# alias ask-claude='_aider_role cloud-code general'
# alias ask-frontier='_aider_role cloud-frontier general'

# --- utilities ---
alias ai-health='"${HEARTH_ROOT}/scripts/healthcheck.sh"'
alias ai-audit='"${HEARTH_ROOT}/scripts/audit-fallbacks.sh"'
alias ai-status='"${HEARTH_ROOT}/scripts/status.sh"'
alias ai-boot='"${HEARTH_ROOT}/scripts/boot.sh"'
alias ai-db='"${HEARTH_ROOT}/scripts/db.sh"'
ai-restart() { launchctl kickstart -k "$(ai_litellm_agent)"; }
alias ai-log='tail -f "$HOME/Library/Logs/litellm.error.log"'
alias ai-loaded='ollama ps'
alias ask-architect='_aider_role local-big private'
