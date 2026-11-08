#!/bin/bash
# Check VS Code's user settings against the host rules (ADR 0036). Checked,
# never written: VS Code settings are JSONC the operator edits.
#
#   scripts/vscode-check.sh          # report
#   scripts/vscode-check.sh --show   # print the settings to paste, change nothing
#
# Fails on anything that sends code off the host: Copilot inline completions
# or next edit suggestions on, Copilot code search on, telemetry not off, or
# a language-model endpoint other than 127.0.0.1 / localhost.
# Warns when the agent request cap or the role is missing.
#
# Exit 0 clean, 1 a setting breaks the host rules, 2 could not run.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"

USERDIR="${VSCODE_USER:-$HOME/Library/Application Support/Code/User}"
SETTINGS="${USERDIR}/settings.json"
MODELS="${USERDIR}/chatLanguageModels.json"

if [ "${1:-}" = "--show" ]; then
  cat <<'EOF'
// VS Code user settings (Cmd-Shift-P → Preferences: Open User Settings (JSON)).
// Host rules, ADR 0036. Merge into the existing object.
  "github.copilot.enable": { "*": false },
  "github.copilot.nextEditSuggestions.enabled": false,
  "github.copilot.chat.codesearch.enabled": false,
  "telemetry.telemetryLevel": "off",
  "chat.agent.enabled": true,
  "chat.agent.maxRequests": 40,
  "chat.tools.global.autoApprove": false,
  "chat.mcp.discovery.enabled": {
      "claude-desktop": false, "windsurf": false,
      "cursor-global": false, "cursor-workspace": false
  },
  "chat.useHooks": true,
  "chat.useAgentsMdFile": true,
EOF
  exit 0
fi

[ -f "$SETTINGS" ] || { echo "could not run: no VS Code settings at ${SETTINGS}"; exit 2; }

# Program on stdin (heredoc), data in argv — never both on stdin.
/usr/bin/python3 -I - "$SETTINGS" "$MODELS" <<'PY'
import json, os, re, sys

settings_path, models_path = sys.argv[1], sys.argv[2]

def jsonc(text):
    # Strip // and /* */ comments outside strings, then trailing commas.
    out, i, n, s = [], 0, len(text), False
    while i < n:
        c = text[i]
        if s:
            out.append(c)
            if c == "\\" and i + 1 < n:
                out.append(text[i + 1]); i += 2; continue
            if c == '"':
                s = False
        elif c == '"':
            s = True; out.append(c)
        elif text.startswith("//", i):
            while i < n and text[i] != "\n":
                i += 1
            continue
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            i = n if j < 0 else j + 2
            continue
        else:
            out.append(c)
        i += 1
    return json.loads(re.sub(r",(\s*[}\]])", r"\1", "".join(out)))

rc = 0
def bad(msg):
    global rc
    print("FAIL   " + msg); rc = 1
def ok(msg):
    print("ok     " + msg)
def warn(msg):
    print("warn   " + msg)

try:
    s = jsonc(open(settings_path).read())
except ValueError as e:
    print("could not run: settings.json did not parse (%s)" % e); sys.exit(2)

enable = s.get("github.copilot.enable")
if isinstance(enable, dict) and enable.get("*") is False and not any(v is True for v in enable.values()):
    ok("Copilot inline completions off")
else:
    bad('Copilot inline completions not off — set "github.copilot.enable": {"*": false} (they go to GitHub, rule 3)')

if s.get("github.copilot.nextEditSuggestions.enabled") is False:
    ok("next edit suggestions off")
else:
    bad('next edit suggestions not off — set "github.copilot.nextEditSuggestions.enabled": false (GitHub service)')

if s.get("github.copilot.chat.codesearch.enabled") is True:
    bad("Copilot code search on — it uses GitHub embeddings; set it false")
else:
    ok("Copilot code search off")

if s.get("telemetry.telemetryLevel") == "off":
    ok("VS Code telemetry off")
else:
    bad('telemetry not off — set "telemetry.telemetryLevel": "off"')

if s.get("chat.tools.global.autoApprove") is True:
    bad("chat.tools.global.autoApprove is on — every tool call runs unasked")
else:
    ok("tool calls ask first")

mr = s.get("chat.agent.maxRequests")
if isinstance(mr, int) and mr <= 40:
    ok("chat.agent.maxRequests %d" % mr)
else:
    warn("chat.agent.maxRequests %s — set 40 (ADR 0036)" % ("unset" if mr is None else mr))

if s.get("chat.agent.enabled") is False:
    warn("chat.agent.enabled false — agent mode is off, so no tools run")

disc = s.get("chat.mcp.discovery.enabled")
if disc is True or (isinstance(disc, dict) and any(v is True for v in disc.values())):
    warn("MCP discovery on — servers from other apps load into chat; turn each source off")

if s.get("chat.useHooks") is False:
    warn("chat.useHooks false — the loop guard will not run in the Local harness")

# Language model endpoints. Every URL must be loopback.
if not os.path.exists(models_path):
    warn("no chatLanguageModels.json — add the hearth Custom Endpoint (docs/IDES.md)")
else:
    try:
        m = jsonc(open(models_path).read())
    except ValueError as e:
        print("could not run: chatLanguageModels.json did not parse (%s)" % e); sys.exit(2)
    urls, ids = [], []
    def walk(x):
        if isinstance(x, dict):
            for k, v in x.items():
                if k == "url" and isinstance(v, str):
                    urls.append(v)
                elif k == "id" and isinstance(v, str):
                    ids.append(v)
                walk(v)
        elif isinstance(x, list):
            for v in x:
                walk(v)
    walk(m)
    for u in urls:
        if re.match(r"^http://(127\.0\.0\.1|localhost)(:\d+)?(/|$)", u):
            ok("endpoint %s" % u)
        else:
            bad("endpoint %s is not loopback — no remote model in host VS Code (rule 3)" % u)
    raw = open(models_path).read()
    if re.search(r'"apiKey"\s*:\s*"(?!\$\{)[^"]+"', raw):
        mode = os.stat(models_path).st_mode & 0o777
        if mode & 0o077:
            bad("chatLanguageModels.json holds a key and is mode %o — chmod 600 it" % mode)
        else:
            ok("key file mode 600")
    if "local-main" in ids:
        ok("model id local-main (the role)")
    else:
        warn("no model with id local-main — call the role, never a model name (rule 1)")

sys.exit(rc)
PY
