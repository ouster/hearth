# ADR 0046 — Raise main-brain context to 256K

**Date:** 2026-11-10
**Status:** accepted 2026-11-10 by the operator.
**Supersedes:** the 131072 prompt cap in ADR 0017. Slots stay 3.

## Context

`main-brain`'s weights are trained to 262,144 tokens. ADR 0017 capped the
prompt at 131,072 so three slots would fit an older ~48 GB GPU ceiling.
oMLX pages the KV cache, so the cap costs nothing until a prompt is that
long. The vendor card (fetched 2026-11-10) asks for at least 128K so
thinking is preserved, and treats 262,144 as the native window. Past that,
oMLX 0.7.4 applies static YaRN for this family; this change does not.

A large codebase thread was being trimmed at 128K. That trim is what made
agent turns repeat work.

## Decision

- `main-brain` context is **262144**, still **3 slots**.
- `deep-brain` stays **65536 × 1**. A 100k prompt on it took 9 minutes and
  evicts `main-brain` for the session.
- Clients advertise 262144. Zed compacts at **170,000**, which leaves the
  old ~21k count lag plus the 65,536 output budget inside 262,144.
- No YaRN, and no edit to the weights' `config.json`.

## Consequences

- The 30k c3 gate matched the 128k-cap run: 30/30, TTFT p50 59.8 s / p95
  60.4 s, wall 610 s (`bench/results/2026-11-10-262144-concurrency-c3-main`).
  That report's footprint is 0 because `\.omlx/` does not match `omlx-server`.
- One 200,266-token prompt, concurrency 1: valid tool call, TTFT 377.6 s,
  peak 40.0 GB (`bench/results/2026-11-10-262144-main-200k`). Under the
  56 GB ceiling. Three concurrent prompts of that length were not run.
- The row is shared with a 48 GB host (40 GB ceiling). A prompt that peaked
  at 40 GB here sits on that ceiling, and the memory guard refuses it.
- A cold 200k prefill is several minutes and serial. A thread that keeps
  its prefix should pay only for the new tail; the bench nonce disables
  that cache on purpose.
