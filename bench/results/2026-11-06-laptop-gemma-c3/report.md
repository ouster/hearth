# Concurrency bench — laptop M5 Pro 48GB oMLX policy 131072 c3

| | |
|---|---|
| Base URL | `http://127.0.0.1:8000/v1` |
| Role | `gemma-4-26b-a4b-it-qat-mlx` |
| Concurrency × rounds | 3 × 10 = 30 requests |
| Target prompt tokens | 30000 (actual median 31044) |
| Client timeout | 180 s |
| Run | 2026-11-06T10:10:14 → 2026-11-06T10:21:55 (700 s wall) |
| Footprint process match | `[o]mlx` |

## Result

| Metric | Value |
|---|---|
| Valid `read_file` tool calls | 30 / 30 |
| Timeouts (client, 180 s) | 0 |
| HTTP errors | 0 |
| Other failures (bad/no tool call, stream error) | 0 |
| TTFB p50 / p95 | 0.1 s / 1.5 s |
| TTFT p50 / p95 (requests that produced a token) | 63.3 s / 71.9 s |
| Total time p50 / p95 (successful) | 63.4 s / 71.9 s |
| Peak footprint (sum of matched processes) | 22.0 GB |

Raw: `raw.tsv`, `footprint.tsv`.
