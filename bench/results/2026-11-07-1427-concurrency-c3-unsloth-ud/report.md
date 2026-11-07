# Concurrency bench — unsloth-ud-mlx-4bit

| | |
|---|---|
| Base URL | `http://127.0.0.1:1234/v1` |
| Role | `local-main` |
| Concurrency × rounds | 3 × 10 = 30 requests |
| Target prompt tokens | 30000 (actual median 30619) |
| Client timeout | 180 s |
| Run | 2026-11-07T14:27:59 → 2026-11-07T14:38:49 (651 s wall) |
| Footprint process match | `\.omlx/` |

## Result

| Metric | Value |
|---|---|
| Valid `read_file` tool calls | 30 / 30 |
| Timeouts (client, 180 s) | 0 |
| HTTP errors | 0 |
| Other failures (bad/no tool call, stream error) | 0 |
| TTFB p50 / p95 | 0.0 s / 0.1 s |
| TTFT p50 / p95 (requests that produced a token) | 63.4 s / 66.7 s |
| Total time p50 / p95 (successful) | 64.2 s / 67.8 s |
| Peak footprint (sum of matched processes) | 0.0 GB |

Raw: `raw.tsv`, `footprint.tsv`.
