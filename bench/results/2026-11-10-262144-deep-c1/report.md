# Concurrency bench — deep-brain 262144 x 1

| | |
|---|---|
| Base URL | `http://127.0.0.1:1234/v1` |
| Role | `deep-brain` |
| Concurrency × rounds | 1 × 3 = 3 requests |
| Target prompt tokens | 30000 (actual median 30052) |
| Client timeout | 600 s |
| Run | 2026-11-10T10:05:20 → 2026-11-10T10:11:36 (377 s wall) |
| Footprint process match | `omlx-server` |

## Result

| Metric | Value |
|---|---|
| Valid `read_file` tool calls | 3 / 3 |
| Timeouts (client, 600 s) | 0 |
| HTTP errors | 0 |
| Other failures (bad/no tool call, stream error) | 0 |
| TTFB p50 / p95 | 0.0 s / 0.1 s |
| TTFT p50 / p95 (requests that produced a token) | 123.4 s / 123.7 s |
| Total time p50 / p95 (successful) | 125.5 s / 125.8 s |
| Peak footprint (sum of matched processes) | 30.0 GB |

Raw: `raw.tsv`, `footprint.tsv`.
