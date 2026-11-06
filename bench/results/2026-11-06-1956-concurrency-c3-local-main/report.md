# Concurrency bench — local-main, thinking on, 128K x 3, kernels

| | |
|---|---|
| Base URL | `http://127.0.0.1:1234/v1` |
| Role | `local-main` |
| Concurrency × rounds | 3 × 10 = 30 requests |
| Target prompt tokens | 30000 (actual median 30889) |
| Client timeout | 180 s |
| Run | 2026-11-06T19:57:03 → 2026-11-06T20:11:22 (859 s wall) |
| Footprint process match | `\.omlx/` |

## Result

| Metric | Value |
|---|---|
| Valid `read_file` tool calls | 30 / 30 |
| Timeouts (client, 180 s) | 0 |
| HTTP errors | 0 |
| Other failures (bad/no tool call, stream error) | 0 |
| TTFB p50 / p95 | 0.1 s / 0.6 s |
| TTFT p50 / p95 (requests that produced a token) | 79.2 s / 88.2 s |
| Total time p50 / p95 (successful) | 83.7 s / 88.9 s |
| Peak footprint (sum of matched processes) | 31.0 GB |

Raw: `raw.tsv`, `footprint.tsv`.
