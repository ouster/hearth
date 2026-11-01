# ADR 0020 — local-deep: a slower, more careful model, swapped in on demand

**Date:** 2026-11-01
**Status:** accepted 2026-11-01 by the operator. The resident role in the
measurement below was renamed `local-main` the same day (ADR 0021).
Consequences use that name.

## Context

The dense 27B benched on 2026-11-01 gave the best `bench/tasks` 03 answer
but runs ~26 tok/s and uses 2.5–5.5× the tokens of `local-big` (ADR 0019):
10–24× the wall time. Too slow for agent loops; useful for hard one-off
questions. The operator asked for it as a second role, on demand, also
reachable from laptops and the host's Zed.

Measured 2026-11-01 (footprint includes the app):

| State | Footprint |
|---|---|
| `local-big` idle | ~16.8 GB |
| `local-big` + `local-deep` (64K × 1), both idle | 33.3 GB |
| `local-deep` alone (`local-big` unloaded) | 17.3 GB |
| `local-deep` reading a ~30K-token prompt while `local-big` serves 3 agents × ~30K | **49.9 GB peak**, over the ~48 GB ceiling; swap rose to ~5 GB |

In that last run `local-deep` took 193 s to its first token, and **all three
`local-big` requests that overlapped it timed out at 180 s** (12/15 valid
overall; later rounds were normal). A dense model's long prefill starves the
resident agent model, the same symptom as the stalls in ADR 0015. Swapping
`local-deep` in or out takes ~13 s.

## Decision

- `config/roles.tsv` gains a `load` column: `resident` (kept loaded by
  `scripts/lms-load.sh`) or `demand`. `local-deep` is `demand`, 64K × 1.
- `local-deep` is only ever loaded **instead of** `local-big`:
  `scripts/demand-load.sh local-deep up --evict` unloads the resident roles,
  loads it, and confirms the load (with JIT off a request for an unloaded
  role is answered by whatever is loaded, without saying so); `… down`
  unloads it and reloads `roles.tsv`. Without `--evict` its memory guard
  refuses beside `local-big`.
- `ask-deep` on the host does the swap for one aider session.
- Laptops (`ask-deep` in the clients) and the host's Zed (a picker entry
  labelled "load first") can use it only while the host has swapped it in;
  the laptop client checks `/v1/models` and refuses otherwise.
- Healthcheck, bench and `swap-role.sh` never call a demand role.

## Consequences

- While `local-deep` is in, there is no `local-main`: Zed, aider, Open WebUI
  and laptops asking for `local-main` are answered by `local-deep`, slowly.
- Ending an `ask-deep` session that loaded the role restores `local-main`,
  including when the session is interrupted. A later `ask-deep` that finds
  the role already loaded leaves that swap in place and says so. A manual
  `up --evict` must be followed by `down`, or by `scripts/lms-load.sh`.
- At rest there is still one resident model (D1 holds).
- `local-deep`'s weights are pinned like any role; its thinking is on by the
  model's own template, with no app setting.
