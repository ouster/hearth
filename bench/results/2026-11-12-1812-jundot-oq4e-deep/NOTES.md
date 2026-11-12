# Jundot Qwen3.8-27B-oQ4e-mtp — deep challenger

Date: 2026-11-12. Not a role change. Compared to live
`lmstudio-community/Qwen3.8-27B-MLX-4bit` (`deep-brain`).

| | Live deep (2026-11-10 c1 × 3) | Jundot oQ4e-mtp (this run, c1 × 10) |
|---|---|---|
| Tool-smoke | (prior pass as deep-brain) | PASS |
| Valid tools | 3 / 3 | 10 / 10 |
| TTFT p50 / p95 | 123.4 / 123.7 s | 129.6 / 136.7 s |
| Peak footprint | 30.0 GB | 38.0 GB |
| Weights | 15 GB uniform 4-bit | 16 GB oQ4e + MTP |

Slightly slower and fatter than the live pin on the same ~30K prompt.
MTP did not help this prefill-heavy tool gate. Keep live deep until a
quality win on `bench/tasks` says otherwise.
