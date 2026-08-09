#!/bin/bash
# Renamed — kept as a thin redirect for muscle memory.
echo "hearth: scripts/client-setup.sh → scripts/provision-client.sh" >&2
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/provision-client.sh" "$@"
