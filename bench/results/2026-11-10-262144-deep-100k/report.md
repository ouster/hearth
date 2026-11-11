# Concurrency bench — deep-brain 262144 cap, one 100k prompt

| | |
|---|---|
| Base URL | `http://127.0.0.1:1234/v1` |
| Role | `deep-brain` |
| Concurrency × rounds | 1 × 1 = 1 requests |
| Target prompt tokens | 100000 (actual median 101696) |
| Client timeout | 900 s |
| Run | 2026-11-10T10:11:42 → 2026-11-10T10:20:49 (547 s wall) |
| Footprint process match | `omlx-server` |

## Result

| Metric | Value |
|---|---|
| Valid `read_file` tool calls | 1 / 1 |
| Timeouts (client, 900 s) | 0 |
| HTTP errors | 0 |
| Other failures (bad/no tool call, stream error) | 0 |
| TTFB p50 / p95 | 0.1 s / 0.1 s |
| TTFT p50 / p95 (requests that produced a token) | 544.7 s / 544.7 s |
| Total time p50 / p95 (successful) | 547.4 s / 547.4 s |
| Peak footprint (sum of matched processes) | 36.0 GB |

Raw: `raw.tsv`, `footprint.tsv`.
