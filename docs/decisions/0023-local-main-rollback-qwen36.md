# ADR 0023 — local-main rolls back to the Qwen3.6 35B-A3B

**Date:** 2026-11-01
**Status:** accepted 2026-11-01 by the operator.
**Supersedes:** ADR 0019

## Context

ADR 0019 put the 26B-A4B on the resident role. Sampling was then set to that
model's `generation_config.json` (temperature 1.0, top K 64, top P 0.95,
min P 0, repeat penalty off) because a lower temperature made its thinking
loop. Zed agent turns still looped.

The previous resident is the Qwen3.6 35B-A3B (`docs/MODELS.md`), already
benched (ADR 0017, 0019). Its weights were kept for this rollback. It is
weaker on `bench/tasks` 03, and its c3 peak is 29.7 GB against the 26B-A4B's
25.2 GB.

## Decision

`local-main` is that Qwen3.6 build again: 128K × 3, MTP draft on.
`scripts/swap-role.sh` loaded it and tool-smoke passed. No new bench. This
is a rollback of a model that had already been the resident, because the
replacement looped in Zed.

## Consequences

- The 26B-A4B weights stay on disk. Its app settings (thinking template,
  channel markers, top K 64) are per-model and do not follow the role.
- This build's template opens `<think>` unless `enable_thinking` is false.
  Its `generation_config.json` asks for temperature 1.0, top K 20, top P
  0.95. Zed's `temperature: 1.0` pin on `local-main` still matches. Zed
  cannot set Top K or Top P.
- The resident peak is the 29.7 GB c3 measurement again
  (`bench/results/2026-11-01-128k`). Still under the ~48 GB ceiling alone,
  and still not beside `local-deep`.
- Reload Zed and start a new thread. An open thread is still the looping
  model.
