# Concurrency bench — local 48GB M5 Pro

| | |
|---|---|
| Base URL | `http://127.0.0.1:1234/v1` |
| Role | `main-brain` |
| Concurrency × rounds | 3 × 10 = 30 requests |
| Target prompt tokens | 30000 (actual median 29918) |
| Client timeout | 180 s |
| Run | 2026-11-08T21:24:18 → 2026-11-08T21:32:16 (478 s wall) |
| Footprint process match | `omlx-server` |

## Result

| Metric | Value |
|---|---|
| Valid `read_file` tool calls | 30 / 30 |
| Timeouts (client, 180 s) | 0 |
| HTTP errors | 0 |
| Other failures (bad/no tool call, stream error) | 0 |
| TTFB p50 / p95 | 0.1 s / 0.2 s |
| TTFT p50 / p95 (requests that produced a token) | 43.7 s / 47.5 s |
| Total time p50 / p95 (successful) | 46.1 s / 48.9 s |
| Peak footprint (sum of matched processes) | 31.0 GB |

Raw: `raw.tsv`, `footprint.tsv`.
