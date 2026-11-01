#!/bin/bash
# Write each LM Studio role's label and context into Zed's settings, from
# config/roles.tsv + `lms ls`. Clients still call the role (`local-main`);
# only the label shown in Zed's model picker names the model, and it is
# regenerated whenever roles change, so it cannot go stale.
#
#   scripts/zed-sync.sh            # update ~/.config/zed/settings.json
#   scripts/zed-sync.sh --check    # report drift, change nothing
#
# Edits only `display_name` and `max_tokens` on entries whose `name` is a
# role, inside language_models.openai_compatible.hearth, leaving comments
# and everything else byte-for-byte. Backup: settings.json.zed-sync.bak
# Called by scripts/lms-load.sh after a successful load.
#
# Exit 0 in sync / updated, 1 drift (--check) or a role missing in Zed,
# 2 could not run.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"

ZED="${ZED_SETTINGS:-$HOME/.config/zed/settings.json}"
CHECK=0; [ "${1:-}" = "--check" ] && CHECK=1
[ -f "$ZED" ] || { echo "could not run: no Zed settings at ${ZED}"; exit 2; }
[ -x "$HEARTH_LMS" ] || { echo "could not run: lms not found"; exit 2; }

ls_json=$("$HEARTH_LMS" ls --json 2>/dev/null) || { echo "could not run: lms ls failed"; exit 2; }

# Program on stdin (heredoc), data in argv — never both on stdin.
# A demand role's label says to load it first: picking it in Zed while it is
# unloaded is answered by local-main without saying so (JIT off).
/usr/bin/python3 -I - "$ZED" "$CHECK" "$ls_json" "$(hearth_roles lmstudio)" "$(hearth_demand_roles)" <<'PY'
import json, re, shutil, sys
zed, check, ls_json, roles_tsv = sys.argv[1], sys.argv[2] == "1", sys.argv[3], sys.argv[4]
demand = set(sys.argv[5].split())
models = {}
for m in json.loads(ls_json):
    models[m.get("modelKey", "")] = m
    for v in m.get("variants") or []:
        models.setdefault(v, m)

rows = [l.split("\t") for l in roles_tsv.splitlines() if l.strip()]
text = open(zed).read()
new, rc = text, 0
for role, _backend, key, ctx, _slots, *_ in rows:
    m = models.get(key)
    if m is None:
        print(f"skip   {role}: {key} not in lms ls"); rc = max(rc, 1); continue
    if "embed" in key:
        continue  # Zed's model picker lists chat models only
    quant = (m.get("quantization") or {}).get("name", "")
    label = f'{role} · {m.get("displayName", key)}' + (f" {quant}" if quant else "")
    if role in demand:
        label += " — load first: scripts/demand-load.sh " + role + " up --evict"
    # The entry: "name": "<role>", then its fields up to the closing brace.
    pat = re.compile(r'("name"\s*:\s*"' + re.escape(role) + r'"\s*,)(.*?)(\n\s*\})', re.S)
    hit = pat.search(new)
    if not hit:
        print(f"MISSING {role}: no hearth entry with \"name\": \"{role}\" in Zed settings"); rc = max(rc, 1); continue
    body = hit.group(2)
    body2 = re.sub(r'("display_name"\s*:\s*)"[^"]*"', lambda x: x.group(1) + json.dumps(label, ensure_ascii=False), body, count=1)
    body2 = re.sub(r'("max_tokens"\s*:\s*)\d+', lambda x: x.group(1) + ctx, body2, count=1)
    if body2 == body:
        print(f"ok     {role}: \"{label}\", max_tokens {ctx}")
        continue
    print(f"{'DRIFT ' if check else 'update'} {role}: \"{label}\", max_tokens {ctx}")
    if check:
        rc = max(rc, 1)
    new = new[:hit.start(2)] + body2 + new[hit.end(2):]

if not check and new != text:
    shutil.copy2(zed, zed + ".zed-sync.bak")
    open(zed, "w").write(new)
sys.exit(rc)
PY
