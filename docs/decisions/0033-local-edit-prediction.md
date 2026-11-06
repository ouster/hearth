# ADR 0033 — local-edit: editor edit prediction on oMLX; local-deep swaps on 64 GB

**Date:** 2026-11-07
**Status:** accepted 2026-11-07 by the operator. Not benched yet (rule 5):
the role has no incumbent, so the gate is the latency bench below. Amends
ADR 0028 and 0032 (64 GB `beside`).

## Context

Zed's default edit prediction sends the text around the cursor to Zed's
service (rule 3). It is off (`docs/IDES.md`). Zed can instead post to any
`/v1/completions` endpoint with a key, which oMLX serves. The operator wants
a prediction model that is small, fast, and good, on the host and on a
laptop's own oMLX.

The chosen weights ship only as a Q8_0 GGUF. `mlx_lm.convert` takes
safetensors; `mx.load` reads GGUF. Names and revisions are in
`docs/MODELS.md`.

## Decision

- New role `local-edit`, load `edit`: kept loaded and pinned like a resident,
  greedy, 512 max tokens, 8K context, thinking off. Called only on
  `/v1/completions`. It is not a chat or agent model: bench, the agent model
  list and `zed-sync` labels skip it. Row at `min_ram` 48.
- `client/edit-model.sh convert` builds the weights on either machine:
  pinned GGUF checked against the Hub's sha256, dequantized, renamed to
  Qwen2, quantized to MLX 8-bit by `mlx_lm`, then a sample prediction must
  reproduce the file. The fine-tune prunes the vocabulary to 43,839 tokens
  with its own merges, so the tokenizer is rebuilt from the GGUF's vocabulary
  and merges; the base model's tokenizer at a pinned revision is only the
  template for pre-tokenizer and decoder, and the result must round-trip a
  code sample. A
  `HEARTH-SOURCE.json` records the provenance.
- Host: `scripts/omlx.sh up` links, configures and loads it. The scheduler
  limit becomes `local-main` slots + `local-edit` slots (3 + 2).
- Laptop: `client/edit-model.sh laptop-up` links it into the laptop's own
  oMLX and pins it. Zed on a laptop may use either: the host through the
  tunnel with the laptop's key, or its own oMLX.
- `local-deep` is `swap` on every tier. At 64 GB the three together (~55 GB
  estimated) would pass the ceiling-minus-2 margin ADR 0032 sets for
  `beside`. The 64 GB `beside` row is removed.
- `scripts/zed-sync.sh --check` (run by preflight) fails when Zed's edit
  prediction provider is anything but `none` or a localhost
  `/v1/completions` serving `local-edit`.

## Consequences

- `ask-deep` evicts `local-main` on 64 GB too; Zed, aider and laptops get
  errors for the session. `local-edit` stays loaded through it.
- Gate before turning Zed's provider on: `scripts/edit-bench.sh` p95 ≤ 500 ms
  with no errors, and `local-main` TTFT within 10% of its last c3 baseline
  while `scripts/edit-bench.sh --duration` runs beside
  `scripts/concurrency-bench.sh`. Same on a laptop with
  `client/edit-model.sh bench`.
- The summed scheduler limit is a cap, not a reservation. Up to five
  requests may be `local-main` at once, beyond the c3 footprint (34.0 GB)
  that was measured. The concurrency run above must report the peak.
- The converter handles qwen2 GGUFs only. Another architecture needs code.
- First run, 2026-11-07, laptop (M5 Pro 48 GB, its own oMLX 0.7.3):
  conversion 1.4 GB, sample prediction correct. `client/edit-model.sh bench`:
  30 requests, 0 errors, p50 350 ms / p95 398 ms, expected edit in 24/30.
  It misses `02-add-field` every round: it adds an unrelated field instead of
  using the new one (`bench/results/2026-11-07-0905-edit-laptop`). The host
  gate (alone and beside `concurrency-bench.sh`) has not run.
