# ADR 0035 — local-main switches to OptiQ-4bit

**Date:** 2026-11-07
**Status:** accepted 2026-11-07 by the operator.
**Amends:** ADR 0030 (same 35B-A3B base; new quant recipe)

## Context

ADR 0030 put the uniform MLX-4bit 35B-A3B on `local-main`. On 2026-11-07
three alternate quants of that base were gated on this host (rule 5):
Jundot oQ4e, Unsloth UD, and OptiQ-4bit, against the live pin’s concurrency
shape (c3 × ~30K, tools, `bench/tasks`, tool-smoke).

| Quant | c3 tools | TTFT p50 / p95 | Record |
|---|---|---|---|
| lmstudio uniform-4bit (incumbent) | 30/30 | 61.4 / 89.7 s | `2026-11-07-0930-concurrency-c3` |
| Jundot oQ4e | 30/30 | 61.2 / 63.4 s | `2026-11-07-0754-concurrency-c3-jundot-oq4e` |
| Unsloth UD | 30/30 | 63.4 / 66.7 s | `2026-11-07-1427-concurrency-c3-unsloth-ud` |
| OptiQ-4bit | 30/30 | 61.9 / 62.1 s | `2026-11-07-1542-concurrency-c3-optiq` |

OptiQ had the tightest p95, passed tool-smoke, and matched syntax on the
auto-checked tasks. The operator chose it.

## Decision

`local-main` weights are `mlx-community/Qwen3.6-35B-A3B-OptiQ-4bit`
(@ `08567bc`): 128K × 3, thinking on, same sampling as before (generation
config + `scripts/omlx.sh`). Clients still call `local-main`.

## Consequences

- Previous uniform pin stays on disk under
  `lmstudio-community/Qwen3.6-35B-A3B-MLX-4bit`, unloaded.
- Unsloth and Jundot leaves (if present) stay unloaded candidates.
- Zed labels refresh via `scripts/zed-sync.sh` to the OptiQ leaf name
  (ADR 0034).
- Digests re-recorded with `scripts/pin-digests.sh`.
- Combined peak with `local-deep` not re-measured under OptiQ.
