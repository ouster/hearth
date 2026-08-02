#!/bin/bash
# Pull candidate models for benching. Does NOT change any role — candidates sit
# alongside the incumbents until scripts/bench.sh says they win.
#
#   scripts/pull-candidates.sh          # show the plan and disk cost
#   scripts/pull-candidates.sh --pull   # actually download
#
# Weight budget: ~48GB of 64GB. The rest is macOS, Cursor, and a browser.

set -euo pipefail

BUDGET_GB=48

# model|approx GB|role it is auditioning for|why
CANDIDATES=(
  "qwen3-coder:30b|19|local-code, local-big|30B MoE, ~3B active. 256K ctx. ~7B speed, ~30B reasoning."
  "gpt-oss:20b|13|local-big|Strong reasoning at mid-size. Replaces the 70B's actual job."
  "devstral:24b|14|local-agent (new)|46.8% SWE-Bench Verified — the only local coder with a hard agentic number."
)

# Deliberately excluded, with reasons — so nobody re-suggests them later:
#   gpt-oss:120b   ~65GB. Over budget. "Runs on a 64GB Mac with offload" means
#                  swapping to SSD every token. Do not.
#   deepseek-r1:70b  Same 42GB single-occupancy problem as llama3.3:70b.

echo "Weight budget: ${BUDGET_GB}GB"
echo
printf '%-22s %6s  %s\n' MODEL GB "AUDITIONING FOR"
printf '%-22s %6s  %s\n' "----------------------" "------" "---------------"

total=0
for c in "${CANDIDATES[@]}"; do
  IFS='|' read -r model gb role why <<< "$c"
  printf '%-22s %6s  %s\n' "$model" "$gb" "$role"
  printf '%-22s %6s  %s\n' "" "" "$why"
  total=$((total + gb))
done

echo
echo "Candidates total: ${total}GB"
echo "Currently resident-capable: qwen2.5-coder:7b (4.7) + 32b (19) + llama3.3:70b (42)"
echo
echo "If all three candidates win, retiring llama3.3:70b frees 42GB and lets"
echo "qwen3-coder:30b + gpt-oss:20b + qwen2.5-coder:7b (~37GB) stay resident together."
echo "Today the 70B alone evicts everything else."

if [ "${1:-}" != "--pull" ]; then
  echo
  echo "Nothing downloaded. Re-run with --pull to fetch."
  exit 0
fi

echo
avail=$(df -g /Users/Shared 2>/dev/null | awk 'NR==2{print $4}')
echo "Free disk: ${avail}GB — need ~${total}GB"
if [ -n "$avail" ] && [ "$avail" -lt "$total" ]; then
  echo "Not enough disk. Aborting."; exit 1
fi

for c in "${CANDIDATES[@]}"; do
  IFS='|' read -r model _ _ _ <<< "$c"
  echo
  echo "==> pulling ${model}"
  ollama pull "$model"
done

echo
echo "Done. Next: scripts/bench.sh"
echo "Nothing is promoted until the bench report says so."
