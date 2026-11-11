# Concurrency bench — main-brain 262144 x 3

| | |
|---|---|
| Base URL | `http://127.0.0.1:1234/v1` |
| Role | `main-brain` |
| Concurrency × rounds | 3 × 10 = 30 requests |
| Target prompt tokens | 30000 (actual median 30015) |
| Client timeout | 180 s |
| Run | 2026-11-10T09:47:49 → 2026-11-10T09:57:59 (610 s wall) |
| Footprint process match | `\.omlx/` |

## Result

| Metric | Value |
|---|---|
| Valid `read_file` tool calls | 30 / 30 |
| Timeouts (client, 180 s) | 0 |
| HTTP errors | 0 |
| Other failures (bad/no tool call, stream error) | 0 |
| TTFB p50 / p95 | 0.0 s / 0.1 s |
| TTFT p50 / p95 (requests that produced a token) | 59.8 s / 60.4 s |
| Total time p50 / p95 (successful) | 60.7 s / 61.3 s |
| Peak footprint (sum of matched processes) | 0.0 GB |

Raw: `raw.tsv`, `footprint.tsv`.
