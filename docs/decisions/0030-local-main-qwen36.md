# ADR 0030 — local-main returns to the 35B-A3B

**Date:** 2026-11-06
**Status:** accepted 2026-11-06 by the operator.
**Supersedes:** ADR 0024

## Context

ADR 0024 put the 26B-A4B back on `local-main` after a Zed loop turned out to
be context trim. The 35B-A3B weights stayed on disk.

On 2026-11-06, with native kernels, both were benched again. On `bench/tasks`
the 35B-A3B decoded faster and gave the complete long-context answer. It
wrote about 2.2× the tokens, so the three short tasks still finished sooner
on the 26B-A4B. At concurrency 3, ~30K-token prompts, both returned 30/30
valid tool calls. Time to first token was p50 60.7 s / p95 61.5 s against
79.2 s / 88.2 s. Peak footprint was 34.0 GB against 31.0 GB.

## Decision

`local-main` is the 35B-A3B again: 128K × 3, no draft. Thinking stays on.
Sampling follows its generation config: temperature 1.0, top K 20, top P
0.95, repeat penalty off. The reasoning parser is the qwen parser.

## Consequences

- The 26B-A4B weights stay on disk, unloaded.
- The resident c3 peak is 34.0 GB
  (`bench/results/2026-11-06-2012-concurrency-c3-qwen3.6`). Under the 56 GB
  guard alone.
- Loaded beside `local-deep` was not re-measured. The last combined peak was
  49.9 GB with the smaller resident (ADR 0028). This resident is 3 GB
  heavier at the same c3 method.
- Short agent turns emit more tokens than on the 26B-A4B. That is the wall
  time this swap spends.
- Reload Zed and start a new thread.
