# ADR 0032 — RAM tiers in roles.tsv

**Date:** 2026-11-07
**Status:** accepted 2026-11-07 by the operator. Amends ADR 0031 (the fixed
co-load threshold).

## Context

ADR 0031 sized the GPU ceiling from RAM but kept one role set for every host
and a fixed 56 GB threshold for loading `local-deep` beside `local-main`.
Hosts from 32 GB to 512 GB want different role sets, and whether two models
fit together is a measured fact per tier, not a constant.

## Decision

- `config/roles.tsv` gains a ninth column, `min_ram` (GB of RAM; `-` on cloud
  rows). Per role, a host uses the row with the largest `min_ram` at or below
  its RAM. `scripts/lib.sh` `hearth_resolved_roles` is the only resolver;
  every script reads through it. `HEARTH_RAM_GB` overrides detected RAM.
- The load column becomes `resident | beside | swap`. `beside` loads next to
  the resident (ADR 0028); `swap` unloads the resident first and restores it
  (ADR 0031). `HEARTH_COLOAD_MIN_GB` is removed.
- A row may say `beside` only with a bench showing the combined peak at or
  below the ceiling minus 2 GB.
- A tier gets rows only after `bench/tasks` and `scripts/concurrency-bench.sh`
  pass on that hardware (rule 5). Unbenched picks live in `docs/MODELS.md`
  under *Candidates by RAM*.
- `pins/digests.tsv` is keyed by weights path. Recording keeps the rows of
  weights this host does not serve.
- Rule 1 is unchanged: model names stay in `roles.tsv` and `MODELS.md`.

## Consequences

- Rows today: `local-main` at 48; `local-deep` `beside` at 64 and `swap` at 48.
  Resolved at 64 GB, they are the same rows as before this ADR.
- Above 64 GB a host falls back to the 64 GB rows with a larger ceiling, so
  it works before its own tier is benched.
- Below 48 GB no resident row fits: `scripts/omlx.sh up` refuses and
  preflight fails. `scripts/install-host.sh` prints the matching
  *Candidates by RAM* row from `docs/MODELS.md` and stops. That line is
  not a role. Deliberate until a tier is benched on that hardware.
- The 64 GB `beside` row still rests on ADR 0028. The combined peak with the
  ADR 0030 resident (~53 GB estimated against 56) has not been measured.
- The 48 GB rows are not benched on 48 GB hardware (ADR 0031).
