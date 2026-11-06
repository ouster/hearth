# Concurrency bench — laptop M5 Pro 48GB oMLX policy 131072 c3

| | |
|---|---|
| Base URL | `http://127.0.0.1:8000/v1` |
| Role | `qwen3.8-27b-mlx` |
| Concurrency × rounds | 3 × 10 = 30 requests |
| Target prompt tokens | 30000 (actual median 30629) |
| Client timeout | 180 s |
| Run | 2026-11-06T10:34:04 → 2026-11-06T11:04:04 (1800 s wall) |
| Footprint process match | `[o]mlx` |

## Result

| Metric | Value |
|---|---|
| Valid `read_file` tool calls | 10 / 30 |
| Timeouts (client, 180 s) | 20 |
| HTTP errors | 0 |
| Other failures (bad/no tool call, stream error) | 0 |
| TTFB p50 / p95 | 0.1 s / 20.3 s |
| TTFT p50 / p95 (requests that produced a token) | 79.5 s / 97.7 s |
| Total time p50 / p95 (successful) | 89.2 s / 107.8 s |
| Peak footprint (sum of matched processes) | 22.0 GB |

## Failures

| Round | Slot | HTTP | TTFT | Total | Finish | Error |
|---|---|---|---|---|---|---|
| 1 | 0 | 200 | — | 180.001 | timeout | timeout after 180s |
| 1 | 2 | 200 | — | 180.001 | timeout | timeout after 180s |
| 2 | 1 | 200 | — | 180.002 | timeout | timeout after 180s |
| 2 | 2 | 200 | — | 180.002 | timeout | timeout after 180s |
| 3 | 1 | 200 | — | 180.001 | timeout | timeout after 180s |
| 3 | 2 | 200 | — | 180.001 | timeout | timeout after 180s |
| 4 | 0 | 200 | — | 180.002 | timeout | timeout after 180s |
| 4 | 2 | 200 | — | 180.001 | timeout | timeout after 180s |
| 5 | 0 | 200 | — | 180.001 | timeout | timeout after 180s |
| 5 | 2 | 200 | — | 180.002 | timeout | timeout after 180s |
| 6 | 0 | 200 | — | 180.003 | timeout | timeout after 180s |
| 6 | 2 | 200 | — | 180.001 | timeout | timeout after 180s |
| 7 | 1 | 200 | — | 180.002 | timeout | timeout after 180s |
| 7 | 2 | 200 | — | 180.002 | timeout | timeout after 180s |
| 8 | 0 | 200 | — | 180.003 | timeout | timeout after 180s |
| 8 | 2 | 200 | — | 180.002 | timeout | timeout after 180s |
| 9 | 1 | 200 | — | 180.002 | timeout | timeout after 180s |
| 9 | 2 | 200 | — | 180.002 | timeout | timeout after 180s |
| 10 | 0 | 200 | — | 180.003 | timeout | timeout after 180s |
| 10 | 2 | 200 | — | 180.003 | timeout | timeout after 180s |

Raw: `raw.tsv`, `footprint.tsv`.
