# Concurrency bench — ripple-65b-mlx-4bit

| | |
|---|---|
| Base URL | `http://127.0.0.1:1234/v1` |
| Role | `Ripple-65B-Preview-MLX-4bit` |
| Concurrency × rounds | 1 × 10 = 10 requests |
| Target prompt tokens | 30000 (actual median 28171) |
| Client timeout | 600 s |
| Run | 2026-11-21T14:50:25 → 2026-11-21T15:45:13 (3289 s wall) |
| Footprint process match | `\.omlx/` |

## Result

| Metric | Value |
|---|---|
| Valid `read_file` tool calls | 10 / 10 |
| Timeouts (client, 600 s) | 0 |
| HTTP errors | 0 |
| Other failures (bad/no tool call, stream error) | 0 |
| TTFB p50 / p95 | 0.0 s / 0.1 s |
| TTFT p50 / p95 (requests that produced a token) | 322.6 s / 330.3 s |
| Total time p50 / p95 (successful) | 329.5 s / 334.7 s |
| Peak footprint (sum of matched processes) | 0.0 GB |

Raw: `raw.tsv`, `footprint.tsv`.
