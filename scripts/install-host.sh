#!/bin/bash
# Set up this machine as a Hearth host: its own brain on 127.0.0.1:1234
# (ADR 0040). Runs the existing steps in order and stops at the first one
# that needs you. Safe to re-run.
#
#   scripts/install-host.sh --check    # report, change nothing
#   scripts/install-host.sh            # do what can be done, report the rest
#
# Never reads a token. You type secrets in your own terminal; this script
# only checks file modes. Steps that need sudo (scripts/iogpu-wired.sh) are
# printed, not run.
#
# On a machine that is also a client of another host, run
# client/install-client.sh --dual first: the tunnel must leave 1234.
#
# Exit 0 all ok, 1 something needs you, 2 could not run.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"

CHECK=0
case "${1:-}" in
  --check) CHECK=1 ;;
  "") ;;
  -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
  *) echo "usage: $0 [--check]"; exit 2 ;;
esac

rc=0
ok()   { printf 'ok      %s\n' "$1"; }
todo() { printf 'TODO    %s\n' "$1"; rc=1; }
stop() { printf 'STOP    %s\n' "$1"; exit 1; }
mode_ok() { [ -f "$1" ] && [ "$(ls -l "$1" | cut -c5-10)" = "------" ] && [ -s "$1" ]; }

# The largest *Candidates by RAM* shortlist row at or below this machine.
# Read from docs/MODELS.md so this file does not name a model (rule 1).
suggest_unbenched() {
  local ram="$1" models="${ROOT}/docs/MODELS.md"
  [ -f "$models" ] || { echo "suggestion  docs/MODELS.md missing"; return; }
  awk -F'|' -v ram="$ram" '
    BEGIN { best = 0 }
    $0 ~ /^\| [0-9]+ GB \(/ {
      cell = $2
      gsub(/^[ \t]+|[ \t]+$/, "", cell)
      split(cell, a, " ")
      gb = a[1] + 0
      if (gb > 0 && gb <= ram + 0 && gb >= best) {
        best = gb
        label = cell
        agent = $3
        deep = $4
        load = $5
      }
    }
    END {
      if (best == 0) {
        print "suggestion  under 24 GB: no local hearth. This machine stays a client; the tunnel is the only endpoint on 127.0.0.1:1234 (README → Laptops)"
        exit
      }
      gsub(/^[ \t]+|[ \t]+$/, "", agent)
      gsub(/^[ \t]+|[ \t]+$/, "", deep)
      gsub(/^[ \t]+|[ \t]+$/, "", load)
      print "suggestion  " label " — docs/MODELS.md → Candidates by RAM (unbenched, not a role)"
      print "            main-brain: " agent
      print "            deep-brain: " deep
      print "            load: " load
      print "            hearth: this machine, 127.0.0.1:1234"
      print "            hearth-remote: optional, the other host on 127.0.0.1:1235"
    }
  ' "$models"
}

# 1. Port 1234 must be free for oMLX, or already oMLX. A client tunnel there
#    means this machine is a laptop that has not moved its tunnel yet.
if ps axww -o command= 2>/dev/null | grep -F "ssh " | grep -qF -- "-L 127.0.0.1:1234:127.0.0.1:1234"; then
  stop "this machine's hearth tunnel holds 127.0.0.1:1234. Move it first: client/install-client.sh --dual, then in a new shell ai-tunnel-stop && ai-tunnel-install. Re-run this after."
fi
ok "127.0.0.1:1234 is not held by a client tunnel"

# 2. A benched tier row for this much RAM (ADR 0032, rule 5).
ram=$(hearth_ram_gb) || { echo "could not run: cannot read RAM"; exit 2; }
roles=$(hearth_resolved_roles | awk -F'\t' '$2 == "omlx"')
if printf '%s\n' "$roles" | awk -F'\t' '$1 == "main-brain"' | grep -q .; then
  ok "${ram} GB RAM: benched main-brain row, ceiling $(hearth_gpu_ceiling_gb) GB"
else
  suggest_unbenched "$ram"
  stop "${ram} GB RAM has no benched main-brain row. The suggestion above is not installed. A row needs bench/tasks and scripts/concurrency-bench.sh on this hardware first (rule 5)."
fi

# 3. oMLX installed (README → Install oMLX).
if [ -x "${HOME}/.omlx/bin/omlx" ] || [ -x "${HOME}/.omlx/venv/bin/omlx" ]; then
  ok "oMLX installed"
else
  todo "oMLX not installed — README → Install oMLX (DMG app or headless venv)"
fi
if pgrep -f omlx-server >/dev/null 2>&1 && ! nc -z 127.0.0.1 1234 >/dev/null 2>&1; then
  todo "an omlx-server is running but not on 1234 (a brew service?). Stop it first: brew services stop omlx"
fi

# 4. Weights for every role this host loads (resident and on-demand).
missing=0
while IFS="$(printf '\t')" read -r role _b _k _c _s weights _d load; do
  [ -n "$role" ] || continue
  case "$load" in edit) continue ;; esac   # edit-brain: client/edit-model.sh, not this host
  if [ -d "${HOME}/.hearth/models/${weights}" ]; then
    ok "${role}: weights present"
  elif [ "$load" = beside ] || [ "$load" = swap ]; then
    printf 'skip    %s: not installed (optional; ask-deep needs ~/.hearth/models/%s — docs/MODELS.md)\n' "$role" "$weights"
  else
    todo "${role}: no weights at ~/.hearth/models/${weights} — source and revision in docs/MODELS.md"
    missing=1
  fi
done <<EOF
$roles
EOF

# 5. Host token: presence and mode only.
if mode_ok "$HEARTH_ENV"; then
  ok "${HEARTH_ENV/#$HOME/~} present, mode 600"
else
  todo "host token: in your own terminal, docs/RUNBOOK.md → First-time setup step 2 (writes ${HEARTH_ENV/#$HOME/~}, mode 600)"
fi

# 6. Serve, autostart, aliases. Only when nothing above needs you.
if [ "$CHECK" -eq 0 ] && [ "$rc" -eq 0 ]; then
  "${ROOT}/scripts/omlx.sh" up || todo "scripts/omlx.sh up failed — see its output"
  "${ROOT}/scripts/install-autostart.sh" --apply >/dev/null 2>&1 \
    && ok "autostart installed (com.hearth.boot)" \
    || todo "autostart: scripts/install-autostart.sh --apply failed"
  zrc="${HOME}/.zshrc"
  if grep -qF "scripts/aliases.zsh" "$zrc" 2>/dev/null; then
    ok "~/.zshrc sources scripts/aliases.zsh"
  else
    printf '\nsource %s/scripts/aliases.zsh\n' "$ROOT" >> "$zrc" && ok "added scripts/aliases.zsh to ~/.zshrc"
  fi
elif [ "$CHECK" -eq 0 ]; then
  echo "        (not starting oMLX until the TODOs above are done)"
fi
if [ "$CHECK" -eq 1 ]; then
  "${ROOT}/scripts/install-autostart.sh" --check >/dev/null 2>&1 \
    && ok "autostart installed" || todo "autostart not installed"
fi

# 7. GPU wired limit (sudo — printed, never run).
want=$(( $(hearth_gpu_ceiling_gb) * 1024 ))
have=$(sysctl -n iogpu.wired_limit_mb 2>/dev/null || echo 0)
[ "$have" = "$want" ] && ok "iogpu.wired_limit_mb ${have}" \
  || todo "iogpu.wired_limit_mb ${have}, want ${want}: run scripts/iogpu-wired.sh (asks for your password)"

# 8. Pins (D4). Re-record only after a re-bench (rule 6).
[ "$missing" -eq 0 ] && { "${ROOT}/scripts/pin-digests.sh" --check >/dev/null 2>&1 \
  && ok "weights match pins/digests.tsv" \
  || todo "weights differ from pins/digests.tsv — scripts/pin-digests.sh --check; re-record only after a re-bench (rule 6)"; }

# 9. Proof.
if [ "$rc" -eq 0 ]; then
  "${ROOT}/scripts/preflight.sh" >/dev/null 2>&1 && ok "preflight passes" || todo "preflight: run scripts/preflight.sh and fix each FAIL"
  "${ROOT}/scripts/healthcheck.sh" >/dev/null 2>&1 && ok "healthcheck passes" || todo "healthcheck: run scripts/healthcheck.sh"
fi

echo
echo "hearth: this machine, 127.0.0.1:1234"
if [ -f "${HOME}/.hearth-key" ]; then
  echo "hearth-remote: optional. A client key is present; keep that tunnel on 1235 (client/install-client.sh --dual, ADR 0040)."
else
  echo "hearth-remote: optional. Skip it, or add another host with client/install-client.sh --dual."
fi
exit "$rc"
