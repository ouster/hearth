# ADR 0031 — GPU ceiling sized from RAM; local-deep swaps below 64 GB

**Date:** 2026-11-07
**Status:** accepted 2026-11-07 by the operator. Amends ADR 0027 (the 56 GB
figure) and ADR 0028 (both roles loaded).

## Context

ADR 0027 hardcoded a 56 GB wired limit and oMLX guard for the 64 GB host.
A 48 GB M5 Pro should be able to host too. Its macOS GPU cap is ~36 GB by
default. `local-main` (ADR 0030) peaks at 34.0 GB at 128K × 3 on the host.
With `local-deep` beside it the last measured peak was 49.9 GB, with the
smaller resident (ADR 0028). That cannot fit in 48 GB at all.

## Decision

- Ceiling = installed RAM minus 8 GB, read from `hw.memsize`. It is both
  `iogpu.wired_limit_mb` (`scripts/iogpu-wired.sh`) and the oMLX memory guard
  (`scripts/omlx.sh`): 56 GB on 64 GB, 40 GB on 48 GB.
- oMLX hot cache: 8 GB at 64 GB RAM and above, 4 GB below. SSD cache unchanged.
- `local-deep` loads beside `local-main` only when the ceiling is at least
  56 GB. Below that, `scripts/demand-load.sh local-deep up` evicts the
  resident, as ADR 0027 did, and `down` loads it back.
- `config/roles.tsv` stays shared: Qwen3.6 35B-A3B at 128K × 3 on both sizes.

## Consequences

- On a 48 GB host, `local-main` is down for the whole of an `ask-deep`
  session. Zed, aider and laptops get errors until it ends. That is the
  intended loud failure.
- 34.0 GB against a 40 GB guard leaves ~6 GB of headroom. It was measured on
  the 64 GB host, not on 48 GB. The laptop benches on 2026-11-06 matched
  processes by `[o]mlx` and are not comparable with the host's `\.omlx/`.
  Until a c3 run on 48 GB with the host's matcher passes (30/30, peak ≤ 36 GB),
  48 GB hosting is not benched.
- If that run exceeds 36 GB, the fallback is 128K × 2 or 64K × 3 on 48 GB.
  That needs a per-host override of `ctx`/`slots`, which does not exist yet.
- The combined 64 GB peak with the current resident is still unmeasured
  (~53 GB estimated). If it exceeds ~54 GB, raise `HEARTH_COLOAD_MIN_GB` in
  `scripts/lib.sh` and the 64 GB host swaps too.
- Without `scripts/iogpu-wired.sh` a 48 GB Mac stays at ~36 GB. Preflight
  warns when the wired limit or the saved guard differs from RAM minus 8.
