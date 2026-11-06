#!/bin/bash
# Edit-prediction latency bench for local-edit on the host (ADR 0033).
# Runs bench/edit_bench.py against oMLX on :1234 with the host token.
#
#   scripts/edit-bench.sh                     # 6 rounds of bench/edit/
#   scripts/edit-bench.sh --duration 600      # loop, to run beside:
#   scripts/concurrency-bench.sh --base-url http://127.0.0.1:1234/v1 \
#       --token-env OMLX_HOST_TOKEN --model local-main --concurrency 3
#
# Pass: p95 ≤ 500 ms with no errors alone, and local-main's TTFT within
# 10% of its last concurrency baseline while the loop runs.
# A laptop runs the same bench on its own oMLX: client/edit-model.sh bench.
#
# Exit 0 no errors, 1 errors, 2 could not run.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"
ai_load_env
[ -n "${OMLX_HOST_TOKEN:-}" ] || { echo "could not run: OMLX_HOST_TOKEN not set (${HEARTH_ENV})" >&2; exit 2; }
hearth_edit_roles | grep -q . || { echo "could not run: no edit role for this host's tier" >&2; exit 2; }
export OMLX_HOST_TOKEN

STAMP="$(date +%Y-%m-%d-%H%M)"
OUT="${ROOT}/bench/results/${STAMP}-edit"
/usr/bin/python3 -I "${ROOT}/bench/edit_bench.py" --base-url "$HEARTH_URL" \
  --key-env OMLX_HOST_TOKEN --out "$OUT" --label "host $(hearth_ram_gb || echo ?) GB" "$@"
