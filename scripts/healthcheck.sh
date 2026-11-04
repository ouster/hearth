#!/bin/bash
# Is local inference healthy, and does the boundary hold? (ADR 0016)
#
#   scripts/healthcheck.sh
#
# Every refusal is paired with a positive control. "No token → 401" proves
# nothing on its own — a broken server refuses everything — so the host token
# must also get 200 on the same path.
#
#   1. server answers; the host token works (positive control)
#   2. no token → 401, wrong token → 401
#   3. each resident lmstudio role in config/roles.tsv answers a real request, and each
#      chat role thinks with its reasoning parsed out of the answer
#   4. what is actually listening on :1234, and only LM Studio
#   5. LAN: no answer — laptops use the SSH tunnel (D8). Any LAN answer fails.
#   6. CORS: no Access-Control-Allow-Origin for a foreign Origin
#   7. JIT off: a model on disk but not in roles.tsv is never loaded. (LM Studio
#      answers an unknown model name with the loaded LLM rather than refusing —
#      reported as a warning.)
#   8. Open WebUI and SearXNG answer (warning only)
#
# Exit 0 healthy, 1 a real problem, 2 a check could not run.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"
ai_load_env

pass=0; fail=0; err=0; warn=0
ok()  { printf '  \033[32mOK\033[0m    %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; fail=$((fail+1)); }
wrn() { printf '  \033[33mWARN\033[0m  %s\n' "$1"; warn=$((warn+1)); }
# ERROR = the check could not run. Never report it as FAIL.
er()  { printf '  \033[35mERROR\033[0m %s\n' "$1"; err=$((err+1)); }
hdr() { printf '\n\033[1m%s\033[0m\n' "$1"; }

TOK="${LMSTUDIO_HOST_TOKEN:-}"
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT

# POST JSON with the token; body → $TMPD/out, prints HTTP code.
post() {
  printf 'header = "Authorization: Bearer %s"\n' "$TOK" \
    | curl -s -m "${3:-60}" -o "$TMPD/out" -w '%{http_code}' -K - \
        -H 'Content-Type: application/json' -d "$2" "${HEARTH_URL}$1" 2>/dev/null
}

# ---------------------------------------------------------------- 1. server
hdr "1. Server"
[ -n "$TOK" ] || { er "LMSTUDIO_HOST_TOKEN not set in ${HEARTH_ENV} — nothing below is meaningful"; }
holder="$(lsof -nP -iTCP:"${HEARTH_PORT}" -sTCP:LISTEN 2>/dev/null | awk 'NR==2 {print $1}')"
case "$holder" in
  Python|python*|omlx) ok "oMLX serves ${HEARTH_URL} (ADR 0026)" ;;
  *) bad "oMLX is not serving on :${HEARTH_PORT} (scripts/omlx.sh up)" ;;
esac
code=$(hearth_http /models "$TOK")
SERVER_OK=0
case "$code" in
  200) ok "host token → 200 on /v1/models (positive control)"; SERVER_OK=1 ;;
  401) bad "host token → 401 — token wrong or revoked" ;;
  000) bad "server not answering on ${HEARTH_URL} (scripts/boot.sh)" ;;
  *)   bad "host token → ${code} on /v1/models" ;;
esac

# ---------------------------------------------------------------- 2. auth
hdr "2. Authentication"
if [ "$SERVER_OK" -eq 1 ]; then
  c=$(hearth_http /models)
  [ "$c" = "401" ] && ok "no token → 401" || bad "no token → ${c} — Require Authentication is OFF"
  c=$(hearth_http /models "hearth-healthcheck-not-a-token")
  [ "$c" = "401" ] && ok "wrong token → 401" || bad "wrong token → ${c}"
else
  er "skipped: no positive control, a refusal here would prove nothing"
fi

# ---------------------------------------------------------------- 3. roles
hdr "3. Roles (config/roles.tsv)"
if [ "$SERVER_OK" -eq 1 ]; then
  while IFS="$(printf '\t')" read -r role _ key _ _; do
    [ -n "$role" ] || continue
    case "$key" in
      *embed*)
        c=$(post /embeddings "{\"model\":\"${role}\",\"input\":\"healthcheck\"}" 30)
        if [ "$c" = "200" ] && /usr/bin/python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); assert len(d["data"][0]["embedding"])>0' "$TMPD/out" 2>/dev/null; then
          ok "${role}: embedding returned"
        else
          bad "${role}: embeddings → ${c}"
        fi ;;
      *)
        c=$(post /chat/completions "{\"model\":\"${role}\",\"max_tokens\":64,\"messages\":[{\"role\":\"user\",\"content\":\"Reply with the word ok.\"}]}" 120)
        if [ "$c" = "200" ] && /usr/bin/python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); m=d["choices"][0]["message"]; assert (m.get("content") or m.get("reasoning_content"))' "$TMPD/out" 2>/dev/null; then
          ok "${role}: chat completion returned"
          # Thinking can depend on settings held in the LM Studio app, not the
          # repo (docs/MODELS.md). A reset turns it off silently, so prove it.
          c=$(post /chat/completions "{\"model\":\"${role}\",\"max_tokens\":3000,\"messages\":[{\"role\":\"user\",\"content\":\"Pens are 3 for \$2.10 and notebooks \$1.35 each. 7 pens and 4 notebooks, paid with \$20. Change? Amount only.\"}]}" 300)
          why=$(/usr/bin/python3 -I -c '
import json, sys
m = json.load(open(sys.argv[1]))["choices"][0]["message"]
c = m.get("content") or ""
if not (m.get("reasoning_content") or "").strip(): print("no reasoning_content")
elif any(t in c for t in ("<think>", "</think>", "<|channel>", "<channel|>")): print("thinking markers in the answer")
' "$TMPD/out" 2>/dev/null || echo "unreadable reply")
          if [ "$c" != "200" ]; then
            bad "${role}: thinking probe → ${c}"
          elif [ -n "$why" ]; then
            bad "${role}: thinking off or unparsed (${why}) — LM Studio per-model settings, docs/MODELS.md"
          else
            ok "${role}: thinks, and reasoning is parsed out of the answer"
          fi
        else
          bad "${role}: chat → ${c} $(head -c 160 "$TMPD/out" 2>/dev/null)"
        fi ;;
    esac
  done <<EOF
$(hearth_resident_roles)
EOF
  # Calling an unloaded demand role would be answered by local-main (JIT off).
  for r in $(hearth_demand_roles); do
    echo "        ${r}: loaded on demand by ask-deep — not called here"
  done
else
  er "skipped: server not answering"
fi

# ---------------------------------------------------------------- 4. listener
hdr "4. Listener on :${HEARTH_PORT}"
# The command may contain spaces (\x20 in lsof). The address is the field
# that looks like host:port; "(LISTEN)" is a separate trailing field.
listen=$(lsof -nP -iTCP:"$HEARTH_PORT" -sTCP:LISTEN 2>/dev/null | awk '
  NR>1 {
    addr=""
    for (i=1; i<=NF; i++) if ($i ~ /:[0-9]+$/) addr=$i
    if (addr != "") print $1 "\t" addr
  }' | sort -u)
if [ -z "$listen" ]; then
  er "nothing listening, or lsof could not see it"
else
  others=$(printf '%s\n' "$listen" | cut -f1 | grep -viE '^(LM|lms|llmster|Python|python|omlx)' || true)
  if [ -n "$others" ]; then
    bad "something else listens on :${HEARTH_PORT}: ${others}"
  elif printf '%s\n' "$listen" | cut -f1 | grep -qiE '^(Python|python|omlx)$'; then
    ok "oMLX listens on :${HEARTH_PORT}"
  else
    ok "only LM Studio listens on :${HEARTH_PORT}"
  fi
  bad_bind=""
  while IFS="$(printf '\t')" read -r _ addr; do
    [ -n "$addr" ] || continue
    case "$addr" in
      127.0.0.1:${HEARTH_PORT}|"[::1]:${HEARTH_PORT}") ;;
      *) bad_bind="${bad_bind} ${addr}" ;;
    esac
  done <<EOF
$listen
EOF
  if [ -z "$bad_bind" ]; then
    ok "loopback only ($(printf '%s\n' "$listen" | cut -f2 | paste -sd ' ' -))"
  else
    bad "not loopback-only:${bad_bind} — D8 is the SSH tunnel; scripts/boot.sh rebinds"
  fi
fi

# ---------------------------------------------------------------- 5. LAN
hdr "5. LAN"
LAN=$(ai_lan_ip)
if [ -z "$LAN" ]; then
  er "no LAN address found — LAN exposure is INCONCLUSIVE, not safe"
else
  c=$(hearth_http /models "" "http://${LAN}:${HEARTH_PORT}/v1")
  case "$c" in
    000) ok "LAN ${LAN}: no answer (localhost-only; laptops use the SSH tunnel, D8)" ;;
    *)   bad "LAN ${LAN}: answered ${c} — D8 is tunnel only; scripts/boot.sh rebinds to 127.0.0.1" ;;
  esac
fi

# ---------------------------------------------------------------- 6. CORS
hdr "6. CORS"
if [ "$SERVER_OK" -eq 1 ]; then
  # GET and OPTIONS. A missing status line is "could not run", not a pass:
  # silence used to look like CORS off.
  cors_bad=""
  cors_err=""
  for method in GET OPTIONS; do
    hdr=$(curl -s -m 5 -D - -o /dev/null -X "$method" \
      -H 'Origin: https://hearth-healthcheck.invalid' "${HEARTH_URL}/models" 2>/dev/null | tr -d '\r')
    printf '%s\n' "$hdr" | grep -q '^HTTP/' || cors_err="${cors_err} ${method}"
    acao=$(printf '%s\n' "$hdr" | awk -F': ' 'tolower($1)=="access-control-allow-origin" {print $2; exit}')
    [ -z "$acao" ] || cors_bad="${cors_bad} ${method}=${acao}"
  done
  if [ -n "$cors_err" ]; then
    er "CORS check got no HTTP status for:${cors_err}"
  elif [ -n "$cors_bad" ]; then
    bad "CORS on (${cors_bad}) — any website you visit can call the server (scripts/boot.sh locks it off)"
  else
    ok "no Access-Control-Allow-Origin on GET or OPTIONS (both returned HTTP status lines)"
  fi
else
  er "skipped: server not answering"
fi

# ---------------------------------------------------------------- 7. JIT
hdr "7. JIT loading off"
if [ "$SERVER_OK" -eq 1 ]; then
  listed=$(hearth_roles lmstudio | cut -f3 | tr '\n' '|')
  probe=$("$HEARTH_LMS" ls --json 2>/dev/null | /usr/bin/python3 -I -c '
import json, sys
listed = set(sys.argv[1].strip("|").split("|"))
for m in json.load(sys.stdin):
    k = m.get("modelKey", "")
    if m.get("type") == "llm" and k not in listed and not any(k == l.split("@")[0] for l in listed):
        print(k); break
' "$listed")
  if [ -z "$probe" ]; then
    er "no unlisted LLM on disk to probe JIT with"
  else
    before=$("$HEARTH_LMS" ps --json 2>/dev/null | grep -c "\"modelKey\":\"${probe}\"" || true)
    c=$(post /chat/completions "{\"model\":\"${probe}\",\"max_tokens\":1,\"messages\":[{\"role\":\"user\",\"content\":\"x\"}]}" 30)
    sleep 1
    after=$("$HEARTH_LMS" ps --json 2>/dev/null | grep -c "\"modelKey\":\"${probe}\"" || true)
    served=$(/usr/bin/python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1])).get("model",""))' "$TMPD/out" 2>/dev/null)
    if [ "$after" -gt "$before" ]; then
      bad "unlisted model (${probe}) was LOADED — JIT loading is ON; reloading roles.tsv"
      "$HEARTH_LMS" unload --all >/dev/null 2>&1; "${ROOT}/scripts/lms-load.sh" >/dev/null 2>&1
    elif [ "$c" = "200" ]; then
      ok "unlisted model (${probe}) not loaded (JIT off)"
      wrn "LM Studio answers an unknown model name with '${served}' instead of refusing — a typo silently gets that role (local, so not a leak)"
    else
      ok "unlisted model (${probe}) refused with ${c}, not loaded"
    fi
  fi
else
  er "skipped: server not answering"
fi

# ---------------------------------------------------------------- 8. UI
hdr "8. Open WebUI / SearXNG (down is a warning; a LAN bind is a failure)"
for pu in "Open WebUI|3000|http://127.0.0.1:3000/health" "SearXNG|8888|http://127.0.0.1:8888/"; do
  n="${pu%%|*}"; rest="${pu#*|}"; p="${rest%%|*}"; u="${rest#*|}"
  c=$(curl -s -m 5 -o /dev/null -w '%{http_code}' "$u" 2>/dev/null)
  [ "$c" = "200" ] && ok "${n} answering" || wrn "${n} not answering (${c}) — the Podman VM may have stopped: scripts/boot.sh"
  wan=$(hearth_wan_binds "$p")
  [ -z "$wan" ] || bad "${n} is not loopback-only:${wan}"
done

# ---------------------------------------------------------------- verdict
printf '\n\033[1m%d passed, %d warnings, %d failed, %d errors\033[0m\n' "$pass" "$warn" "$fail" "$err"
[ "$err" -gt 0 ] && { echo "ERRORS mean a check could not run — this report is incomplete."; exit 2; }
[ "$fail" -gt 0 ] && exit 1
exit 0
