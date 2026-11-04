#!/bin/bash
# Write each local role's label and context into Zed's settings, from
# config/roles.tsv. Clients still call the role (`local-main`). The label
# is the role, regenerated whenever roles change, so it cannot go stale.
#
#   scripts/zed-sync.sh            # update ~/.config/zed/settings.json
#   scripts/zed-sync.sh --check    # report drift, change nothing
#
# Edits only `display_name` and `max_tokens` on entries whose `name` is a
# role, inside language_models.openai_compatible.hearth, leaving comments
# and everything else byte-for-byte. Backup: settings.json.zed-sync.bak
#
# Exit 0 in sync / updated, 1 drift (--check) or a role missing in Zed,
# 2 could not run.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"

ZED="${ZED_SETTINGS:-$HOME/.config/zed/settings.json}"
CHECK=0; [ "${1:-}" = "--check" ] && CHECK=1
[ -f "$ZED" ] || { echo "could not run: no Zed settings at ${ZED}"; exit 2; }

# Program on stdin (heredoc), data in argv — never both on stdin.
# A demand role's label says to load it first.
/usr/bin/python3 -I - "$ZED" "$CHECK" "$(hearth_roles omlx)" "$(hearth_demand_roles)" <<'PY'
import json, re, shutil, sys
zed, check, roles_tsv = sys.argv[1], sys.argv[2] == "1", sys.argv[3]
demand = set(sys.argv[4].split())

rows = [l.split("\t") for l in roles_tsv.splitlines() if l.strip()]
text = open(zed).read()
new, rc = text, 0
for role, _backend, key, ctx, _slots, *_ in rows:
    if "embed" in key:
        continue  # Zed's model picker lists chat models only
    label = role
    if role in demand:
        label += " — load first: scripts/demand-load.sh " + role + " up"
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
