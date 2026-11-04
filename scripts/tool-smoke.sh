#!/bin/bash
# Zed-like agent tool smoke — read then write with '<' in file content.
#
#   scripts/tool-smoke.sh                          local-main on oMLX :1234
#   scripts/tool-smoke.sh <base_url> <model>       any OpenAI-compatible server
#
# Token: OPENAI_API_KEY if set, else OMLX_HOST_TOKEN from
# ~/.config/hearth/env. Passed by environment, never on the command line.
#
# Exit 0 = turn-2 write/edit succeeded. See bench/tool-smoke.py.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"
ai_load_env

# stdlib only — no PyYAML needed.
AI_PY=/usr/bin/python3
[ -x "$AI_PY" ] || AI_PY="$(command -v python3)" || { echo "could not run: no python3" >&2; exit 2; }

BASE="${1:-$HEARTH_URL}"
MODEL="${2:-local-main}"
OPENAI_API_KEY="${OPENAI_API_KEY:-${OMLX_HOST_TOKEN:-}}" \
  exec "$AI_PY" -I "${ROOT}/bench/tool-smoke.py" --backend openai --url "$BASE" --model "$MODEL"
