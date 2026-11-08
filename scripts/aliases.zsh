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

# oMLX on localhost (ADR 0026). Every local alias is main-brain (D1); there
# is no router, so a role name is the model id and nothing can fall back.
HEARTH_LOCAL="${HEARTH_LOCAL:-http://127.0.0.1:1234/v1}"
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
  local tok; tok="$(_hearth_var OMLX_HOST_TOKEN)" || return 1
  OPENAI_API_BASE="$HEARTH_LOCAL" \
  OPENAI_API_KEY="$tok" \
  aider --model openai/main-brain "$@"
}

# --- local: stays on this machine, safe for client / sensitive work ---
alias ask='_aider_local'
# Role-named commands (ADR 0039), alongside ask / ask-deep.
main-brain() { _aider_local "$@"; }
deep-brain() { ask-deep "$@"; }

# Architect mode with the same model on both sides: the design step stays
# visible, and nothing is evicted because there is only one model.
ask-arch() { _aider_local --architect --editor-model openai/main-brain "$@"; }

# Slow, careful local model for hard one-off questions (ADR 0020, 0028, 0031).
# Still local: safe for sensitive work. It evicts main-brain on every tier
# (ADR 0033), so Zed, aider and laptops get errors until the session ends. The session unloads it on the way out,
# including Ctrl-C, and main-brain is loaded again. Idempotent: INT and EXIT
# can both fire.
_hearth_ask_deep_restore() {
  [ "${_hearth_ask_deep_state:-}" = loaded ] || return 0
  _hearth_ask_deep_state=restored
  "${HEARTH_ROOT}/scripts/demand-load.sh" deep-brain down
}

ask-deep() {
  setopt localoptions localtraps
  local tok rc
  tok="$(_hearth_var OMLX_HOST_TOKEN)" || return 1
  _hearth_ask_deep_state=$("${HEARTH_ROOT}/scripts/demand-load.sh" deep-brain up) || return 1
  # already: a manual `up`, or a session this shell did not start. Leave it
  # loaded. loaded: this call brought it in, so the trap unloads it on the
  # way out, including Ctrl-C, and restores main-brain if it was evicted.
  if [ "$_hearth_ask_deep_state" != loaded ]; then
    echo "deep-brain is already loaded; this session will not unload it." >&2
    echo "When you are finished: scripts/demand-load.sh deep-brain down" >&2
  else
    trap _hearth_ask_deep_restore EXIT INT TERM
  fi
  OPENAI_API_BASE="$HEARTH_LOCAL" OPENAI_API_KEY="$tok" \
    aider --model openai/deep-brain --weak-model openai/deep-brain "$@"
  rc=$?
  return $rc
}

# No cloud alias: the host holds no cloud key (ADR 0038). ask-cloud exists
# only in client/hearth-client.sh, with the laptop's own key.

# --- utilities ---
alias ai-health='"${HEARTH_ROOT}/scripts/healthcheck.sh"'
alias ai-status='"${HEARTH_ROOT}/scripts/status.sh"'
alias ai-boot='"${HEARTH_ROOT}/scripts/boot.sh"'
alias ai-load='"${HEARTH_ROOT}/scripts/omlx.sh" up'
alias ai-loaded='"${HEARTH_ROOT}/scripts/omlx.sh" status'
ai-restart() { "${HEARTH_ROOT}/scripts/omlx.sh" down && "${HEARTH_ROOT}/scripts/omlx.sh" up; }
alias ai-log='tail -f "$HOME/Library/Logs/hearth-omlx.log"'
