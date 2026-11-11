# Concurrency bench — main-brain 262144 cap, one 200k prompt

| | |
|---|---|
| Base URL | `http://127.0.0.1:1234/v1` |
| Role | `main-brain` |
| Concurrency × rounds | 1 × 1 = 1 requests |
| Target prompt tokens | 200000 (actual median 200266) |
| Client timeout | 900 s |
| Run | 2026-11-10T09:58:25 → 2026-11-10T10:04:43 (378 s wall) |
| Footprint process match | `omlx-server` |

## Result

| Metric | Value |
|---|---|
| Valid `read_file` tool calls | 1 / 1 |
| Timeouts (client, 900 s) | 0 |
| HTTP errors | 0 |
| Other failures (bad/no tool call, stream error) | 0 |
| TTFB p50 / p95 | 0.2 s / 0.2 s |
| TTFT p50 / p95 (requests that produced a token) | 377.6 s / 377.6 s |
| Total time p50 / p95 (successful) | 378.1 s / 378.1 s |
| Peak footprint (sum of matched processes) | 40.0 GB |

Raw: `raw.tsv`, `footprint.tsv`.
