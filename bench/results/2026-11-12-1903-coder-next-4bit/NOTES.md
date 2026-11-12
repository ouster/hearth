# Qwen3-Coder-Next-4bit — main challenger

Date: 2026-11-12. Not a role change. Weights:
`mlx-community/Qwen3-Coder-Next-4bit` (~42 GB / 80B-A3B).

Loaded after unpinning OptiQ. Guard refused 131072 projected (67 GB over
the 56 GB ceiling). First load at 8192, then raised live to 98304 for the
~30K concurrency run.

| | Live main OptiQ (2026-11-10 c3 × 10) | Coder-Next 4bit (this run, c1 × 10) |
|---|---|---|
| Tool-smoke | PASS | PASS |
| Valid tools | 30 / 30 | 10 / 10 |
| TTFT p50 / p95 | 59.8 / 60.4 s | 27.2 / 27.3 s |
| Peak footprint | (matcher miss then; ~34–40 GB class) | 52.0 GB |
| Slots | 3 × 256K | 1 (tight under 56 GB) |
| deep beside | yes (swap) | no |

Much faster on a single ~30K tool turn. Too heavy for the current 3-slot
resident set. Quality on `bench/tasks` is in
`bench/results/2026-11-12-1923-coder-next-quality` (03 catches float money;
04 uses the docs). Still one slot. Do not point `roles.tsv` at it until a
load story fits 3 slots or an ADR accepts single-slot.
