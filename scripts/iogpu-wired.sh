#!/bin/bash
# Set the Apple GPU wired limit to 56 GB and keep it across reboot (ADR 0027).
# 64 GB machine, 8 GB left for macOS. Re-run asks for the admin password.
set -euo pipefail

MB=57344
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
