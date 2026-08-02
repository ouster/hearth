#!/bin/bash
# Does sandboxing actually work on this machine?
#
# Read-only. Runs no agent, changes no config, writes only to a temp dir.
#
# Exit codes follow preflight.sh:
#   0  everything verified
#   1  FAIL  -- a control does not hold. The sandbox is not doing its job.
#   2  ERROR -- a check could not run. Unknown, not safe.
#
# The distinction matters here more than anywhere else in this repo. If the
# SBPL profile fails to COMPILE, then every sandboxed command fails to start,
# and a naive probe would see "could not reach the internet" and "could not
# write to HOME" and report perfect containment. That is the same false-pass
# that bit the leak test. So the first thing this does is prove the profile
# loads and that an allowed action still SUCCEEDS.
#
set -u

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SELF_DIR/.." && pwd)
GATEWAY_PORT=${GATEWAY_PORT:-4000}

PASS=0; FAIL=0; ERRS=0
pass()  { printf "  \033[32mPASS\033[0m   %s\n" "$1"; PASS=$((PASS+1)); }
fail()  { printf "  \033[31mFAIL\033[0m   %s\n" "$1"; FAIL=$((FAIL+1)); }
err()   { printf "  \033[33mERROR\033[0m  %s\n" "$1"; ERRS=$((ERRS+1)); }
info()  { printf "         %s\n" "$1"; }
head_() { printf "\n\033[1m%s\033[0m\n" "$1"; }

TMPD=$(mktemp -d -t aistack-probe) || { echo "mktemp failed" >&2; exit 2; }
trap 'rm -rf "$TMPD"' EXIT INT TERM

# ---------------------------------------------------------------------------
head_ "1. Does the primitive exist"
# ---------------------------------------------------------------------------

if [ "$(uname -s)" != "Darwin" ]; then
    err "not macOS -- this probe only means anything on the Studio"
    exit 2
fi
info "macOS $(sw_vers -productVersion 2>/dev/null || echo '?')"

if ! command -v sandbox-exec >/dev/null 2>&1; then
    fail "sandbox-exec not found -- Apple has removed it. The wrapper cannot work."
    info "Fall back to a Lima VM or a separate user account. See docs/THREAT-MODEL.md."
    exit 1
fi
pass "sandbox-exec present at $(command -v sandbox-exec)"

if sandbox-exec -p '(version 1)(allow default)' /usr/bin/true 2>"$TMPD/min.err"; then
    pass "a minimal profile loads and runs"
else
    fail "even a minimal profile will not run -- sandboxing is unavailable"
    info "$(head -3 "$TMPD/min.err" 2>/dev/null)"
    exit 1
fi

# ---------------------------------------------------------------------------
head_ "2. Does OUR profile compile"
# ---------------------------------------------------------------------------

WORK="$TMPD/work"; mkdir -p "$WORK"

if [ ! -x "$SELF_DIR/sandboxed.sh" ]; then
    if [ -f "$SELF_DIR/sandboxed.sh" ]; then
        err "sandboxed.sh exists but is not executable -- run: chmod +x scripts/sandboxed.sh"
    else
        err "scripts/sandboxed.sh missing"
    fi
    exit 2
fi

if ! "$SELF_DIR/sandboxed.sh" --dir "$WORK" --gateway-port "$GATEWAY_PORT" \
        --print-profile > "$TMPD/profile.sb" 2>"$TMPD/gen.err"; then
    err "could not generate the profile"
    info "$(head -5 "$TMPD/gen.err")"
    exit 2
fi
info "profile is $(wc -l < "$TMPD/profile.sb" | tr -d ' ') lines"

if sandbox-exec -f "$TMPD/profile.sb" /usr/bin/true 2>"$TMPD/load.err"; then
    pass "the real profile compiles and a trivial command runs under it"
    PROFILE_OK=1
else
    fail "the real profile does not load"
    info "$(head -5 "$TMPD/load.err")"
    PROFILE_OK=0
fi

# If it did not load, find out which line macOS objects to, rather than
# making you bisect it by hand.
if [ "$PROFILE_OK" -eq 0 ]; then
    head_ "2b. Which line is macOS rejecting"
    SUSPECTS='(allow network-outbound (remote unix-socket))
(allow network-bind (local ip "localhost:*"))
(allow file-write* (regex #"^/dev/tty"))
(allow file-ioctl (regex #"^/dev/tty"))
(allow ipc-posix-shm)'
    printf '%s\n' "$SUSPECTS" | while IFS= read -r line; do
        [ -n "$line" ] || continue
        grep -vF "$line" "$TMPD/profile.sb" > "$TMPD/without.sb"
        if sandbox-exec -f "$TMPD/without.sb" /usr/bin/true 2>/dev/null; then
            printf "  \033[33m>>>\033[0m removing this line FIXES it:\n         %s\n" "$line"
        fi
    done
    info "no single removal fixed it? then the problem is structural -- paste"
    info "the error above and we will rebuild the profile from a minimal base."
    echo
    printf "\033[1m%s\033[0m\n" "SUMMARY: $PASS passed, $FAIL failed, $ERRS errors"
    exit 1
fi

# ---------------------------------------------------------------------------
head_ "3. Positive controls (unsandboxed) -- what is even reachable right now"
# ---------------------------------------------------------------------------
# Without these, the deny tests below are uninterpretable. A machine with no
# internet "passes" an egress-blocking test trivially and tells you nothing.

GW_LIVE=0
if curl -s --max-time 4 -o /dev/null "http://127.0.0.1:$GATEWAY_PORT/health/liveliness" 2>/dev/null; then
    pass "gateway reachable unsandboxed on :$GATEWAY_PORT"
    GW_LIVE=1
else
    err "gateway NOT reachable unsandboxed -- start it, or test 4 proves nothing"
fi

NET_LIVE=0
if curl -s --max-time 5 -o /dev/null "https://1.1.1.1" 2>/dev/null; then
    pass "internet reachable unsandboxed (so a block below is meaningful)"
    NET_LIVE=1
else
    err "no internet unsandboxed -- cannot prove the egress block does anything"
fi

# ---------------------------------------------------------------------------
head_ "4. The controls that matter"
# ---------------------------------------------------------------------------

SB="sandbox-exec -f $TMPD/profile.sb"

# 4a. ALLOWED path must still work. If this fails the sandbox is useless --
#     aider could not talk to the gateway and you would just turn it off.
if [ "$GW_LIVE" -eq 1 ]; then
    if $SB curl -s --max-time 4 -o /dev/null "http://127.0.0.1:$GATEWAY_PORT/health/liveliness" 2>/dev/null; then
        pass "sandboxed process CAN still reach the gateway  (aider will work)"
    else
        fail "sandboxed process CANNOT reach the gateway -- profile is too tight"
        info "everything below may look secure only because nothing runs"
    fi
else
    err "skipped: gateway not up"
fi

# 4b. DENIED path must fail. This is the whole point.
if [ "$NET_LIVE" -eq 1 ]; then
    if $SB curl -s --max-time 5 -o /dev/null "https://1.1.1.1" 2>/dev/null; then
        fail "sandboxed process REACHED THE INTERNET -- egress block does not hold"
        info "this is the control the design depends on. Do not rely on the sandbox."
    else
        pass "sandboxed process cannot reach 1.1.1.1  (exfiltration channel closed)"
    fi

    if $SB curl -s --max-time 5 -o /dev/null "https://example.com" 2>/dev/null; then
        fail "sandboxed process resolved DNS and connected out"
    else
        pass "sandboxed process cannot resolve hostnames"
    fi
else
    err "skipped: no baseline internet to block"
fi

# 4c. Writes inside the workdir must succeed.
if $SB /bin/sh -c "echo ok > '$WORK/canary'" 2>/dev/null && [ -f "$WORK/canary" ]; then
    pass "sandboxed process CAN write inside its working directory"
else
    fail "sandboxed process cannot write to its own workdir -- unusable"
fi

# 4d. Writes outside must fail. Use a path we then verify did NOT appear.
OUTSIDE="$HOME/.hearth-sandbox-canary"
rm -f "$OUTSIDE" 2>/dev/null
$SB /bin/sh -c "echo escaped > '$OUTSIDE'" 2>/dev/null
if [ -f "$OUTSIDE" ]; then
    fail "sandboxed process WROTE TO \$HOME -- write confinement does not hold"
    rm -f "$OUTSIDE"
else
    pass "sandboxed process cannot write outside its working directory"
fi

# 4e. The honest one: reads are NOT confined, by design. Verify that is true
#     so the threat model does not overstate what this buys you.
if $SB /bin/sh -c "head -c 1 '$HOME/.zshrc' >/dev/null 2>&1"; then
    info "note: reads are unconfined by design -- a sandboxed agent CAN still"
    info "      read your keys and dotfiles. Egress is what stops them leaving."
fi

# ---------------------------------------------------------------------------
echo
if [ "$FAIL" -gt 0 ]; then
    printf "\033[1;31mSUMMARY: %s passed, %s FAILED, %s errors\033[0m\n" "$PASS" "$FAIL" "$ERRS"
    echo "Do not rely on the sandbox until the failures above are resolved."
    exit 1
elif [ "$ERRS" -gt 0 ]; then
    printf "\033[1;33mSUMMARY: %s passed, 0 failed, %s ERRORS\033[0m\n" "$PASS" "$ERRS"
    echo "Some controls were not exercised. Unknown is not the same as safe."
    exit 2
else
    printf "\033[1;32mSUMMARY: %s passed, 0 failed, 0 errors\033[0m\n" "$PASS"
    echo "Containment verified: gateway reachable, everything else is not."
    exit 0
fi
