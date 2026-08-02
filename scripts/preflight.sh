#!/bin/bash
# Read-only. Changes nothing. Run before deploy and after any config edit.
#
#   scripts/preflight.sh
#
# Every check that can be made without touching the running gateway is made
# here, so a deploy fails on your terminal rather than halfway through a
# launchd restart.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"
CFG="${ROOT}/litellm/config.yaml"
ENVF="${ROOT}/litellm/.env"
LIVE_CFG="$HOME/.config/litellm/config.yaml"
LIVE_ENV="$HOME/.config/litellm/env"

pass=0; warn=0; fail=0; err=0
ok()   { printf '  \033[32mOK\033[0m    %s\n' "$1"; pass=$((pass+1)); }
wrn()  { printf '  \033[33mWARN\033[0m  %s\n' "$1"; warn=$((warn+1)); }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; fail=$((fail+1)); }
# ERROR = the check could not run. Distinct from FAIL, which means it ran and
# found a problem. Conflating them turns a missing module into a fake leak.
er()   { printf '  \033[35mERROR\033[0m %s\n' "$1"; err=$((err+1)); }
hdr()  { printf '\n\033[1m%s\033[0m\n' "$1"; }

# ---------------------------------------------------------------- integrity
# A script referenced by the docs but absent from disk is a silent trap — you
# find out mid-deploy. db.sh went missing exactly this way once.
hdr "Repo integrity"

missing_files=""
for r in $(grep -rhoE 'scripts/[a-z-]+\.(sh|zsh)' "$ROOT/docs" "$ROOT/scripts" "$ROOT/CLAUDE.md" 2>/dev/null | sort -u); do
  [ -f "${ROOT}/${r}" ] || missing_files="${missing_files} ${r}"
done
for p in litellm/config.yaml litellm/.env.example bench/tasks docs/decisions; do
  [ -e "${ROOT}/${p}" ] || missing_files="${missing_files} ${p}"
done
# Existing-but-not-executable is its own trap: the file is there, the docs are
# right, and it fails only when you actually try to run it. sandboxed.sh
# shipped this way once.
not_exec=""
for r in "$ROOT"/scripts/*.sh; do
  [ -f "$r" ] || continue
  [ -x "$r" ] || not_exec="${not_exec} scripts/$(basename "$r")"
done
if [ -n "$not_exec" ]; then
  bad "present but not executable (chmod +x):${not_exec}"
else
  ok "every script in scripts/ is executable"
fi

if [ -z "$missing_files" ]; then
  ok "all referenced scripts and paths exist"
else
  bad "referenced but missing:${missing_files}"
fi

# ---------------------------------------------------------------- tooling
hdr "Tooling"

if [ -n "${AI_PY:-}" ]; then
  ok "python with PyYAML: ${AI_PY}"
  HAVE_YAML=true
else
  er "no python3 with PyYAML — config checks cannot run"
  echo "        fix: \"\$HOME/.local/pipx/venvs/litellm/bin/pip\" install pyyaml"
  echo "        or:  pip3 install --user --break-system-packages pyyaml"
  HAVE_YAML=false
fi

# ---------------------------------------------------------------- config
hdr "Config"

if ! $HAVE_YAML; then
  er "config.yaml parse — skipped, no yaml module"
  er "fallback leak audit — skipped, no yaml module"
else
  if "$AI_PY" -c "import yaml,sys; yaml.safe_load(open('$CFG'))" 2>/dev/null; then
    ok "config.yaml parses"
  else
    bad "config.yaml does not parse"
  fi

  bash "${ROOT}/scripts/audit-fallbacks.sh" >/dev/null 2>&1
  case $? in
    0) ok "no local role falls back to cloud" ;;
    1) bad "FALLBACK LEAK — a local role can reach a cloud model. Fix before deploying." ;;
    *) er "fallback audit could not run" ;;
  esac

  # model_info is a validated pydantic model, and an invalid field makes LiteLLM
  # DROP that deployment while logging only "ignoring and continuing" — the
  # gateway starts clean and serves nothing. `tier` cost us an hour: it is a real
  # field accepting only 'free' or 'paid', and we used it for our own bookkeeping.
  mi=$("$AI_PY" - "$CFG" <<'PY'
import sys, yaml
SAFE = {
    'mode', 'id', 'base_model', 'tier',
    'max_tokens', 'max_input_tokens', 'max_output_tokens',
    'input_cost_per_token', 'output_cost_per_token',
    'supports_vision', 'supports_function_calling', 'supports_prompt_caching',
}
problems = []
cfg = yaml.safe_load(open(sys.argv[1])) or {}
for m in cfg.get('model_list', []):
    info = m.get('model_info') or {}
    name = m.get('model_name')
    for k, v in info.items():
        if k == 'tier' and v not in ('free', 'paid'):
            problems.append(f"{name}: tier={v!r} (only 'free' or 'paid' allowed)")
        elif k not in SAFE:
            problems.append(f"{name}: unknown model_info key {k!r}")
print('\n'.join(problems))
PY
)
  # Docs drift. A registry that disagrees with the config is worse than none —
  # you trust it and it lies. Every live role must appear in MODELS.md and
  # ROUTING.md, and no retired role may still be described as current.
  drift=$("$AI_PY" - "$CFG" "$ROOT" <<'PY'
import sys, yaml, re, os
cfg = yaml.safe_load(open(sys.argv[1])) or {}
root = sys.argv[2]
live = [m['model_name'] for m in cfg.get('model_list', [])]
models = {m['model_name']: m['litellm_params']['model'].split('/', 1)[-1] for m in cfg.get('model_list', [])}
problems = []

for doc in ('docs/MODELS.md', 'docs/ROUTING.md'):
    p = os.path.join(root, doc)
    if not os.path.exists(p):
        problems.append(f"{doc} missing"); continue
    t = open(p).read()
    for r in live:
        if f'`{r}`' not in t:
            problems.append(f"{doc}: live role {r} not documented")

# MODELS.md must name the actual model behind each live role.
p = os.path.join(root, 'docs/MODELS.md')
if os.path.exists(p):
    t = open(p).read()
    for role, model in models.items():
        if f'`{model}`' not in t:
            problems.append(f"docs/MODELS.md: {role} -> {model} not listed")

print('\n'.join(problems))
PY
)
  if [ -z "$drift" ]; then
    ok "docs match config (roles and models)"
  else
    wrn "documentation drift:"
    printf '%s\n' "$drift" | sed 's/^/        /'
  fi

  if [ -z "$mi" ]; then
    ok "model_info fields valid"
  else
    bad "invalid model_info — LiteLLM will DROP these deployments silently:"
    printf '%s\n' "$mi" | sed 's/^/        /'
    echo "        Put bookkeeping in YAML comments, not model_info."
  fi
fi

# Every os.environ/ referenced by the config must resolve, or LiteLLM fails the
# whole config load — not just the offending model.
[ -f "$ENVF" ] && { set -a; . "$ENVF"; set +a; }
[ -f "$LIVE_ENV" ] && { set -a; . "$LIVE_ENV"; set +a; }

# Walk the PARSED yaml, not the raw text — commented-out roles must not count.
#
# Critically, check the SERVICE's environment, not this shell's. LiteLLM runs
# under launchd via run-litellm.sh, which sources ~/.config/litellm/env and
# nothing else. A var exported in ~/.zshrc would look fine here and then fail
# at runtime — a false green is worse than no check.
if ! $HAVE_YAML; then
  er "env var check — skipped, no yaml module"
else
  need=$("$AI_PY" - "$CFG" <<'PY'
import sys, yaml

def refs(node):
    if isinstance(node, dict):
        for v in node.values():
            yield from refs(v)
    elif isinstance(node, list):
        for v in node:
            yield from refs(v)
    elif isinstance(node, str) and node.startswith('os.environ/'):
        yield node.split('/', 1)[1]

cfg = yaml.safe_load(open(sys.argv[1])) or {}
print('\n'.join(sorted(set(refs(cfg)))))
PY
)
  if [ ! -f "$LIVE_ENV" ]; then
    bad "no ${LIVE_ENV} — the service has no environment file"
  else
    svc_missing=""; shell_only=""
    for v in $need; do
      if grep -qE "^[[:space:]]*(export[[:space:]]+)?${v}=" "$LIVE_ENV"; then
        continue
      elif [ -n "$(eval "printf '%s' \"\${${v}:-}\"")" ]; then
        shell_only="${shell_only} ${v}"
      else
        svc_missing="${svc_missing} ${v}"
      fi
    done

    if [ -z "$svc_missing" ] && [ -z "$shell_only" ]; then
      ok "all config vars present in ${LIVE_ENV}"
    fi
    [ -n "$shell_only" ] && {
      bad "set in your shell but NOT in ${LIVE_ENV}:${shell_only}"
      echo "        launchd does not read ~/.zshrc. This will fail at runtime."
    }
    [ -n "$svc_missing" ] && {
      bad "unset everywhere:${svc_missing}"
      echo "        LiteLLM fails the ENTIRE config on a missing var."
      echo "        Add to ${LIVE_ENV} or comment the role out."
    }
  fi
fi

# ---------------------------------------------------------------- database mode
# Adding database_url to the config introduces a dependency the non-DB install
# never had. Missing prisma kills startup, so check it BEFORE deploying rather
# than discovering it during the launchd restart.
hdr "Database mode"

if ! $HAVE_YAML; then
  er "database mode check — skipped, no yaml module"
else
  db_on=$("$AI_PY" - "$CFG" <<'PY'
import sys, yaml
cfg = yaml.safe_load(open(sys.argv[1])) or {}
g = cfg.get('general_settings') or {}
print('yes' if (g.get('database_url') or g.get('store_model_in_db')) else 'no')
PY
)
  if [ "$db_on" = "no" ]; then
    ok "database mode off — prisma not required"
  else
    LPY="${LITELLM_VENV:-$HOME/.local/pipx/venvs/litellm}/bin/python"
    if [ ! -x "$LPY" ]; then
      wrn "cannot find litellm venv python at ${LPY} — skipping prisma check"
    elif "$LPY" -c 'from prisma import Prisma' 2>/dev/null; then
      ok "prisma installed and client generated"
    elif "$LPY" -c 'import prisma' 2>/dev/null; then
      bad "prisma installed but client NOT generated — startup will fail"
      echo "        fix: scripts/setup-prisma.sh"
    else
      bad "config uses database_url but prisma is NOT installed — startup will fail"
      echo "        fix: scripts/setup-prisma.sh"
    fi

    # Prisma being importable says nothing about whether the SCHEMA was applied.
    # LiteLLM often skips its startup migration on a pip install, giving a
    # healthy gateway that 500s the moment anything touches a virtual key.
    if podman container exists ai-stack-postgres 2>/dev/null; then
      tbl=$(podman exec ai-stack-postgres psql -U litellm -d litellm -tAc \
        "select to_regclass('public.\"LiteLLM_VerificationToken\"')" 2>/dev/null | tr -d '[:space:]')
      if [ -n "$tbl" ]; then
        ok "database schema applied (LiteLLM_VerificationToken present)"
      else
        bad "database is empty — LiteLLM tables not created"
        echo "        Gateway will start fine and then 500 on any key operation."
        echo "        fix: scripts/db.sh migrate"
      fi
    fi
  fi
fi

# ---------------------------------------------------------------- ollama
hdr "Ollama"

if curl -s -m 5 -o /dev/null "http://127.0.0.1:11434/api/tags"; then
  ok "ollama responding on 127.0.0.1:11434"
  have=$(ollama list 2>/dev/null | awk 'NR>1{print $1}')
  if ! $HAVE_YAML; then
    er "model presence check — skipped, no yaml module"
    want=""
  else
  want=$("$AI_PY" - "$CFG" <<'PY'
import sys, yaml
cfg = yaml.safe_load(open(sys.argv[1]))
for m in cfg.get('model_list', []):
    mp = m['litellm_params']['model']
    if mp.startswith(('ollama/', 'ollama_chat/')):
        print(mp.split('/', 1)[1])
PY
)
  fi
  # Digest drift. Tags are mutable pointers, so a routine `ollama pull` can
  # change the weights behind a benched role with no warning.
  if [ -f "${ROOT}/pins/digests.tsv" ]; then
    bash "${ROOT}/scripts/pin-digests.sh" --check >/dev/null 2>&1
    case $? in
      0) ok "all roles match their recorded digest" ;;
      1) bad "DIGEST DRIFT — weights changed under a benched role"
         echo "        scripts/pin-digests.sh --check    (see which)" ;;
      *) wrn "some roles unpinned — scripts/pin-digests.sh to record" ;;
    esac
  else
    wrn "no digest pins recorded — scripts/pin-digests.sh"
    echo "        Without pins an ollama pull can silently swap a role's weights."
  fi

  # Ollama reports an implicit :latest tag, so a config entry without a tag
  # must match the :latest variant. Compare both forms.
  for w in $want; do
    case "$w" in *:*) alt="$w" ;; *) alt="${w}:latest" ;; esac
    if grep -qx -e "$w" -e "$alt" <<< "$have"; then
      ok "model present: ${w}"
    else
      bad "model in config but NOT pulled: ${w}  (ollama pull ${w})"
    fi
  done
else
  bad "ollama not responding — gateway will have no local roles"
fi

# ---------------------------------------------------------------- secrets
hdr "Secrets"

if [ -f "$ENVF" ]; then
  ok "litellm/.env exists"
  ph="$(ai_placeholders "$ENVF")"
  if [ -n "$ph" ]; then
    wrn "placeholders still in litellm/.env:${ph}"
    echo "        Harmless — scripts drop them — but delete the lines so a real"
    echo "        value is never mistaken for a stub."
  else
    ok "no placeholder values in litellm/.env"
  fi

  # Variables the GATEWAY needs must live in the service env. Sitting in the
  # repo .env they look set to you and are invisible to launchd.
  wrongplace=""
  for v in LITELLM_MASTER_KEY GOOGLE_API_KEY ANTHROPIC_API_KEY \
           OPENROUTER_API_KEY MOONSHOT_API_KEY FIREWORKS_API_KEY DATABASE_URL; do
    if grep -qE "^[[:space:]]*(export[[:space:]]+)?${v}=" "$ENVF" 2>/dev/null; then
      grep -qE "^[[:space:]]*(export[[:space:]]+)?${v}=" "$LIVE_ENV" 2>/dev/null \
        || wrongplace="${wrongplace} ${v}"
    fi
  done
  if [ -n "$wrongplace" ]; then
    bad "gateway vars in litellm/.env but NOT in ${LIVE_ENV}:${wrongplace}"
    echo "        launchd never reads the repo .env. Move these to the service env."
    echo "        Template: litellm/service-env.example"
  else
    ok "no gateway-only vars stranded in litellm/.env"
  fi
  [ -n "${LITELLM_MASTER_KEY:-}" ] && ok "LITELLM_MASTER_KEY set" || bad "LITELLM_MASTER_KEY unset"
  if [ "${POSTGRES_PASSWORD:-CHANGEME}" = "CHANGEME" ]; then
    bad "POSTGRES_PASSWORD is still CHANGEME"
  else
    ok "POSTGRES_PASSWORD set"
  fi
else
  wrn "litellm/.env missing — cp litellm/.env.example litellm/.env"
fi

if git -C "$ROOT" check-ignore -q litellm/.env 2>/dev/null; then
  ok ".env is gitignored"
else
  [ -f "$ENVF" ] && bad ".env is NOT gitignored — keys would be committed" || true
fi

if grep -qE '^\s*master_key:\s*["'"'"']?sk-' "$CFG" 2>/dev/null; then
  bad "master_key is hardcoded in config.yaml — use os.environ/"
else
  ok "no hardcoded master_key in config.yaml"
fi

# ---------------------------------------------------------------- runtime
hdr "Runtime"

if lsof -nP -iTCP:4000 -sTCP:LISTEN >/dev/null 2>&1; then
  ok "something is listening on :4000 (existing gateway)"
else
  wrn ":4000 not listening — gateway is down"
fi

if lsof -nP -iTCP:5433 -sTCP:LISTEN >/dev/null 2>&1; then
  ok "postgres listening on :5433"
else
  wrn "postgres not up — run scripts/db.sh up (needed for virtual keys)"
fi

if command -v podman >/dev/null 2>&1; then
  ok "podman installed"
  podman info >/dev/null 2>&1 && ok "podman machine running" || wrn "podman machine stopped — scripts/db.sh up will start it"
else
  wrn "podman not installed — brew install podman"
fi

# `launchctl list | grep` misses agents in the gui domain on modern macOS —
# it reported "not loaded" while the gateway was demonstrably serving :4000.
if launchctl print "gui/$(id -u)/com.colinnevin.litellm" >/dev/null 2>&1; then
  ok "launchd agent loaded"
elif launchctl list 2>/dev/null | grep -q com.colinnevin.litellm; then
  ok "launchd agent loaded (legacy list)"
else
  wrn "launchd agent not found — deploy's restart step will not work"
fi

# ---------------------------------------------------------------- exposure
hdr "Exposure"

LANIP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "")
if [ -n "$LANIP" ]; then
  if curl -s -m 3 -o /dev/null "http://${LANIP}:11434/api/tags" 2>/dev/null; then
    wrn "ollama reachable at ${LANIP}:11434 with no auth — bypasses every routing rule (Phase 3)"
  else
    ok "ollama not reachable from the LAN address"
  fi
fi

# ---------------------------------------------------------------- hygiene
hdr "Hygiene"

crlf=$(find "$ROOT/scripts" -name '*.sh' -exec file {} \; 2>/dev/null | grep -c CRLF || true)
[ "$crlf" -eq 0 ] && ok "no CRLF line endings in scripts" || bad "${crlf} script(s) have CRLF — breaks shebangs and launchd"

# macOS /bin/bash is 3.2. bash-4-only syntax passes review, passes on any Linux
# CI, and dies on the target machine. `declare -A` in bench.sh got through
# exactly this way.
# --exclude this file: it contains the patterns literally, in this grep.
bash4=$(grep -lnE 'declare -A|local -A|mapfile|readarray|\$\{[A-Za-z_]+\^\^|\$\{[A-Za-z_]+,,' \
          "$ROOT"/scripts/*.sh 2>/dev/null \
        | grep -v 'preflight\.sh$' | xargs -n1 basename 2>/dev/null | tr '\n' ' ')
if [ -z "$bash4" ]; then
  ok "no bash 4+ syntax (macOS /bin/bash is 3.2)"
else
  bad "bash 4+ syntax in: ${bash4}"
  echo "        These will fail on macOS. Avoid declare -A, mapfile, \${x^^}, \${x,,}."
fi

# Unguarded empty-array expansion is fatal under `set -u` on bash 3.2 only.
unguarded=$(grep -lnE '"\$\{[A-Za-z_]+\[@\]\}"' "$ROOT"/scripts/*.sh 2>/dev/null \
            | grep -v 'preflight\.sh$' \
            | xargs -I{} sh -c 'grep -q "\[@\]+" {} || basename {}' 2>/dev/null | tr '\n' ' ')
if [ -n "$unguarded" ]; then
  wrn "possibly unguarded array expansion in: ${unguarded}"
  echo "        Use \${arr[@]+\"\${arr[@]}\"} if the array can be empty."
fi

if [ -L "$LIVE_CFG" ]; then
  tgt=$(readlink "$LIVE_CFG")
  [ "$tgt" = "$CFG" ] && ok "live config symlinked to repo" || wrn "live config symlinked elsewhere: ${tgt}"
elif [ -f "$LIVE_CFG" ]; then
  wrn "live config is a real file, not yet symlinked to the repo (pre-deploy)"
else
  bad "no live config at ${LIVE_CFG}"
fi

# ---------------------------------------------------------------- verdict
printf '\n\033[1m%d passed, %d warnings, %d failures, %d errors\033[0m\n' \
  "$pass" "$warn" "$fail" "$err"

if [ "$err" -gt 0 ]; then
  echo
  echo "ERRORS mean checks could not run, not that anything is wrong."
  echo "Clear the tooling problem and re-run — until then this report is incomplete."
  exit 2
fi
if [ "$fail" -gt 0 ]; then
  echo "Do not deploy until failures are cleared."
  exit 1
fi
echo "Safe to deploy: scripts/deploy.sh"
