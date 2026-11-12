# Qwen3-Coder-Next-4bit — oMLX Performance + Intelligence

Date: 2026-11-12. Host M4 Max 64 GB, oMLX v0.7.4.dev1. Role:
`coding-brain` (`mlx-community/Qwen3-Coder-Next-4bit`).

## Performance (app bench, Code Mixed)

Uploaded from the oMLX app earlier the same day. Thinking on,
`max_context_window` 98304, `reasoning_parser` qwen_3_5.

| Context | PP tok/s | TG tok/s | TTFT | Peak mem (MLX) | Link |
|---|---|---|---|---|---|
| 64k | 788.3 | 59.1 | 83.1 s | 45.5 GB | https://omlx.ai/benchmarks/performance/9dz1w6ja |
| 195k | 372.4 | 31.7 | 537.1 s | 49.2 GB | https://omlx.ai/benchmarks/performance/f8180al2 |

Footprint peaks (app): 50.5 GB at 64k / same session for 195k. GPU ~99%.

## Intelligence (admin accuracy suite)

Queued via `/admin/api/bench/accuracy/queue/add` against leaf
`Qwen3-Coder-Next-4bit`. Sample 100 each, batch 1, thinking on,
`sampling_profile=deterministic`. Finished 2026-11-12T21:03:12.

| Benchmark | Score | n | Wall | Upload |
|---|---|---|---|---|
| HumanEval | 92% | 92/100 | 211 s | https://omlx.ai/benchmarks/intelligence/u05uucwd |
| MBPP | 82% | 82/100 | 228 s | https://omlx.ai/benchmarks/intelligence/gtcvpozv |
| LiveCodeBench | 73% | 73/100 | 3000 s | https://omlx.ai/benchmarks/intelligence/jsd5ldmv |
| GSM8K | 94% | 94/100 | 422 s | https://omlx.ai/benchmarks/intelligence/5ml1ff2q |

Machine-readable copy: `results.json` in this directory.

Hearth role decision still rests on `bench/tasks` + concurrency
(`2026-11-12-1903-coder-next-4bit`, `2026-11-12-1923-coder-next-quality`)
and ADR 0047, not this leaderboard.
