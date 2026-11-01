# Concurrency bench — 128K re-baseline, LM Studio app, 3 slots x 128K, c3

| | |
|---|---|
| Base URL | `http://127.0.0.1:1234/v1` |
| Role | `local-big` |
| Concurrency × rounds | 3 × 10 = 30 requests |
| Target prompt tokens | 30000 (actual median 29868) |
| Client timeout | 180 s |
| Run | 2026-11-01T10:42:48 → 2026-11-01T10:53:27 (639 s wall) |
| Footprint process match | `(\.lmstudio/|LM Studio)` |

## Result

| Metric | Value |
|---|---|
| Valid `read_file` tool calls | 30 / 30 |
| Timeouts (client, 180 s) | 0 |
| HTTP errors | 0 |
| Other failures (bad/no tool call, stream error) | 0 |
| TTFB p50 / p95 | 45.6 s / 62.2 s |
| TTFT p50 / p95 (requests that produced a token) | 45.6 s / 62.2 s |
| Total time p50 / p95 (successful) | 63.5 s / 65.5 s |
| Peak footprint (sum of matched processes) | 29.7 GB |

Raw: `raw.tsv`, `footprint.tsv`.
