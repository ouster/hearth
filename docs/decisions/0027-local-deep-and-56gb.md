# ADR 0027 — local-deep swaps inside oMLX; GPU ceiling is 56 GB

**Date:** 2026-11-04
**Status:** accepted

## Context

ADR 0026 left `local-deep` on LM Studio, so `ask-deep` refused while oMLX held
`:1234`. The GPU wired limit was unset. Metal then capped the working set at
51.8 GB, and the oMLX guard was 48 GB. oMLX's own suggestion, 62259 MB, would
leave about 3 GB for macOS on this 64 GB machine.

ADR 0020 still stands: loading `local-deep` beside a busy `local-main` peaked
at 49.9 GB and the resident requests timed out. A higher cap does not remove
that prefill starvation.

## Decision

Copy the `local-deep` weights to `~/.hearth/models`. `ask-deep` unloads
`local-main`, loads `local-deep`, and restores `local-main` on the way out.
The two are not loaded together. Set `iogpu.wired_limit_mb` to 57344 (56 GB,
RAM minus 8) and the oMLX memory guard to 56 GB. `scripts/iogpu-wired.sh`
installs a LaunchDaemon so the wired limit survives reboot.

## Consequences

- `ask-deep` no longer needs `scripts/omlx-try.sh down`.
- Uninstalling LM Studio no longer deletes the `local-deep` weights.
- `local-deep` has not been re-benched on oMLX. The swap is the same policy
  as ADR 0020, not a new quality claim.
- Without the LaunchDaemon, a reboot returns the GPU cap to the macOS default.
