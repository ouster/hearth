#!/bin/bash
# Set the Apple GPU wired limit to RAM minus 8 GB and keep it across reboot
# (ADR 0027, 0031): 57344 MB on 64 GB, 40960 MB on 48 GB. Matches the oMLX
# memory guard in scripts/omlx.sh. Re-run asks for the admin password.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"

GB="$(hearth_gpu_ceiling_gb)" || { echo "iogpu-wired: cannot read hw.memsize" >&2; exit 2; }
MB=$(( GB * 1024 ))
LABEL="com.hearth.iogpu-wired"
DEST="/Library/LaunchDaemons/${LABEL}.plist"

if [ "$(id -u)" -ne 0 ]; then
  exec sudo /bin/bash "$0" "$@"
fi

/usr/sbin/sysctl -w "iogpu.wired_limit_mb=${MB}"

/usr/bin/python3 -I - "$DEST" "$LABEL" "$MB" <<'PY'
import plistlib, sys
path, label, mb = sys.argv[1], sys.argv[2], sys.argv[3]
doc = {
    "Label": label,
    "ProgramArguments": ["/usr/sbin/sysctl", "-w", "iogpu.wired_limit_mb=%s" % mb],
    "RunAtLoad": True,
}
with open(path, "wb") as fh:
    plistlib.dump(doc, fh)
PY
chown root:wheel "$DEST"
chmod 644 "$DEST"
launchctl bootout "system/${LABEL}" >/dev/null 2>&1 || true
launchctl bootstrap system "$DEST"
printf 'iogpu.wired_limit_mb=%s\n' "$(/usr/sbin/sysctl -n iogpu.wired_limit_mb)"
