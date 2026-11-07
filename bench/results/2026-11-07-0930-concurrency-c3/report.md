# Concurrency bench

| | |
|---|---|
| Base URL | `http://127.0.0.1:1234/v1` |
| Role | `local-main` |
| Concurrency × rounds | 3 × 10 = 30 requests |
| Target prompt tokens | 30000 (actual median 30596) |
| Client timeout | 180 s |
| Run | 2026-11-07T09:30:10 → 2026-11-07T09:43:03 (773 s wall) |
| Footprint process match | `\.omlx/` |

## Result

| Metric | Value |
|---|---|
| Valid `read_file` tool calls | 30 / 30 |
| Timeouts (client, 180 s) | 0 |
| HTTP errors | 0 |
| Other failures (bad/no tool call, stream error) | 0 |
| TTFB p50 / p95 | 0.1 s / 0.2 s |
| TTFT p50 / p95 (requests that produced a token) | 61.4 s / 89.7 s |
| Total time p50 / p95 (successful) | 62.2 s / 92.7 s |
| Peak footprint (sum of matched processes) | 35.0 GB |

Raw: `raw.tsv`, `footprint.tsv`.
