# Concurrency bench — 128K, LM Studio app, 1 slot x 128K, c3

| | |
|---|---|
| Base URL | `http://127.0.0.1:1234/v1` |
| Role | `local-big` |
| Concurrency × rounds | 3 × 10 = 30 requests |
| Target prompt tokens | 30000 (actual median 29869) |
| Client timeout | 180 s |
| Run | 2026-11-01T10:59:25 → 2026-11-01T11:11:19 (714 s wall) |
| Footprint process match | `(\.lmstudio/|LM Studio)` |

## Result

| Metric | Value |
|---|---|
| Valid `read_file` tool calls | 30 / 30 |
| Timeouts (client, 180 s) | 0 |
| HTTP errors | 0 |
| Other failures (bad/no tool call, stream error) | 0 |
| TTFB p50 / p95 | 47.4 s / 71.6 s |
| TTFT p50 / p95 (requests that produced a token) | 47.4 s / 71.6 s |
| Total time p50 / p95 (successful) | 48.1 s / 72.4 s |
| Peak footprint (sum of matched processes) | 26.8 GB |

Raw: `raw.tsv`, `footprint.tsv`.
