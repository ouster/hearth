#!/bin/bash
# Send the images that are actually running to Snyk for ongoing monitoring.
#
#   scripts/snyk-monitor.sh            # Open WebUI and SearXNG
#   scripts/snyk-monitor.sh webui      # one of them
#
# Hearth has no dependency manifests, so the third-party code worth watching
# is these containers. Both use moving tags (:main, :latest), so the image the
# container runs is exported by ID and snapshotted, not the tag: Snyk then
# re-tests that snapshot daily and emails new vulnerabilities. Re-run after an
# image update — scripts/webui.sh and searxng.sh do, after `up`.
#
# Only the image's package list goes to Snyk (projects hearth/<kind>), not
# this repo's code. Needs the snyk CLI, signed in with `snyk auth`.
#
# Exit 0 monitored, 1 a monitor failed, 2 could not run.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "${ROOT}/scripts/lib.sh"

KINDS="${1:-webui searxng}"
command -v snyk >/dev/null 2>&1 || { echo "could not run: snyk CLI not installed (brew tap snyk/tap && brew install snyk-cli)"; exit 2; }
command -v podman >/dev/null 2>&1 || { echo "could not run: podman not installed"; exit 2; }
snyk whoami --experimental >/dev/null 2>&1 || { echo "could not run: snyk not signed in (snyk auth)"; exit 2; }
podman info >/dev/null 2>&1 || { echo "could not run: podman VM not running (podman machine start)"; exit 2; }

TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
rc=0; ran=0
for kind in $KINDS; do
  c="$(ai_container "$kind")"
  if ! podman container exists "$c" 2>/dev/null; then
    echo "skip   ${kind}: container ${c} not created (scripts/${kind}.sh up)"; continue
  fi
  ref=$(podman inspect -f '{{.ImageName}}' "$c")
  id=$(podman inspect -f '{{.Image}}' "$c")
  archive="${TMPD}/${kind}.tar"
  if ! podman image save --format oci-archive -o "$archive" "$id" >/dev/null 2>&1; then
    echo "FAIL   ${kind}: could not export image ${id:0:12}"; rc=1; continue
  fi
  out=$(snyk container monitor "oci-archive:${archive}" --project-name="hearth/${kind}" 2>&1); src=$?
  rm -f "$archive"; ran=$((ran + 1))
  if [ "$src" -eq 0 ]; then
    url=$(printf '%s\n' "$out" | grep -oE 'https://app\.snyk\.io[^ ]*' | tail -1)
    echo "ok     ${kind}: ${ref} (${id:0:12}) monitored as hearth/${kind} ${url}"
  else
    echo "FAIL   ${kind}: snyk container monitor exited ${src}: $(printf '%s' "$out" | tail -2 | tr '\n' ' ')"; rc=1
  fi
done
[ "$ran" -eq 0 ] && [ "$rc" -eq 0 ] && exit 2
exit "$rc"
