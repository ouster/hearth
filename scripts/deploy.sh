#!/bin/bash
# Point the running gateway at this repo. Verifies each step, rolls back on failure.
#
#   scripts/deploy.sh           # deploy, with confirmation
#   scripts/deploy.sh --dry     # show what would happen
#   scripts/deploy.sh --rollback
#
# launchd and the plist are never touched. run-litellm.sh already loads
# ~/.config/litellm/config.yaml, so we only swap that file for a symlink.
# Rollback is therefore one mv.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"
CFG="${ROOT}/litellm/config.yaml"
LIVE="$HOME/.config/litellm/config.yaml"
BACKUP="$HOME/.config/litellm/config.yaml.pre-hearth"
AGENT="$(ai_litellm_agent)"

say()  { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
ok()   { printf '    \033[32mok\033[0m %s\n' "$1"; }
bad()  { printf '    \033[31mfail\033[0m %s\n' "$1"; }

wait_ready() {
  printf '    waiting for gateway'
  for _ in $(seq 1 30); do
    if curl -s -m 3 -o /dev/null "http://127.0.0.1:4000/health/readiness"; then
      echo; return 0
    fi
    printf '.'; sleep 1
  done
  echo; return 1
}

rollback() {
  say "Rolling back"
  if [ -f "$BACKUP" ]; then
    rm -f "$LIVE"
    mv "$BACKUP" "$LIVE"
    ok "restored previous config"
    launchctl kickstart -k "$AGENT" 2>/dev/null
    wait_ready && ok "gateway back up on the old config" || bad "gateway did not come back — check ~/Library/Logs/litellm.error.log"
  else
    bad "no backup at ${BACKUP} — nothing to restore"
  fi
}

# ------------------------------------------------------------------ rollback
if [ "${1:-}" = "--rollback" ]; then rollback; exit $?; fi

DRY=false
[ "${1:-}" = "--dry" ] && DRY=true

# ------------------------------------------------------------------ 1. preflight
say "1/5 Preflight"
if ! bash "${ROOT}/scripts/preflight.sh"; then
  bad "preflight failed — not deploying"
  exit 1
fi

if $DRY; then
  say "Dry run — would do:"
  echo "    mv ${LIVE} ${BACKUP}"
  echo "    ln -s ${CFG} ${LIVE}"
  echo "    launchctl kickstart -k ${AGENT}"
  echo "    scripts/healthcheck.sh"
  exit 0
fi

echo
read -r -p "Deploy? The gateway will restart. [y/N] " c
[ "$c" = "y" ] || { echo "aborted"; exit 0; }

# ------------------------------------------------------------------ 2. backup
say "2/5 Backup"
if [ -L "$LIVE" ]; then
  ok "already a symlink — leaving existing backup intact"
elif [ -f "$LIVE" ]; then
  cp "$LIVE" "$BACKUP"
  ok "saved ${BACKUP}"
else
  bad "no live config to back up"; exit 1
fi

# ------------------------------------------------------------------ 3. symlink
say "3/5 Symlink"
rm -f "$LIVE"
ln -s "$CFG" "$LIVE"
[ -L "$LIVE" ] && ok "$(readlink "$LIVE")" || { bad "symlink failed"; rollback; exit 1; }

# ------------------------------------------------------------------ 4. restart
say "4/5 Restart"
launchctl kickstart -k "$AGENT" 2>/dev/null || true
if wait_ready; then
  ok "gateway responding"
else
  bad "gateway did not come up"
  echo
  tail -20 "$HOME/Library/Logs/litellm.error.log" 2>/dev/null | sed 's/^/    /'
  rollback
  exit 1
fi

# ------------------------------------------------------------------ 5. verify
say "5/5 Verify"
bash "${ROOT}/scripts/healthcheck.sh"
hc=$?
case $hc in
  0) ok "all roles healthy" ;;
  2)
    # Exit 2 = the check could not run (missing key, no yaml). The gateway
    # itself is fine — it already answered /health/readiness above. Rolling
    # back a working deploy because a script could not read a env var would
    # be absurd, so do not even offer.
    bad "healthcheck could not run — but the gateway is up and serving"
    echo "    Not offering rollback: step 4 already proved the gateway responds."
    echo "    Fix the script's environment and re-run scripts/healthcheck.sh."
    ;;
  *)
    bad "healthcheck ran and found real failures"
    echo
    read -r -p "Roll back? [y/N] " r
    [ "$r" = "y" ] && { rollback; exit 1; }
    echo "    keeping the new config"
    ;;
esac

say "Deployed"
cat <<EOF
    Live config: ${LIVE} -> ${CFG}
    Rollback:    scripts/deploy.sh --rollback

    Next:
      scripts/db.sh up          if Postgres is not running
      scripts/create-keys.sh    virtual keys, once Postgres is up
      scripts/healthcheck.sh    re-run to exercise the private-key leak test
EOF
