#!/bin/bash
# Concurrency bench — N simultaneous agent turns against one role.
# See docs/MIGRATION-LMSTUDIO.md phase 0 and bench/concurrency.py.
#
#   scripts/concurrency-bench.sh --base-url http://127.0.0.1:1234/v1 \
#       --token-env LMSTUDIO_HOST_TOKEN --model local-big --concurrency 3
#
# Options (defaults): --concurrency 3, --rounds 10, --prompt-tokens 30000,
#   --timeout 180, --proc-match '(\.lmstudio/|LM Studio)', --out <auto>,
#   --label TEXT, --note-log FILE (repeatable).
#
# The token is read from the named env var (after loading the hearth env
# files), never passed on the command line.
#
# Exit 0 all requests valid, 1 at least one failure, 2 could not run.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"
ai_load_env

PY=""
for p in /usr/bin/python3 /opt/homebrew/bin/python3 python3; do
  if command -v "$p" >/dev/null 2>&1 && "$p" -c 'import sys; sys.exit(sys.version_info < (3, 8))' 2>/dev/null; then
    PY="$p"; break
  fi
done
[ -n "$PY" ] || { echo "could not run: no python3 >= 3.8" >&2; exit 2; }
command -v footprint >/dev/null 2>&1 || { echo "could not run: footprint(1) not found" >&2; exit 2; }

CONC=3
OUT=""
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --concurrency) CONC="${2:?}"; ARGS+=("$1" "$2"); shift 2 ;;
    --out) OUT="${2:?}"; shift 2 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) ARGS+=("$1"); shift ;;
  esac
done
[ -n "$OUT" ] || OUT="${ROOT}/bench/results/$(date +%Y-%m-%d-%H%M)-concurrency-c${CONC}"

# The bench process needs the LM Studio token. Nothing else in the env file
# goes with it — GOOGLE_API_KEY stays unexported (ai_load_env).
export LMSTUDIO_HOST_TOKEN
exec "$PY" -I "${ROOT}/bench/concurrency.py" --root "$ROOT" --out "$OUT" \
  ${ARGS[@]+"${ARGS[@]}"}
