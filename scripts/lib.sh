# Shared helpers. Source, don't execute.
#
#   . "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
#
# LM Studio on 127.0.0.1:1234 (ADR 0016). The app owns the server (D6);
# `lms` drives whichever daemon is running.

# launchd and non-interactive shells get a stripped PATH.
case ":${PATH:-}:" in
  *:/opt/homebrew/bin:*) ;;
  *) PATH="/opt/homebrew/bin:/usr/local/bin:${PATH:-/usr/bin:/bin:/usr/sbin:/sbin}" ;;
esac

HEARTH_LMS="${HEARTH_LMS:-$HOME/.lmstudio/bin/lms}"
HEARTH_PORT="${HEARTH_PORT:-1234}"
HEARTH_URL="${HEARTH_URL:-http://127.0.0.1:${HEARTH_PORT}/v1}"
HEARTH_ENV="${HEARTH_ENV:-$HOME/.config/hearth/env}"
HEARTH_APP="${HEARTH_APP:-/Applications/LM Studio.app}"
LMS_SERVER_CFG="$HOME/.lmstudio/.internal/http-server-config.json"

# HEARTH_* is canonical; AI_STACK_* still accepted during the rename.
_hearth_env() {
  # usage: _hearth_env HEARTH_FOO AI_STACK_FOO
  eval "printf '%s' \"\${$1:-\${$2:-}}\""
}

# Primary LAN IPv4. Empty string if none — callers must treat that as
# INCONCLUSIVE, never as "secure". An unreachable probe looks identical to a
# closed port.
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
  hostname -I 2>/dev/null | awk '{print $1; exit}'
}

ai_boot_label() {
  local v; v="$(_hearth_env HEARTH_BOOT_LABEL AI_STACK_BOOT_LABEL)"
  printf '%s' "${v:-com.hearth.boot}"
}

# Podman container name for a logical service. Prefers an already-running
# legacy ai-stack-* container so a rename does not orphan data.
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

# Read the two secrets into THIS shell without exporting them. `set -a` would
# hand both to every child — including the Podman VM boot.sh starts, which
# outlives the script. Callers that need a child to see the LM Studio token
# export that one variable themselves. Placeholders are dropped.
ai_load_env() {
  local line name val
  [ -f "$HEARTH_ENV" ] || return 0
  for name in LMSTUDIO_HOST_TOKEN GOOGLE_API_KEY; do
    line=$(grep -E "^[[:space:]]*(export[[:space:]]+)?${name}=" "$HEARTH_ENV" | tail -1 || true)
    if [ -z "$line" ]; then
      unset "$name"
      continue
    fi
    val="${line#*=}"
    val="${val%\"}"; val="${val#\"}"; val="${val%\'}"; val="${val#\'}"
    case "$val" in
      ''|*...|CHANGEME|*CHANGEME*) unset "$name" ;;
      *) printf -v "$name" '%s' "$val"; export -n "$name" ;;
    esac
  done
  return 0
}

# `lms server start --cors` only turns CORS on; there is no flag to turn it
# off. Write loopback + CORS off into the saved settings, then start without
# --cors so a restart cannot come up on the LAN or with CORS.
hearth_lock_loopback() {
  [ -f "$LMS_SERVER_CFG" ] || return 0
  /usr/bin/python3 -I -c '
import json, sys
path, bind, port = sys.argv[1], sys.argv[2], int(sys.argv[3])
try:
    with open(path) as fh:
        cfg = json.load(fh)
except Exception:
    sys.exit(0)
cfg["networkInterface"] = bind
cfg["port"] = port
cfg["cors"] = False
with open(path, "w") as fh:
    json.dump(cfg, fh, indent=2)
    fh.write("\n")
' "$LMS_SERVER_CFG" "127.0.0.1" "$HEARTH_PORT"
}

hearth_server_start() {
  hearth_lock_loopback || return 1
  "$HEARTH_LMS" server start --bind 127.0.0.1 -p "$HEARTH_PORT"
}

# `lms` exists and a daemon (the app's, D6) answers.
hearth_lms_ok() {
  [ -x "$HEARTH_LMS" ] && "$HEARTH_LMS" daemon status >/dev/null 2>&1
}

# Which daemon owns ~/.lmstudio: "app", "llmster", or "none".
hearth_daemon_owner() {
  local s
  s=$("$HEARTH_LMS" daemon status 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')
  case "$s" in
    *"LM Studio v"*"is running"*) printf 'app' ;;
    *"llmster v"*"is running"*)   printf 'llmster' ;;
    *)                            printf 'none' ;;
  esac
}

# HTTP status for GET <path> on the server. "000" means no answer.
#   hearth_http /models            # no token
#   hearth_http /models "$TOKEN"
hearth_http() {
  local path="$1" tok="${2:-}" base="${3:-$HEARTH_URL}"
  if [ -n "$tok" ]; then
    # Token via stdin config, not argv, so it never shows in ps.
    printf 'header = "Authorization: Bearer %s"\n' "$tok" \
      | curl -s -m 5 -o /dev/null -w '%{http_code}' -K - "${base}${path}" 2>/dev/null
  else
    curl -s -m 5 -o /dev/null -w '%{http_code}' "${base}${path}" 2>/dev/null
  fi
}

# Rows of config/roles.tsv, tab-separated: role backend key ctx slots weights.
#   hearth_roles            # all rows
#   hearth_roles lmstudio   # one backend
hearth_roles() {
  local root="${ROOT:?ROOT not set}" b="${1:-}"
  awk -F'\t' -v b="$b" '!/^[[:space:]]*(#|$)/ && (b == "" || $2 == b) {print $1 "\t" $2 "\t" $3 "\t" $4 "\t" $5 "\t" $6}' \
    "${root}/config/roles.tsv"
}

# Like `hearth_roles lmstudio`, minus roles loaded on demand (column 8).
# With JIT off, a request for a role that is not loaded is answered by
# whatever IS loaded, so a demand role must never be called unless loaded.
hearth_resident_roles() {
  local root="${ROOT:?ROOT not set}"
  awk -F'\t' '!/^[[:space:]]*(#|$)/ && $2 == "lmstudio" && $8 != "demand" {print $1 "\t" $2 "\t" $3 "\t" $4 "\t" $5 "\t" $6}' \
    "${root}/config/roles.tsv"
}

# Names of lmstudio roles loaded on demand, one per line.
hearth_demand_roles() {
  local root="${ROOT:?ROOT not set}"
  awk -F'\t' '!/^[[:space:]]*(#|$)/ && $2 == "lmstudio" && $8 == "demand" {print $1}' "${root}/config/roles.tsv"
}

# LM Studio's memory footprint in GB, summed over its processes, e.g. "25.2".
hearth_footprint_gb() {
  local p
  for p in $(pgrep -f '\.lmstudio/|LM Studio'); do
    footprint -p "$p" 2>/dev/null | grep -o 'Footprint: [0-9.]* [KMG]B' | head -1
  done | awk '{v=$2; if ($3=="MB") v/=1024; if ($3=="KB") v/=1048576; s+=v} END {printf "%.1f", s}'
}

# One key from LM Studio's server settings file, or "" if unreadable.
hearth_server_setting() {
  /usr/bin/python3 -I -c '
import json, sys
try:
    v = json.load(open(sys.argv[1])).get(sys.argv[2])
except Exception:
    sys.exit(0)
print("" if v is None else (str(v).lower() if isinstance(v, bool) else v))
' "$LMS_SERVER_CFG" "$1"
}
