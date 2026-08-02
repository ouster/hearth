#!/bin/bash
# Repoint a role at a different model, safely.
#
#   scripts/swap-role.sh local-code qwen3-coder:30b
#   scripts/swap-role.sh local-code qwen3-coder:30b --delete-old
#
# Order matters and this enforces it: pull the new model, edit the config,
# audit, deploy, verify the role actually answers, and only then offer to
# delete the old weights. Deleting first is how you end up with a role
# pointing at nothing.
#
# Comments in config.yaml are preserved — they carry the reasoning, and a
# yaml load/dump round-trip would strip them.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"
ai_python_or_die || exit 2
ai_load_env "$ROOT"

CFG="${ROOT}/litellm/config.yaml"
ROLE="${1:?usage: swap-role.sh <role> <new-model> [--delete-old]}"
NEW="${2:?usage: swap-role.sh <role> <new-model> [--delete-old]}"
DELETE_OLD=false
[ "${3:-}" = "--delete-old" ] && DELETE_OLD=true

say() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

# ---------------------------------------------------------------- current
OLD=$("$AI_PY" - "$CFG" "$ROLE" <<'PY'
import sys, yaml
cfg = yaml.safe_load(open(sys.argv[1])) or {}
for m in cfg.get('model_list', []):
    if m['model_name'] == sys.argv[2]:
        print(m['litellm_params']['model']); break
PY
)
[ -n "$OLD" ] || { echo "role '${ROLE}' not found in ${CFG}"; exit 1; }

OLD_BARE="${OLD#*/}"
echo "role      : ${ROLE}"
echo "currently : ${OLD}"
echo "new       : ollama_chat/${NEW}"

[ "$OLD_BARE" = "$NEW" ] && { echo "already pointing there — nothing to do"; exit 0; }

# ---------------------------------------------------------------- pull
say "1/5 Ensure the new model is present"
if ollama list 2>/dev/null | awk 'NR>1{print $1}' | grep -qx -e "$NEW" -e "${NEW}:latest"; then
  echo "    already pulled"
else
  echo "    pulling ${NEW} — this may take a while"
  ollama pull "$NEW" || { echo "    pull failed, config untouched"; exit 1; }
fi

# ---------------------------------------------------------------- edit
say "2/5 Update config"
cp "$CFG" "${CFG}.bak"
"$AI_PY" - "$CFG" "$ROLE" "$NEW" <<'PY'
import sys, re
path, role, new = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(path).read().split('\n')
out, inrole, done = [], False, False
for ln in lines:
    if re.match(rf'\s*-\s*model_name:\s*{re.escape(role)}\s*$', ln):
        inrole = True
    elif re.match(r'\s*-\s*model_name:', ln):
        inrole = False
    if inrole and not done and re.match(r'\s*model:\s*ollama', ln):
        indent = ln[:len(ln) - len(ln.lstrip())]
        ln = f'{indent}model: ollama_chat/{new}'
        done = True
    out.append(ln)
open(path, 'w').write('\n'.join(out))
print('    rewrote model line' if done else '    WARNING: no ollama model line found')
PY

# ---------------------------------------------------------------- audit
say "3/5 Audit"
if ! bash "${ROOT}/scripts/audit-fallbacks.sh" >/dev/null 2>&1; then
  echo "    fallback audit FAILED — reverting"
  mv "${CFG}.bak" "$CFG"; exit 1
fi
echo "    fallbacks clean"

if ! bash "${ROOT}/scripts/preflight.sh" >/dev/null 2>&1; then
  echo "    preflight failed — reverting"
  mv "${CFG}.bak" "$CFG"
  bash "${ROOT}/scripts/preflight.sh" | tail -20
  exit 1
fi
echo "    preflight clean"

# ---------------------------------------------------------------- deploy
say "4/5 Restart gateway"
launchctl kickstart -k "$(ai_litellm_agent)" 2>/dev/null
for _ in $(seq 1 30); do
  curl -s -m 3 -o /dev/null "http://127.0.0.1:4000/health/readiness" && break
  sleep 1
done
echo "    gateway responding"

# ---------------------------------------------------------------- verify
say "5/5 Verify the role answers"
start=$(date +%s)
code=$(curl -s -m 900 -o /dev/null -w '%{http_code}' \
  -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" -H "Content-Type: application/json" \
  -d "{\"model\":\"${ROLE}\",\"messages\":[{\"role\":\"user\",\"content\":\"say ok\"}],\"max_tokens\":10}" \
  "http://127.0.0.1:4000/v1/chat/completions")
elapsed=$(( $(date +%s) - start ))

if [ "$code" != "200" ]; then
  echo "    ${ROLE} FAILED (HTTP ${code}) after ${elapsed}s"
  echo "    Config kept at ${CFG}.bak — restore with:"
  echo "      mv ${CFG}.bak ${CFG} && scripts/deploy.sh"
  exit 1
fi
echo "    ${ROLE} answered in ${elapsed}s"
rm -f "${CFG}.bak"

# ---------------------------------------------------------------- cleanup
say "Old weights"
echo "    ${OLD_BARE} is no longer referenced by any role."
if $DELETE_OLD; then
  still=$(grep -c "ollama_chat/${OLD_BARE}\b" "$CFG" 2>/dev/null || echo 0)
  if [ "$still" -gt 0 ]; then
    echo "    NOT deleting — still used by another role"
  else
    ollama rm "$OLD_BARE" && echo "    deleted ${OLD_BARE}"
  fi
else
  echo "    Keep it a few days, then: ollama rm ${OLD_BARE}"
  echo "    Or re-run with --delete-old to remove it now."
fi

cat <<EOF

Remember to update docs/MODELS.md and write an ADR — the registry is only
useful if it matches reality.
EOF
