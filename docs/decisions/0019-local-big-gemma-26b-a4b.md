# ADR 0019 — local-big moves to the Gemma 4 26B-A4B QAT build

**Date:** 2026-11-01
**Status:** accepted 2026-11-01 by the operator.

## Context

`local-big` ran the Qwen3.6 35B-A3B MLX build at 128K × 3 (ADR 0017). Two
candidates were benched against it on 2026-11-01 (`docs/MODELS.md` names
them):

| | Incumbent | Dense 27B | 26B-A4B, thinking on |
|---|---|---|---|
| `bench/tasks` 03 (currency bug) | weak: wrong claims, fix returns float | best | good |
| `bench/tasks` 04 (long context) | correct | correct | correct |
| Wall time per task | 42–73 s | 305–1,578 s | 12–64 s |
| Concurrency, 40 tool calls | 40/40 | not run | 40/40 |
| c3 total p50 / p95 | 63.5 / 65.5 s | — | 73.0 / 75.2 s |
| c3 peak footprint | 29.7 GB | — | 25.2 GB |

Results: `bench/results/2026-11-01-128k`, `2026-11-01-1140`, `2026-11-01-1307`,
`2026-11-01-gemma-concurrency`. Four tasks is a small sample.

## Decision

`local-big` is the 26B-A4B QAT build at 128K × 3, no MTP draft. Its thinking
is turned on by LM Studio per-model settings that are not in the repo
(template line and reasoning parsing, recorded in `docs/MODELS.md`).
`scripts/healthcheck.sh` fails if thinking is off or unparsed.

## Consequences

- Prompt reading is ~15% slower: about 3 s more per 30K-token agent turn.
- 3–4.5 GB more headroom under the ~48 GB ceiling.
- A LM Studio reinstall or settings reset silently loses thinking until the
  healthcheck catches it. The settings must be re-applied by hand.
- The incumbent's weights stay on disk; rollback is one `swap-role.sh`
  command (`docs/MODELS.md`, Retired).
- `swap-role.sh` now resets `draft` to `-` when the model changes; an MTP
  drafter belongs to its model.
