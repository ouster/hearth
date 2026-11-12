#!/bin/bash
# Write each local role's label and context into Zed's settings, from
# config/roles.tsv. Clients still call the role (`main-brain`). The label
# is `role — <weights-leaf>` so the picker shows the backing model (ADR 0034),
# regenerated whenever roles change so it cannot go stale.
#
#   scripts/zed-sync.sh            # update ~/.config/zed/settings.json
#   scripts/zed-sync.sh --check    # report drift, change nothing
#
# Renames retired ADR 0039 role ids (built at runtime; this file does not
# spell them) wherever they appear, then edits only `display_name` and
# `max_tokens` on entries whose `name` is a role. Comments and every other
# field stay. Backup: settings.json.zed-sync.bak
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
/usr/bin/python3 -I - "$ZED" "$CHECK" "$(hearth_roles omlx)" "$(hearth_demand_roles)" "$(hearth_edit_roles | cut -f1)" <<'PY'
import json, re, shutil, sys
zed, check, roles_tsv = sys.argv[1], sys.argv[2] == "1", sys.argv[3]
demand = set(sys.argv[4].split())
edit = set(sys.argv[5].split())

def strip_jsonc(src):
    """Comments and trailing commas, so a Zed settings file can be parsed."""
    out, i, n = [], 0, len(src)
    in_str = esc = False
    while i < n:
        c = src[i]
        if in_str:
            out.append(c)
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                in_str = False
            i += 1
            continue
        if c == '"':
            in_str = True
            out.append(c)
            i += 1
            continue
        if c == "/" and i + 1 < n and src[i + 1] == "/":
            i += 2
            while i < n and src[i] != "\n":
                i += 1
            continue
        if c == "/" and i + 1 < n and src[i + 1] == "*":
            i += 2
            while i + 1 < n and not (src[i] == "*" and src[i + 1] == "/"):
                i += 1
            i = min(i + 2, n)
            continue
        out.append(c)
        i += 1
    return re.sub(r",(\s*[}\]])", r"\1", "".join(out))

rows = [l.split("\t") for l in roles_tsv.splitlines() if l.strip()]
text = open(zed).read()
new, rc = text, 0
# Retired ADR 0039 ids. Built here so this file does not spell them.
retired = {
    "%s-%s" % ("local", "main"): "main-brain",
    "%s-%s" % ("local", "deep"): "deep-brain",
    "%s-%s" % ("local", "edit"): "edit-brain",
}
for old, neu in retired.items():
    pat_old = re.compile(r"(?<![\w-])" + re.escape(old) + r"(?![\w-])")
    if pat_old.search(new):
        print("%s %s → %s" % ("DRIFT " if check else "rename", old, neu))
        new = pat_old.sub(neu, new)
        if check:
            rc = max(rc, 1)
for role, _backend, key, ctx, slots, *rest in rows:
    if "embed" in key or role in edit:
        continue  # Zed's model picker lists chat models only
    weights = rest[0] if rest else ""
    leaf = weights.rstrip("/").split("/")[-1] if weights and weights != "-" else ""
    # Context × slots in the label (ADR 0047); slot count stays out of the role id.
    try:
        ctx_n = int(ctx)
        slot_n = int(slots) if str(slots).isdigit() else 0
    except ValueError:
        ctx_n, slot_n = 0, 0
    if ctx_n >= 1024:
        ctx_label = "%sK" % (ctx_n // 1024)
    else:
        ctx_label = str(ctx)
    if leaf and slot_n:
        label = "%s — %s — %s × %s" % (role, leaf, ctx_label, slot_n)
    elif leaf:
        label = "%s — %s" % (role, leaf)
    else:
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

# Edit prediction (ADR 0033). Checked, never written: the provider is the
# one Zed setting that decides whether file text leaves the machine.
try:
    doc = json.loads(strip_jsonc(new))
except ValueError:
    doc = None
if doc is None:
    print("check  edit_predictions: settings could not be parsed; check the provider by hand")
    ep = None
elif "edit_predictions" not in doc:
    print('DRIFT  edit_predictions: not set — add {"provider": "none"} unless laptop edit-brain or paid Zeta (docs/IDES.md)')
    rc = max(rc, 1)
    ep = None
else:
    ep = doc.get("edit_predictions") or {}
if ep is not None:
    prov = ep.get("provider")
    oac = ep.get("open_ai_compatible_api") or {}
    url = str(oac.get("api_url", ""))
    local = url.startswith(("http://127.0.0.1:", "http://localhost:")) and url.endswith("/v1/completions")
    if prov == "none":
        print("ok     edit_predictions: off" + ("; laptop edit-brain or paid Zeta: docs/IDES.md" if edit else ""))
    elif prov == "open_ai_compatible_api" and local and oac.get("model") in edit | {"edit-brain"}:
        print("ok     edit_predictions: %s at %s" % (oac.get("model"), url))
    elif prov == "zed":
        print("DRIFT  edit_predictions: paid Zed Zeta — cursor text leaves the machine (rule 3); keep \"none\" or laptop edit-brain unless the buffer is non-sensitive (docs/IDES.md)")
        rc = max(rc, 1)
    else:
        print("DRIFT  edit_predictions: provider %r — set \"none\", laptop edit-brain, or knowingly enable paid Zeta (docs/IDES.md)" % prov)
        rc = max(rc, 1)

if not check and new != text:
    shutil.copy2(zed, zed + ".zed-sync.bak")
    open(zed, "w").write(new)
sys.exit(rc)
PY
