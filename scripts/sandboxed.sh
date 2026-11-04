#!/bin/bash
# Run an agent with its capabilities cut down.
#
# Two restrictions, in order of how much they matter:
#
#   1. EGRESS. The process may reach oMLX on 127.0.0.1:1234 (ADR 0016)
#      and nothing else. This is the control that stops exfiltration. curl to an
#      attacker, git push, pip install, DNS -- all fail.
#
#   2. WRITES. Confined to the working directory plus temp.
#
# Reads are deliberately NOT restricted. Restricting them breaks dylib
# loading and every language runtime, and read confinement is not the point:
# an injected agent can still read ~/.ssh/id_rsa. It just has nowhere to
# send it. See docs/THREAT-MODEL.md.
#
# This is not a jail. sandbox-exec has known weaknesses and this profile
# allows broad mach-lookup and process-exec. It raises the cost of an attack
# and closes the specific channel that matters. Do not treat it as a VM.
#
# Usage:
#   scripts/sandboxed.sh aider
#   scripts/sandboxed.sh --dir ~/dev/some-repo aider --model openai/local-main
#   scripts/sandboxed.sh --print-profile
#
set -eu

SELF_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SELF_DIR/.." && pwd)

WORKDIR=$(pwd)
GATEWAY_PORT=1234   # oMLX. Flag name kept from the gateway era.
PRINT_ONLY=0
EXTRA_WRITE=""

usage() {
    sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dir)
            [ $# -ge 2 ] || { echo "--dir needs a path" >&2; exit 2; }
            WORKDIR=$2; shift 2 ;;
        --gateway-port)
            [ $# -ge 2 ] || { echo "--gateway-port needs a number" >&2; exit 2; }
            GATEWAY_PORT=$2; shift 2 ;;
        --also-write)
            # Widens the sandbox. Every use of this should be justified.
            [ $# -ge 2 ] || { echo "--also-write needs a path" >&2; exit 2; }
            EXTRA_WRITE="$EXTRA_WRITE $2"; shift 2 ;;
        --print-profile)
            PRINT_ONLY=1; shift ;;
        -h|--help)
            usage ;;
        --)
            shift; break ;;
        -*)
            echo "unknown option: $1" >&2; exit 2 ;;
        *)
            break ;;
    esac
done

# Resolve to a real path -- SBPL subpath matching is literal, and /tmp and
# ~ are symlinks on macOS. A profile built from an unresolved path silently
# fails to match and the sandbox is tighter than intended.
WORKDIR=$(cd "$WORKDIR" 2>/dev/null && pwd -P) || {
    echo "ERROR: --dir does not exist or is not a directory" >&2; exit 2; }

# NOTE: the sandbox-exec check deliberately comes AFTER --print-profile is
# handled, so the profile can be read and reviewed on any machine. A security
# control you cannot audit without being on the target host is a bad control.

HOME_REAL=$(cd "$HOME" && pwd -P)

emit_profile() {
    cat <<SBPL
(version 1)

;; Default deny. Everything below is an explicit exception with a reason.
(deny default)

;; ---------------------------------------------------------------
;; Process. Without these nothing starts at all.
;; ---------------------------------------------------------------
(allow process-fork)
(allow process-exec*)
(allow signal (target self))
(allow sysctl-read)
(allow ipc-posix-shm)

;; Broad, and the weakest line in this profile. Required for basic runtime
;; services; a determined attacker with code execution may find leverage
;; here. Recorded honestly rather than hidden. See docs/THREAT-MODEL.md.
(allow mach-lookup)

;; ---------------------------------------------------------------
;; Reads: deliberately unrestricted. See the header of this script.
;; ---------------------------------------------------------------
(allow file-read*)

;; ---------------------------------------------------------------
;; Writes: the working directory, temp, and the terminal.
;; ---------------------------------------------------------------
(deny file-write*)
(allow file-write* (subpath "$WORKDIR"))
(allow file-write* (subpath "/private/tmp"))
(allow file-write* (subpath "/private/var/folders"))
(allow file-write-data
    (literal "/dev/null")
    (literal "/dev/zero")
    (literal "/dev/stdout")
    (literal "/dev/stderr"))
(allow file-write* (regex #"^/dev/tty"))
(allow file-ioctl (regex #"^/dev/tty"))
SBPL

    for p in $EXTRA_WRITE; do
        rp=$(cd "$p" 2>/dev/null && pwd -P) || rp="$p"
        echo "(allow file-write* (subpath \"$rp\"))   ; widened via --also-write"
    done

    cat <<SBPL

;; ---------------------------------------------------------------
;; Network. THIS IS THE CONTROL THAT MATTERS.
;;
;; oMLX and nothing else. No DNS, so hostnames do not resolve;
;; no outbound TCP, so curl and git push fail. An injected agent that
;; reads a secret has no channel to send it.
;; ---------------------------------------------------------------
(deny network*)
(allow network-outbound (remote ip "localhost:$GATEWAY_PORT"))

;; Local unix sockets. Some libc facilities need these. Container sockets
;; are denied again below: last matching rule wins, and a Podman socket
;; would be a network escape. If the profile fails to compile, this is the
;; first block to try removing -- sandbox-exec will name the line number.
(allow network-outbound (remote unix-socket))
(deny network-outbound (remote unix-socket (subpath "$HOME_REAL/.local/share/containers")))
(deny network-outbound (remote unix-socket (subpath "$HOME_REAL/.docker")))
(deny network-outbound (remote unix-socket (literal "/var/run/docker.sock")))
(deny network-outbound (remote unix-socket (literal "/private/var/run/docker.sock")))
(allow network-bind (local ip "localhost:*"))
SBPL
}

# --- Known-agent presets -------------------------------------------------
# Some tools keep state outside the working directory and crash without it.
# Widening is applied automatically but ALWAYS announced: a security control
# that quietly loosens itself is worse than one you have to think about.
#
# This runs BEFORE --print-profile so that the profile you audit is byte-for-byte
# the profile that gets applied. An audit of a different artefact is not an audit.
PRESET_NOTE=""
case "${1:-}" in
    ""|-*) : ;;
    *) case "$(basename "$1")" in
    aider)
        # aider writes ~/.aider/caches (version check) and ~/.aider/analytics.json.
        # Safe to allow: it is aider's own state, and with egress blocked there
        # is nothing to be gained by writing there anyway.
        if [ -d "$HOME/.aider" ]; then
            EXTRA_WRITE="$EXTRA_WRITE $HOME/.aider"
            PRESET_NOTE="aider preset: ~/.aider writable"
        else
            echo "NOTE: ~/.aider does not exist yet. aider cannot create it from" >&2
            echo "      inside the sandbox (that is a write to \$HOME). Run once:" >&2
            echo "        mkdir -p ~/.aider/caches" >&2
        fi
        # The pypi version check cannot succeed with egress blocked and crashes
        # on the cache write. Turn it off unless the user already said something.
        case " $* " in
            *" --check-update "*|*" --no-check-update "*) : ;;
            *) set -- "$@" --no-check-update
               PRESET_NOTE="$PRESET_NOTE, --no-check-update added" ;;
        esac
        ;;
    esac ;;
esac

if [ "$PRINT_ONLY" -eq 1 ]; then
    emit_profile
    exit 0
fi

if ! command -v sandbox-exec >/dev/null 2>&1; then
    echo "ERROR: sandbox-exec not found. Running an agent unsandboxed is not" >&2
    echo "       something this script will do silently -- refusing." >&2
    echo "       Run scripts/sandbox-probe.sh to see what this machine supports." >&2
    exit 2
fi

if [ $# -eq 0 ]; then
    echo "ERROR: nothing to run. Try: scripts/sandboxed.sh aider" >&2
    exit 2
fi

PROFILE=$(mktemp -t aistack-sb) || { echo "ERROR: mktemp failed" >&2; exit 2; }
trap 'rm -f "$PROFILE"' EXIT INT TERM
emit_profile > "$PROFILE"

echo "sandbox: writes -> $WORKDIR" >&2
echo "sandbox: egress -> 127.0.0.1:$GATEWAY_PORT only" >&2
if [ -n "$EXTRA_WRITE" ]; then
    echo "sandbox: WIDENED, also writable:$EXTRA_WRITE" >&2
fi
if [ -n "$PRESET_NOTE" ]; then
    echo "sandbox: $PRESET_NOTE" >&2
fi
echo "sandbox: package installs and git push will fail in here, by design" >&2
echo >&2

exec sandbox-exec -f "$PROFILE" "$@"
