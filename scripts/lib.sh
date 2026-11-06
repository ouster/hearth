# Shared helpers. Source, don't execute.
#
#   . "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
#
# oMLX on 127.0.0.1:1234 (ADR 0026). scripts/omlx.sh starts and stops it.

# launchd and non-interactive shells get a stripped PATH.
case ":${PATH:-}:" in
  *:/opt/homebrew/bin:*) ;;
  *) PATH="/opt/homebrew/bin:/usr/local/bin:${PATH:-/usr/bin:/bin:/usr/sbin:/sbin}" ;;
esac

HEARTH_PORT="${HEARTH_PORT:-1234}"
HEARTH_URL="${HEARTH_URL:-http://127.0.0.1:${HEARTH_PORT}/v1}"
HEARTH_ENV="${HEARTH_ENV:-$HOME/.config/hearth/env}"

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

# User-defined bridge. The default "podman" network does not resolve
# container names, and a port published on the Mac's 127.0.0.1 is not
# reachable from a container via host.containers.internal.
hearth_podman_net() {
  command -v podman >/dev/null 2>&1 || return 0
  podman network exists hearth || podman network create hearth >/dev/null
}

hearth_podman_connect() {
  local name="$1" nets
  hearth_podman_net
  nets=$(podman inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{println $k}}{{end}}' "$name" 2>/dev/null || true)
  case "$nets" in
    *hearth*) return 0 ;;
  esac
  podman network connect hearth "$name"
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
# outlives the script. Callers that need a child to see the API key
# export that one variable themselves. Placeholders are dropped.
ai_load_env() {
  local line name val
  [ -f "$HEARTH_ENV" ] || return 0
  for name in OMLX_HOST_TOKEN GOOGLE_API_KEY; do
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

# Listen addresses on PORT that are not 127.0.0.1 or ::1, space-separated.
# Empty when every listener is loopback, or when nothing is listening.
hearth_wan_binds() {
  local port="$1" addr bad
  bad=""
  [ -n "$port" ] || return 0
  while IFS= read -r addr; do
    [ -n "$addr" ] || continue
    case "$addr" in
      "127.0.0.1:${port}"|"[::1]:${port}") ;;
      *) bad="${bad} ${addr}" ;;
    esac
  done <<EOF
$(lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | awk '
  NR>1 {
    a=""
    for (i=1; i<=NF; i++) if ($i ~ /:[0-9]+$/) a=$i
    if (a != "") print a
  }' | sort -u)
EOF
  printf '%s' "${bad# }"
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
#   hearth_roles omlx       # one backend
hearth_roles() {
  local root="${ROOT:?ROOT not set}" b="${1:-}"
  awk -F'\t' -v b="$b" '!/^[[:space:]]*(#|$)/ && (b == "" || $2 == b) {print $1 "\t" $2 "\t" $3 "\t" $4 "\t" $5 "\t" $6}' \
    "${root}/config/roles.tsv"
}

# Resident omlx roles (column 8 is not demand). A demand role must not be
# called unless it was loaded: an unknown name can be answered by whatever
# is already loaded.
hearth_resident_roles() {
  local root="${ROOT:?ROOT not set}"
  awk -F'\t' '!/^[[:space:]]*(#|$)/ && $2 == "omlx" && $8 != "demand" {print $1 "\t" $2 "\t" $3 "\t" $4 "\t" $5 "\t" $6}' \
    "${root}/config/roles.tsv"
}

# Names of omlx roles loaded on demand, one per line.
hearth_demand_roles() {
  local root="${ROOT:?ROOT not set}"
  awk -F'\t' '!/^[[:space:]]*(#|$)/ && $2 == "omlx" && $8 == "demand" {print $1}' "${root}/config/roles.tsv"
}

# Memory envelope, sized from installed RAM (ADR 0031). Integers, GB.
# Ceiling = RAM minus 8 for macOS: 56 on 64 GB, 40 on 48 GB. It is both the
# iogpu wired limit and the oMLX memory guard.
HEARTH_OS_RESERVE_GB=8
# local-main and local-deep load together only at or above this ceiling.
# Combined peak measured 49.9 GB with the smaller resident; ~53 GB estimated
# with the current one (ADR 0028, 0030).
HEARTH_COLOAD_MIN_GB=56

hearth_ram_gb() {
  local b
  b=$(/usr/sbin/sysctl -n hw.memsize 2>/dev/null) || return 1
  [ -n "$b" ] || return 1
  printf '%s' $(( b / 1073741824 ))
}

hearth_gpu_ceiling_gb() {
  local r
  r=$(hearth_ram_gb) || return 1
  printf '%s' $(( r - HEARTH_OS_RESERVE_GB ))
}

# Exit 0 when local-deep may load beside local-main.
hearth_coload_ok() {
  local c
  c=$(hearth_gpu_ceiling_gb) || return 1
  [ "$c" -ge "$HEARTH_COLOAD_MIN_GB" ]
}

# oMLX memory footprint in GB from its pid file, e.g. "24.0". Empty if down.
hearth_footprint_gb() {
  local pid
  pid=$(cat "$HOME/.omlx/hearth.pid" 2>/dev/null || true)
  [ -n "$pid" ] || return 0
  footprint -p "$pid" 2>/dev/null | awk '/Footprint:/ {v=$2; if ($3=="MB") v/=1024; if ($3=="KB") v/=1048576; printf "%.1f", v; exit}'
}
