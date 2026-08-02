#!/bin/bash
# Find which part of config.yaml makes LiteLLM drop every model_list entry.
#
#   scripts/bisect-config.sh
#
# Runs throwaway LiteLLM instances on port 4001 with progressively richer
# configs and asks each one what models it has. Never touches :4000, the live
# config, launchd, or the database.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"
ai_load_env "$ROOT"

VENV="${LITELLM_VENV:-$HOME/.local/pipx/venvs/litellm}"
BIN="${VENV}/bin/litellm"
PORT=4001
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

[ -x "$BIN" ] || { echo "no litellm at ${BIN}"; exit 1; }

# Deliberately no DATABASE_URL and no master key: isolates model loading from
# auth and persistence.
run_variant() {
  local name="$1" cfg="$2"
  printf '\n\033[1m--- %s ---\033[0m\n' "$name"

  env -u DATABASE_URL -u LITELLM_MASTER_KEY -u STORE_MODEL_IN_DB \
    "$BIN" --config "$cfg" --port "$PORT" >"${TMP}/${name}.log" 2>&1 &
  local pid=$!

  local up=false
  for _ in $(seq 1 25); do
    curl -s -m 2 -o /dev/null "http://127.0.0.1:${PORT}/health/readiness" && { up=true; break; }
    kill -0 "$pid" 2>/dev/null || break
    sleep 1
  done

  if ! $up; then
    echo "  did not start. Last log lines:"
    tail -12 "${TMP}/${name}.log" | sed 's/^/    /'
  else
    local n
    n=$(curl -s -m 5 "http://127.0.0.1:${PORT}/v1/models" \
        | python3 -c 'import sys,json; d=json.load(sys.stdin); print(len(d.get("data",[])))' 2>/dev/null || echo "?")
    if [ "$n" = "0" ]; then
      echo "  models loaded: 0   <-- THIS VARIANT BREAKS IT"
      grep -iE 'error|invalid|warn|skip|drop' "${TMP}/${name}.log" | tail -8 | sed 's/^/    /'
    else
      echo "  models loaded: ${n}"
    fi
  fi

  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  sleep 1
}

# ---------------------------------------------------------------- variants

cat > "${TMP}/a.yaml" <<'EOF'
model_list:
  - model_name: local-fast
    litellm_params:
      model: ollama_chat/qwen2.5-coder:7b
      api_base: http://127.0.0.1:11434
EOF

cat > "${TMP}/b.yaml" <<'EOF'
model_list:
  - model_name: local-fast
    litellm_params:
      model: ollama_chat/qwen2.5-coder:7b
      api_base: http://127.0.0.1:11434
    model_info:
      tier: local
      set_on: "2026-08-01"
      note: "quick edits"
EOF

cat > "${TMP}/c.yaml" <<'EOF'
model_list:
  - model_name: local-fast
    litellm_params:
      model: ollama_chat/qwen2.5-coder:7b
      api_base: http://127.0.0.1:11434
  - model_name: local-code
    litellm_params:
      model: ollama_chat/qwen2.5-coder:32b
      api_base: http://127.0.0.1:11434
router_settings:
  num_retries: 2
  timeout: 120
  fallbacks:
    - local-code: ["local-fast"]
EOF

# The live file, minus general_settings (db + master key).
ai_python_or_die || exit 2
"$AI_PY" - "${ROOT}/litellm/config.yaml" "${TMP}/d.yaml" <<'PY'
import sys, yaml
cfg = yaml.safe_load(open(sys.argv[1]))
cfg.pop('general_settings', None)
yaml.safe_dump(cfg, open(sys.argv[2], 'w'), sort_keys=False)
PY

run_variant "A-bare-model-only"        "${TMP}/a.yaml"
run_variant "B-plus-model_info"        "${TMP}/b.yaml"
run_variant "C-plus-router_settings"   "${TMP}/c.yaml"
run_variant "D-live-config-minus-db"   "${TMP}/d.yaml"

cat <<'EOF'

Reading this:
  A fails            -> the ollama_chat provider or litellm install itself
  A ok, B fails      -> my model_info bookkeeping fields (tier/set_on/note)
  B ok, C fails      -> router_settings / fallbacks syntax
  C ok, D fails      -> something else in the live file
  all ok             -> the file is fine; the fault is general_settings,
                        i.e. the database overlay clobbering model_list
EOF
