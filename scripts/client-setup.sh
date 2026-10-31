#!/bin/bash
# Print (or install) the setup for another machine on the LAN.
#
# PENDING PHASE 4 (docs/MIGRATION-LMSTUDIO.md). The previous version set
# laptops up against the removed LiteLLM gateway (:4000, virtual keys) and is
# in git history. Phase 4 rewrites this for LM Studio on <host>:1234 with one
# token per machine (laptop-<name>), stored in ~/.hearth-key on the laptop.
#
# Exit 2: could not run.

echo "client-setup.sh is pending phase 4 — the gateway it configured is gone." >&2
echo "See docs/MIGRATION-LMSTUDIO.md, phase 4." >&2
exit 2
