#!/bin/bash
# Read-only. Changes nothing. Run after any edit to config/roles.tsv, the
# scripts, or oMLX's settings — and before trusting a healthcheck.
#
#   scripts/preflight.sh
#
# Static checks: repo integrity, config/roles.tsv ↔ docs/MODELS.md, rule 1
# (model names in two files only), oMLX's saved server settings, where
# secrets live, weight drift (D4), autostart, shell hygiene. The live checks
# (what actually answers, on which interface) are scripts/healthcheck.sh.
#
# Exit 0 clean, 1 a real problem, 2 a check could not run.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"
ROLES="${ROOT}/config/roles.tsv"
MODELS_MD="${ROOT}/docs/MODELS.md"

pass=0; warn=0; fail=0; err=0
ok()   { printf '  \033[32mOK\033[0m    %s\n' "$1"; pass=$((pass+1)); }
wrn()  { printf '  \033[33mWARN\033[0m  %s\n' "$1"; warn=$((warn+1)); }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; fail=$((fail+1)); }
# ERROR = the check could not run. Distinct from FAIL, which means it ran and
# found a problem. Conflating them turns a missing tool into a fake finding.
er()   { printf '  \033[35mERROR\033[0m %s\n' "$1"; err=$((err+1)); }
hdr()  { printf '\n\033[1m%s\033[0m\n' "$1"; }

# ---------------------------------------------------------------- integrity
hdr "Repo integrity"
missing=""
for r in $(grep -rhoE 'scripts/[a-z-]+\.(sh|zsh)' "$ROOT/docs" "$ROOT/scripts" "$ROOT/CLAUDE.md" "$ROOT/README.md" \
             --exclude-dir=decisions --exclude=HISTORY.md --exclude=MIGRATION-LMSTUDIO.md \
             --exclude=PLAN.md --exclude=COMPARISON.md --exclude=SUMMARY-EMAIL.md --exclude=MLX-BENCH.md \
             --exclude=LAPTOP.md --exclude=CLAUDE-PROJECT.md 2>/dev/null | sort -u); do
  [ -f "${ROOT}/${r}" ] || missing="${missing} ${r}"
done
for p in config/roles.tsv docs/MODELS.md bench/tasks docs/decisions pins/digests.tsv; do
  [ -e "${ROOT}/${p}" ] || missing="${missing} ${p}"
done
[ -z "$missing" ] && ok "all referenced scripts and paths exist" || bad "referenced but missing:${missing}"
not_exec=""
for r in "$ROOT"/scripts/*.sh; do
  [ -x "$r" ] || not_exec="${not_exec} $(basename "$r")"
done
[ -z "$not_exec" ] && ok "every script in scripts/ is executable" || bad "present but not executable:${not_exec}"

# ---------------------------------------------------------------- tooling
hdr "Tooling"
omlx_bin=""
for c in /opt/homebrew/bin/omlx "${HOME}/.omlx/bin/omlx" "${HOME}/.omlx/venv/bin/omlx"; do
  [ -x "$c" ] && omlx_bin="$c" && break
done
[ -n "$omlx_bin" ] || omlx_bin="$(command -v omlx 2>/dev/null || true)"
[ -n "$omlx_bin" ] && [ -x "$omlx_bin" ] && ok "omlx at ${omlx_bin}" || er "omlx not installed — scripts/omlx.sh up cannot serve"
[ -x /usr/bin/python3 ] && ok "python3 (stdlib only)" || er "/usr/bin/python3 missing"

# ---------------------------------------------------------------- roles.tsv
hdr "config/roles.tsv"
if [ ! -f "$ROLES" ]; then
  er "config/roles.tsv missing"
else
  probs=$(awk -F'\t' '
    /^[[:space:]]*(#|$)/ {next}
    { n++ }
    NF != 8 { print "line " NR ": " NF " columns, want 8 (role backend model_key ctx slots weights draft load)"; next }
    $7 != "mtp" && $7 != "-" { print $1 ": draft must be mtp or -" }
    $2 == "omlx" && $8 != "resident" && $8 != "demand" { print $1 ": load must be resident or demand" }
    $2 != "omlx" && $8 != "-" { print $1 ": load must be - on a cloud row" }
    $2 == "omlx" && $8 == "resident" { res++ }
    END { if (n > 0 && res == 0) print "no resident omlx role — nothing would serve local-main" }
    seen[$1]++ { print "duplicate role " $1 }
    $2 != "omlx" && $2 != "gemini" { print $1 ": backend \"" $2 "\" is not omlx or an explicit cloud backend (gemini)" }
    $2 == "omlx" && ($4 !~ /^[0-9]+$/ || $5 !~ /^[0-9]+$/) { print $1 ": ctx/slots must be integers" }
    $2 == "omlx" && $1 !~ /^local-/ { print $1 ": an omlx row must be a local-* role" }
    $2 != "omlx" && $1 ~ /^local-/ { print $1 ": a local-* role on a cloud backend — rule 2/3" }
    $3 ~ /:\/\// || $6 ~ /:\/\// { print $1 ": URL in roles.tsv — :1234 must never front a remote model" }
    END { if (n == 0) print "no rows" }' "$ROLES")
  if [ -z "$probs" ]; then
    ok "well-formed; backends omlx/gemini only; local-* only on omlx"
  else
    while IFS= read -r l; do
      [ -n "$l" ] || continue
      bad "$l"
    done <<EOF
$probs
EOF
  fi

  while IFS="$(printf '\t')" read -r role _ _ _ _ w; do
    [ -n "$role" ] || continue
    if [ -e "$HOME/.hearth/models/${w}" ]; then
      ok "${role}: weights on disk"
    else
      bad "${role}: weights path ${w} missing under ~/.hearth/models"
    fi
  done <<EOF
$(hearth_roles omlx)
EOF

  # Rule 1: every concrete name in roles.tsv is in MODELS.md, and nowhere else.
  while IFS="$(printf '\t')" read -r role _ key _ _ w; do
    [ -n "$role" ] || continue
    grep -qF "$key" "$MODELS_MD" && ok "${role}: ${key} documented in MODELS.md" || bad "${role}: ${key} not in docs/MODELS.md (update both together)"
    leaks=$(grep -rlF "$key" "$ROOT/scripts" "$ROOT/client" "$ROOT/bench/tasks" "$ROOT/CLAUDE.md" "$ROOT/README.md" "$ROOT/pins/digests.tsv" 2>/dev/null \
      | grep -v '/pins/digests.tsv$' | sed "s|^$ROOT/||" | tr '\n' ' ')
    [ -z "$leaks" ] && ok "${role}: model key is not hardcoded in scripts, client, or bench tasks (pins/digests.tsv may record it)" \
                     || bad "rule 1: ${key} also named in ${leaks}"
  done <<EOF
$(hearth_roles)
EOF
fi

# ---------------------------------------------------------------- server settings
hdr "oMLX saved server settings"
OMLX_SETTINGS="$HOME/.omlx/settings.json"
if [ ! -f "$OMLX_SETTINGS" ]; then
  er "${OMLX_SETTINGS} missing — scripts/omlx.sh up writes it"
else
  # Print bind, port, cors, fallback only. The file also holds the API key.
  eval "$(/usr/bin/python3 -I -c '
import json, shlex, sys
d = json.load(open(sys.argv[1]))
s = d.get("server") or {}
cors = s.get("cors_origins")
fb = (d.get("model") or {}).get("model_fallback")
print("omlx_host=%s" % shlex.quote(str(s.get("host") or "")))
print("omlx_port=%s" % shlex.quote(str(s.get("port") or "")))
print("omlx_cors=%s" % shlex.quote("off" if cors == [] else "on"))
print("omlx_fallback=%s" % shlex.quote("off" if fb is False else "on"))
' "$OMLX_SETTINGS")"
  [ "$omlx_host" = "127.0.0.1" ] && ok "bind ${omlx_host}" || bad "bind ${omlx_host:-?}, want 127.0.0.1"
  [ "$omlx_port" = "$HEARTH_PORT" ] && ok "port ${HEARTH_PORT}" || bad "port ${omlx_port}, want ${HEARTH_PORT}"
  [ "$omlx_cors" = "off" ] && ok "CORS off" || bad "CORS on — any website you visit could call the server"
  [ "$omlx_fallback" = "off" ] && ok "model fallback off" || bad "model fallback on — an unknown name can be answered by another model"
fi

# ---------------------------------------------------------------- secrets
hdr "Secrets"
if [ -f "$HEARTH_ENV" ]; then
  mode=$(stat -f '%Lp' "$HEARTH_ENV")
  [ "$mode" = "600" ] && ok "${HEARTH_ENV} is mode 600" || bad "${HEARTH_ENV} is mode ${mode}, want 600"
  # Same parse as ai_load_env: optional whitespace and export, one layer of quotes.
  tokline=$(grep -E '^[[:space:]]*(export[[:space:]]+)?LMSTUDIO_HOST_TOKEN=' "$HEARTH_ENV" | tail -1 || true)
  tok="${tokline#*=}"
  tok="${tok%\"}"; tok="${tok#\"}"; tok="${tok%\'}"; tok="${tok#\'}"
  case "$tok" in
    '') bad "LMSTUDIO_HOST_TOKEN not set" ;;
    *...|*CHANGEME*) bad "LMSTUDIO_HOST_TOKEN is a placeholder" ;;
    *) ok "LMSTUDIO_HOST_TOKEN set" ;;
  esac
else
  bad "${HEARTH_ENV} missing"
fi
exported=""
for f in "$HOME/.zshenv" "$HOME/.zshenv.local" "$HOME/.zprofile" "$HOME/.zshrc" "$HOME/.bash_profile" "$HOME/.profile"; do
  [ -f "$f" ] || continue
  grep -qE '^[[:space:]]*export[[:space:]]+(GOOGLE_API_KEY|GEMINI_API_KEY|OPENAI_API_KEY|ANTHROPIC_API_KEY|OPENROUTER_API_KEY|LMSTUDIO_[A-Z_]*TOKEN)=' "$f" \
    && exported="${exported} ${f/#$HOME/~}"
done
[ -z "$exported" ] && ok "no provider key or LM Studio token exported from shell startup files" \
                   || bad "provider key exported into every shell by:${exported} — move it to ${HEARTH_ENV}"
tracked=$(git -C "$ROOT" ls-files 2>/dev/null | grep -E '(^|/)\.env$|\.key$|\.pem$|(^|/)env$' || true)
[ -z "$tracked" ] && ok "no env/key files tracked in git" || bad "tracked secret-looking files: ${tracked}"

# ---------------------------------------------------------------- drift
hdr "Weight drift (D4)"
out=$("${ROOT}/scripts/pin-digests.sh" --check 2>&1); rc=$?
case "$rc" in
  0) ok "weights match pins/digests.tsv (fast check; --check --deep re-hashes)" ;;
  1)
    n=0
    while IFS= read -r l; do
      [ -n "$l" ] || continue
      bad "$l"
      n=$((n+1))
    done <<EOF
$(printf '%s\n' "$out" | grep DRIFT || true)
EOF
    [ "$n" -gt 0 ] || bad "weight drift (pin-digests exited 1)"
    ;;
  *) er "pin-digests could not run: $(printf '%s' "$out" | tail -1)" ;;
esac

# ---------------------------------------------------------------- zed labels
hdr "Zed labels"
zs=$("${ROOT}/scripts/zed-sync.sh" --check 2>&1); zrc=$?
case "$zrc" in
  0) ok "Zed model labels match roles.tsv (scripts/zed-sync.sh)" ;;
  1) wrn "Zed labels out of date: $(printf '%s' "$zs" | grep -E 'DRIFT|MISSING|skip' | head -1) — run scripts/zed-sync.sh" ;;
  *) wrn "zed-sync could not run: $(printf '%s' "$zs" | tail -1)" ;;
esac

# ---------------------------------------------------------------- autostart
hdr "Autostart"
"${ROOT}/scripts/install-autostart.sh" --check >/dev/null 2>&1 \
  && ok "launchd agent $(ai_boot_label) installed and loaded" \
  || wrn "autostart not installed or last run failed — scripts/install-autostart.sh --check"

# ---------------------------------------------------------------- hygiene
hdr "Hygiene"
crlf=$(find "$ROOT/scripts" "$ROOT/config" -type f \( -name '*.sh' -o -name '*.zsh' -o -name '*.tsv' \) -exec file {} \; 2>/dev/null | grep -c CRLF || true)
[ "$crlf" -eq 0 ] && ok "no CRLF line endings in scripts/config" || bad "${crlf} file(s) have CRLF — breaks shebangs and launchd"

# macOS /bin/bash is 3.2. --exclude this file: it contains the patterns.
bash4=$(grep -lnE 'declare -A|local -A|mapfile|readarray|\$\{[A-Za-z_]+\^\^|\$\{[A-Za-z_]+,,' \
          "$ROOT"/scripts/*.sh 2>/dev/null \
        | grep -v 'preflight\.sh$' | xargs -n1 basename 2>/dev/null | tr '\n' ' ')
[ -z "$bash4" ] && ok "no bash 4+ syntax (macOS /bin/bash is 3.2)" || bad "bash 4+ syntax in: ${bash4}"

# Unguarded empty-array expansion is fatal under `set -u` on bash 3.2 only.
unguarded=$(grep -lnE '"\$\{[A-Za-z_]+\[@\]\}"' "$ROOT"/scripts/*.sh 2>/dev/null \
            | grep -v 'preflight\.sh$' \
            | xargs -I{} sh -c 'grep -q "\[@\]+" {} || basename {}' 2>/dev/null | tr '\n' ' ')
[ -z "$unguarded" ] && ok "array expansions guarded" || wrn "possibly unguarded array expansion in: ${unguarded} — use \${arr[@]+\"\${arr[@]}\"}"

# ---------------------------------------------------------------- verdict
printf '\n\033[1m%d passed, %d warnings, %d failures, %d errors\033[0m\n' "$pass" "$warn" "$fail" "$err"
if [ "$err" -gt 0 ]; then
  echo "ERRORS mean checks could not run, not that anything is wrong — this report is incomplete."
  exit 2
fi
[ "$fail" -gt 0 ] && exit 1
exit 0
