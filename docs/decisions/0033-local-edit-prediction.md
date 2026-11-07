# ADR 0033 — local-edit: editor edit prediction on laptop oMLX; local-deep swaps on 64 GB

**Date:** 2026-11-07
**Status:** accepted 2026-11-07 by the operator; amended 2026-11-07 after the
host gate failed. Amends ADR 0028 and 0032 (64 GB `beside`).

## Context

Zed's default edit prediction sends the text around the cursor to Zed's
hosted Zeta service (rule 3). It is off (`docs/IDES.md`). Zed can instead
post to any `/v1/completions` endpoint with a key, which oMLX serves. The
operator wants a prediction model that is small, fast, and local on a
laptop's own oMLX; the host's agent load must not share a scheduler with it.

The chosen weights ship only as a Q8_0 GGUF. `mlx_lm.convert` takes
safetensors; `mx.load` reads GGUF. Names and revisions are in
`docs/MODELS.md`.

## Decision

- New role `local-edit`, load `edit`: greedy, 512 max tokens, 8K context,
  thinking off. Called only on `/v1/completions`. It is not a chat or agent
  model: bench, the agent model list and `zed-sync` labels skip it. Row at
  `min_ram` 48.
- `client/edit-model.sh convert` builds the weights on either machine:
  pinned GGUF checked against the Hub's sha256, dequantized, renamed to
  Qwen2, quantized to MLX 8-bit by `mlx_lm`, then a sample prediction must
  reproduce the file. The fine-tune prunes the vocabulary to 43,839 tokens
  with its own merges, so the tokenizer is rebuilt from the GGUF's vocabulary
  and merges; the base model's tokenizer at a pinned revision is only the
  template for pre-tokenizer and decoder, and the result must round-trip a
  code sample. A `HEARTH-SOURCE.json` records the provenance.
- **Laptop is primary.** `client/edit-model.sh laptop-up` links it into the
  laptop's own oMLX and pins it. Zed on that laptop points at the laptop's
  `/v1/completions`. Gate: `client/edit-model.sh bench` (p95 ≤ 500 ms, no
  errors).
- **Host does not load `local-edit`.** `scripts/omlx.sh up` leaves host slots
  at `local-main`'s 3. Digests stay in `pins/digests.tsv` so a laptop or a
  later host retry can use the same weights. Do not point host Zed or a
  laptop tunnel at host `:1234` for edit prediction.
- **Paid Zed Zeta** (`"provider": "zed"`) is an operator opt-in only when a
  paid Zed plan is active and the buffer is not sensitive (rule 3 /
  `docs/ROUTING.md`). It is cloud: cursor context leaves the machine.
  Default and the privacy check remain `"none"`. `scripts/zed-sync.sh
  --check` still reports DRIFT for `"zed"` — enabling it is deliberate, not
  a green path. Never add Zeta (or any other cloud provider) as a host Zed
  language-model entry.
- `local-deep` is `swap` on every tier. At 64 GB the three together (~55 GB
  estimated) would pass the ceiling-minus-2 margin ADR 0032 sets for
  `beside`. The 64 GB `beside` row is removed; host edit load is removed for
  scheduler reasons, not RAM.
- `scripts/zed-sync.sh --check` (run by preflight) fails when Zed's edit
  prediction provider is anything but `none` or a localhost
  `/v1/completions` serving `local-edit`.

## Consequences

- `ask-deep` evicts `local-main` on 64 GB too; Zed, aider and laptops get
  errors for the session.
- Host gate, 2026-11-07: alone p50 252 / p95 281 ms (pass). Beside
  concurrency-3: edit p95 5747 ms (fail), `local-main` TTFT p95 89.7 s
  against baseline 61.5 s (fail, >10%), peak 35.0 GB. Reports
  `bench/results/2026-11-07-0929-edit`, `2026-11-07-0930-edit`,
  `2026-11-07-0930-concurrency-c3`.
- Laptop, 2026-11-07 (M5 Pro 48 GB, own oMLX 0.7.3): conversion 1.4 GB,
  sample prediction correct. Bench: 30 requests, 0 errors, p50 350 / p95
  398 ms, expected edit in 24/30. Misses `02-add-field` every round
  (`bench/results/2026-11-07-0905-edit-laptop`).
- The converter handles qwen2 GGUFs only. Another architecture needs code.
