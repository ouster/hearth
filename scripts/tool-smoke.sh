#!/bin/bash
# Zed-like agent tool smoke — read then write with '<' in file content.
#
#   scripts/tool-smoke.sh ollama gpt-oss:20b
#   scripts/tool-smoke.sh ollama qwen3-coder:30b
#   scripts/tool-smoke.sh openai http://127.0.0.1:8000/v1 default
#
# Exit 0 = turn-2 write/edit succeeded. See bench/tool-smoke.py.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"
ai_python_or_die || exit 2

BACKEND="${1:-ollama}"
shift || true

case "$BACKEND" in
  ollama)
    MODEL="${1:?model name, e.g. gpt-oss:20b}"
    URL="${OLLAMA_API_BASE:-http://127.0.0.1:11434}"
    exec "$AI_PY" "${ROOT}/bench/tool-smoke.py" --backend ollama --url "$URL" --model "$MODEL"
    ;;
  openai)
    BASE="${1:?base URL, e.g. http://127.0.0.1:8000/v1}"
    MODEL="${2:?model id}"
    KEY="${OPENAI_API_KEY:-mlx}"
    exec "$AI_PY" "${ROOT}/bench/tool-smoke.py" --backend openai --url "$BASE" --model "$MODEL" --api-key "$KEY"
    ;;
  *)
    echo "usage: $0 ollama <model>"
    echo "       $0 openai <base_url> <model>"
    exit 2
    ;;
esac
