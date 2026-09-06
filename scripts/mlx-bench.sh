#!/bin/bash
# Stage-1 MLX vs Ollama agent bench — tool smoke + optional code bench.
#
#   scripts/mlx-bench.sh --check
#   scripts/mlx-bench.sh --smoke              # Ollama incumbents only
#   scripts/mlx-bench.sh --smoke --mlx        # also Rapid-MLX candidates
#   scripts/mlx-bench.sh --serve qwen3.6-35b-4bit   # foreground server for Zed
#
# MLX model aliases are Rapid-MLX short names (maps to mlx-community on HF).
# Not hearth roles until benched and swapped. See docs/MLX-BENCH.md.
#
# bash 3.2 compatible.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"
ai_python_or_die || exit 2

MLX_PORT="${MLX_BENCH_PORT:-8000}"
MLX_HOST="${MLX_BENCH_HOST:-127.0.0.1}"
MLX_BASE="http://${MLX_HOST}:${MLX_PORT}/v1"
RAPID="${RAPID_MLX_BIN:-}"

find_rapid() {
  if [ -n "$RAPID" ] && [ -x "$RAPID" ]; then
    return 0
  fi
  for p in "$(command -v rapid-mlx 2>/dev/null)" \
           "${HOME}/.local/bin/rapid-mlx" \
           /opt/homebrew/bin/rapid-mlx; do
    [ -n "$p" ] && [ -x "$p" ] && { RAPID="$p"; return 0; }
  done
  return 1
}

# Rapid-MLX aliases → approx disk GB (weights only; KV extra at runtime)
MLX_CANDIDATES="
gpt-oss-20b|13|incumbent agent (MLX) — compare to Ollama gpt-oss:20b
qwen3.6-35b-4bit|20|MoE 35B — safer on 64 GB than 8bit (~38 GB weights)
qwen3.6-35b-8bit|38|MoE 35B 8bit — tight on ~48 GB GPU envelope; cap ctx
gemma-4-12b-4bit|8|vision + tools; light agent candidate
gemma-4-26b-4bit|16|vision + tools; mid-size
"

OLLAMA_SMOKE="gpt-oss:20b qwen3-coder:30b"

usage() {
  cat <<EOF
MLX stage-1 bench (docs/MLX-BENCH.md)

  $0 --check
  $0 --smoke [--mlx]
  $0 --serve <rapid-mlx-alias>
  $0 --install-rapid

Rapid-MLX listens on ${MLX_BASE}
EOF
}

check() {
  echo "MLX bench check"
  echo
  echo "  Ollama: $(curl -s -m 2 -o /dev/null -w '%{http_code}' http://127.0.0.1:11434/api/tags 2>/dev/null || echo down)"
  if find_rapid; then
    echo "  rapid-mlx: ${RAPID}"
    "${RAPID}" --version 2>/dev/null | head -1 || true
  else
    echo "  rapid-mlx: not installed (run $0 --install-rapid)"
  fi
  echo
  echo "  MLX candidates (weights only):"
  echo "$MLX_CANDIDATES" | while IFS='|' read -r alias gb note; do
    [ -z "$alias" ] && continue
    printf '    %-22s %5s GB  %s\n' "$alias" "$gb" "$note"
  done
  echo
  echo "  Envelope: 64 GB unified, ~48 GB GPU-accessible — one hot model (ADR 0011)."
}

install_rapid() {
  if find_rapid; then
    echo "rapid-mlx already at ${RAPID}"
    return 0
  fi
  if command -v rapid-mlx >/dev/null 2>&1; then
    RAPID="$(command -v rapid-mlx)"
    return 0
  fi
  if command -v pipx >/dev/null 2>&1; then
    echo "Installing via pipx..."
    pipx install rapid-mlx
    RAPID="$(command -v rapid-mlx 2>/dev/null || echo "${HOME}/.local/bin/rapid-mlx")"
    [ -x "$RAPID" ] && return 0
  fi
  if command -v brew >/dev/null 2>&1; then
    echo "Installing via Homebrew tap raullenchai/rapid-mlx..."
    brew install raullenchai/rapid-mlx/rapid-mlx
  else
    echo "Need pipx or brew. Try: pipx install rapid-mlx"
    exit 1
  fi
  find_rapid || { echo "install failed"; exit 1; }
  echo "rapid-mlx: ${RAPID}"
}

smoke_ollama() {
  for m in $OLLAMA_SMOKE; do
    echo
    bash "${ROOT}/scripts/tool-smoke.sh" ollama "$m" || true
  done
}

smoke_mlx() {
  find_rapid || { echo "rapid-mlx missing"; exit 1; }
  if ! curl -s -m 2 -o /dev/null "http://${MLX_HOST}:${MLX_PORT}/health" 2>/dev/null \
     && ! curl -s -m 2 -o /dev/null "${MLX_BASE}/models" 2>/dev/null; then
    echo "No Rapid-MLX server on ${MLX_BASE}"
    echo "Start one: $0 --serve qwen3.6-35b-4bit"
    exit 1
  fi
  for alias in gpt-oss-20b qwen3.6-35b-4bit gemma-4-12b-4bit; do
    echo
    bash "${ROOT}/scripts/tool-smoke.sh" openai "$MLX_BASE" "$alias" || true
  done
}

serve() {
  local alias="${1:?rapid-mlx alias, e.g. qwen3.6-35b-4bit}"
  find_rapid || { echo "rapid-mlx missing — $0 --install-rapid"; exit 1; }
  echo "Serving ${alias} at ${MLX_BASE}"
  echo "Zed: add openai_compatible provider mlx → api_url ${MLX_BASE}"
  echo "Ctrl-C to stop."
  exec "${RAPID}" serve "$alias" --host "$MLX_HOST" --port "$MLX_PORT"
}

case "${1:---check}" in
  --check) check ;;
  --install-rapid) install_rapid ;;
  --smoke)
    smoke_ollama
    if [ "${2:-}" = "--mlx" ]; then
      smoke_mlx
    fi
    ;;
  --serve) shift; serve "${1:-}" ;;
  -h|--help) usage ;;
  *) usage; exit 2 ;;
esac
