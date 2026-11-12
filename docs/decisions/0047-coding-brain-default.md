# ADR 0047 — Default resident is coding-brain; main-brain is a 3-slot swap

**Date:** 2026-11-12
**Status:** accepted 2026-11-12 by the operator.
**Amends:** ADR 0020, 0028, 0031, 0033 (load exclusivity), 0032 (tiers), 0035 (OptiQ stays `main-brain`), 0046 (256K on `main-brain` only).

## Context

`main-brain` (OptiQ Qwen3.6 35B-A3B) holds 3 × 256K under the 56 GB ceiling and can swap with `deep-brain`. `mlx-community/Qwen3-Coder-Next-4bit` (~42 GB) is faster on ~30K agent turns (TTFT p50 27.2 s vs 59.8 s) and passed `bench/tasks` quality, but peaks at 52 GB with one slot — no room for concurrent slots or `deep-brain` beside it.

Slot counts change over time; they must not be baked into role ids.

## Decision

- Add role **`coding-brain`**: Coder-Next 4-bit, ctx 98304, **1 slot**, **`resident` on min_ram 64**. Boot and clients default to it on 64 GB hosts.
- On 64 GB, **`main-brain` is `swap`** (same OptiQ weights, 262144 × 3). `scripts/demand-load.sh main-brain up` unloads `coding-brain` (and deep if up), loads `main-brain`, and sets live concurrent requests to 3. `down` restores `coding-brain` and 1 slot.
- **`coding-brain` never shares RAM** with `main-brain` or `deep-brain`. Live sets: coder alone, or main-brain (± deep via swap).
- `ask-deep` records the prior agent and restores it on `down` (not always the roles.tsv resident).
- 48 GB hosts keep a **`main-brain` resident min_ram 48** row and have no `coding-brain` row (Coder-Next does not fit the 40 GB ceiling).
- Clients learn slots from Zed `display_name` / docs (`256K × 3`, `98K × 1`), not from the role name.

## Consequences

- Healthcheck and login boot exercise `coding-brain` on 64 GB. Thinking probes stay on `main-brain` when that role is the one under test.
- Editors list both; picking `main-brain` or `deep-brain` without demand-load can get the wrong resident answering — documented in `docs/IDES.md`.
- Digests pin Coder-Next. Benches: `2026-11-12-1903-coder-next-4bit`, `2026-11-12-1923-coder-next-quality`.
