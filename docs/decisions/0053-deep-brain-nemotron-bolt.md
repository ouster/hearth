# ADR 0053 — deep-brain on 64 GB is Nemotron Bolt

**Date:** 2026-11-21
**Status:** accepted 2026-11-21 by the operator.
**Amends:** ADR 0033 / 0047 (`deep-brain` swap behaviour unchanged;
weights and context on the 64 GB tier change).

## Context

`deep-brain` was Qwen3.8-27B MLX 4-bit (16 GB, 64K × 1) on every tier.
On 2026-11-21, `nativ-community/NVIDIA-Nemotron-3.5-Bolt-74B-A9B-4bit`
(~40 GB disk, peak ~51 GB at 96K) was benched against that incumbent for
the deep role (`bench/results/2026-11-21-1600-nemotron-bolt/`): tool-smoke
PASS, c1 TTFT p50 60.0 s vs live deep ~123 s, `bench/tasks` 03/04 strong,
~50 tok/s on short prompts. It is slower than `coding-brain` (Coder-Next
p50 27 s) and is not a coding-brain candidate. Peak ~51 GB does not fit
the 40 GB ceiling on 48 GB hosts.

## Decision

- On **64 GB** hosts, `deep-brain` is Bolt: model key
  `nemotron-bolt-74b-a9b-4bit`, weights
  `nativ-community/NVIDIA-Nemotron-3.5-Bolt-74B-A9B-4bit`, **98,304 × 1**,
  **swap**, `min_ram` 64.
- On **48 GB** hosts, `deep-brain` stays Qwen3.8-27B (64K × 1, swap,
  `min_ram` 48).
- Still never beside `coding-brain`. Load path unchanged: `ask-deep` /
  `demand-load.sh deep-brain`.
- Hearth clients keep calling the role name; vision/audio in the weights
  are not a new Hearth API surface in this ADR.

## Consequences

- 64 GB `ask-deep` is ~2× faster to first token than Qwen3.8 on the same
  gate, at ~51 GB peak — fits under 56 GB with little headroom.
- 48 GB hosts are unchanged. A 64 GB host that deletes Bolt weights fails
  digests / load until restored.
- OpenMDW-1.1 licence on Bolt; operators using it commercially must read it.
- Re-record `pins/digests.tsv` and run `scripts/zed-sync.sh` on the host.
