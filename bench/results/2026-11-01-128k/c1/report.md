# Concurrency bench — 128K re-baseline, LM Studio app, 3 slots x 128K, c1

| | |
|---|---|
| Base URL | `http://127.0.0.1:1234/v1` |
| Role | `local-big` |
| Concurrency × rounds | 1 × 10 = 10 requests |
| Target prompt tokens | 30000 (actual median 29869) |
| Client timeout | 180 s |
| Run | 2026-11-01T10:39:02 → 2026-11-01T10:42:39 (218 s wall) |
| Footprint process match | `(\.lmstudio/|LM Studio)` |

## Result

| Metric | Value |
|---|---|
| Valid `read_file` tool calls | 10 / 10 |
| Timeouts (client, 180 s) | 0 |
| HTTP errors | 0 |
| Other failures (bad/no tool call, stream error) | 0 |
| TTFB p50 / p95 | 21.1 s / 21.8 s |
| TTFT p50 / p95 (requests that produced a token) | 21.1 s / 21.8 s |
| Total time p50 / p95 (successful) | 21.7 s / 22.5 s |
| Peak footprint (sum of matched processes) | 26.7 GB |

Raw: `raw.tsv`, `footprint.tsv`.
