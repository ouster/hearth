# ADR 0017 — Raise local-big context to 128K

**Date:** 2026-10-31
**Status:** accepted 2026-10-31 by the operator (reload the same day).

## Context

ADR 0010 and migration D2 loaded `local-big` at 64K × 3. Phase 1 peak was
29.7 GB (`bench/results/2026-10-31-phase1`), about 18 GB under the ~48 GB GPU
ceiling. The vendor card for this model (fetched 2026-10-31) states a native
window of 262,144 and asks for at least 128K so thinking is preserved. 64K
was the main limiter on agent turns.

`lms load --estimate-only -c 131072 --parallel 3` reported 26.64 GiB at low
confidence and did not itemise a 3-slot cache. That number is below the
measured 64K footprint, so it was not used to drop slots. An older LM Studio
(0.4.20) ignored `-c` on this model family and jumped to 262,144
(lmstudio-bug-tracker#2250, 2026-08-08). This host's 0.4.28 load honored
65536; the reload has to show 131072.

## Decision

`local-big` context is **131072**, still **3 slots**. If the measured
footprint after reload leaves less than about 4 GB under the ~48 GB ceiling,
drop to 2 slots and reload. If `lms ps` shows 262144, unload and go back to
65536.

256K × 3 does not fit (the same estimate at that size is already over the
ceiling).

## Consequences

- `scripts/zed-sync.sh` writes `max_tokens` from `roles.tsv`, so Zed follows.
- Prefill stays serial. A larger window does not add concurrency; a 28K
  prefill is still one at a time (~20 s, three finishing together near 61 s
  on the phase 1 run).
- Candidate benches in `scripts/bench.sh` still load at 64K. That is the
  candidate path, not the live role.
**Measured 2026-10-31, right after reload:** `lms ps` shows contextLength 131072
and parallel 3 (not the 262144 auto-fit). Sum of `footprint(1)` on the same
process match as the concurrency bench: **20.7 GB** idle. That is the weights
resident, not a 3-way prefill peak — the 64K c3 peak was 29.7 GB, and this
reload did not re-run that bench. 20.7 GB is ~27 GB under the ceiling, so
slots stay at 3.
