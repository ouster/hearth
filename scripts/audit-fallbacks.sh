#!/bin/bash
# Fails if any local-* role can fall back to a cloud model.
#
# This is the exact bug the inherited config had: local-ollama -> gemini, so
# every Ollama timeout silently shipped the prompt to Google. Run before any
# config change goes live.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"
CFG="${1:-${ROOT}/litellm/config.yaml}"

# Exit 2 = could not run (tooling). Exit 1 = real leak. Never confuse the two.
ai_python_or_die || exit 2

"$AI_PY" - "$CFG" <<'PY'
import sys, yaml
cfg = yaml.safe_load(open(sys.argv[1]))

leaks = []
for fb in (cfg.get('router_settings') or {}).get('fallbacks') or []:
    for src, dsts in fb.items():
        if src.startswith('local-'):
            leaks += [(src, d) for d in dsts if not d.startswith('local-')]

names = [m['model_name'] for m in cfg.get('model_list', [])]
print(f"roles: {', '.join(names)}")

if leaks:
    print("\nFAIL — local roles can reach cloud:")
    for s, d in leaks:
        print(f"  {s} -> {d}")
    sys.exit(1)

print("\nPASS — no local role falls back to a cloud model")
PY
