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

# oMLX on localhost (ADR 0026, 0048). Default local chat is the resident
# role (main-brain on every tier). There is no router, so a role name is the
# model id and nothing can fall back.
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

# Resident chat role for this host (main-brain, ADR 0048).
# lib.sh reads roles.tsv under ROOT, which scripts set and a shell does not.
_hearth_resident() {
  ( ROOT="$HEARTH_ROOT"; hearth_resident_roles ) | awk -F'\t' '$1 !~ /edit/ {print $1; exit}'
}

_aider_local() {
  local tok role
  tok="$(_hearth_var OMLX_HOST_TOKEN)" || return 1
  role="$(_hearth_resident)"
  [ -n "$role" ] || { echo "no resident role in roles.tsv for this host" >&2; return 1; }
  OPENAI_API_BASE="$HEARTH_LOCAL" \
  OPENAI_API_KEY="$tok" \
  aider --model "openai/${role}" "$@"
}

# --- local: stays on this machine, safe for client / sensitive work ---
alias ask='_aider_local'
# Role-named commands (ADR 0039, 0048). main-brain is the resident, so
# ask-main is ask under an older name and loads nothing.
main-brain() { _aider_local "$@"; }
ask-main() { _aider_local "$@"; }

# Architect mode with the same model on both sides: the design step stays
# visible, and nothing is evicted because there is only one model.
ask-arch() {
  local tok role
  tok="$(_hearth_var OMLX_HOST_TOKEN)" || return 1
  role="$(_hearth_resident)"
  [ -n "$role" ] || { echo "no resident role" >&2; return 1; }
  OPENAI_API_BASE="$HEARTH_LOCAL" OPENAI_API_KEY="$tok" \
    aider --architect --model "openai/${role}" --editor-model "openai/${role}" "$@"
}

# Swap roles (load=swap in roles.tsv): demand-load, aider, then put back
# what was there. Still local: safe for sensitive work. demand-load.sh
# refuses a role this host's tier has no row for (coding-brain on 48 GB).
#   coding-brain  64 GB only. Evicts main-brain; 1 slot (ADR 0047, 0048).
#   deep-brain    slow, careful, for hard one-off questions (ADR 0020, 0031).
# While a swap role is in, calls to main-brain on this host have no model
# of their own, a laptop on the tunnel included.
_hearth_swap_restore() {
  [ "${_hearth_swap_state:-}" = loaded ] || return 0
  _hearth_swap_state=restored
  "${HEARTH_ROOT}/scripts/demand-load.sh" "$_hearth_swap_role" down
}

_hearth_swap_session() {
  setopt localoptions localtraps 2>/dev/null || true
  local tok rc role="$1"
  shift
  tok="$(_hearth_var OMLX_HOST_TOKEN)" || return 1
  _hearth_swap_role="$role"
  _hearth_swap_state=$("${HEARTH_ROOT}/scripts/demand-load.sh" "$role" up) || return 1
  # already: a manual `up`, or a session this shell did not start. Leave it
  # loaded. loaded: this call brought it in, so the trap unloads it on the
  # way out, including Ctrl-C, and restores the prior agent.
  if [ "$_hearth_swap_state" != loaded ]; then
    echo "${role} is already loaded; this session will not unload it." >&2
    echo "When you are finished: scripts/demand-load.sh ${role} down" >&2
  else
    trap _hearth_swap_restore EXIT INT TERM
  fi
  # weak-model is the same role: a commit step should use the model the
  # session just asked, and the resident is not loaded to answer it.
  OPENAI_API_BASE="$HEARTH_LOCAL" OPENAI_API_KEY="$tok" \
    aider --model "openai/${role}" --weak-model "openai/${role}" "$@"
  rc=$?
  return $rc
}

coding-brain() { _hearth_swap_session coding-brain "$@"; }
ask-coding()   { _hearth_swap_session coding-brain "$@"; }
deep-brain()   { _hearth_swap_session deep-brain "$@"; }
ask-deep()     { _hearth_swap_session deep-brain "$@"; }

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
