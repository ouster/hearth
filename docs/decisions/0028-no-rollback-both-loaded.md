# ADR 0028 — no rollback to LM Studio; both roles may be loaded

**Date:** 2026-11-04
**Status:** accepted

## Context

ADR 0026 kept `scripts/omlx-try.sh down` as the way back onto LM Studio.
ADR 0020, carried forward by ADR 0027, loaded `local-deep` only by unloading
`local-main`. Beside a busy resident the pair peaked at 49.9 GB on
2026-11-01, over the old ~48 GB GPU cap, and the resident's requests timed
out during that prefill. The cap is now 56 GB (ADR 0027).

## Decision

`scripts/omlx.sh down` stops oMLX and leaves the port empty. It does not
start LM Studio, and a failed `up` does not start it either. `ask-deep` and
`scripts/demand-load.sh <role> up` load `local-deep` beside `local-main`.
`down` on the demand role unloads that role and leaves the resident loaded.
`--evict` remains for a run that needs the machine to itself.

## Consequences

- There is no scripted return to LM Studio. The app and its weight copies
  can still be on disk.
- A long prefill on `local-deep` can still stall `local-main`. That
  measurement is not repeated here. The ceiling now has room for the
  49.9 GB peak.
- `local-deep` has not been re-benched on oMLX.
