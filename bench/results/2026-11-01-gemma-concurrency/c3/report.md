# Concurrency bench — Gemma 4 26B-A4B QAT, thinking on, 3 slots x 128K, c3

| | |
|---|---|
| Base URL | `http://127.0.0.1:1234/v1` |
| Role | `bench-candidate` |
| Concurrency × rounds | 3 × 10 = 30 requests |
| Target prompt tokens | 30000 (actual median 30173) |
| Client timeout | 180 s |
| Run | 2026-11-01T13:16:06 → 2026-11-01T13:28:26 (740 s wall) |
| Footprint process match | `(\.lmstudio/|LM Studio)` |

## Result

| Metric | Value |
|---|---|
| Valid `read_file` tool calls | 30 / 30 |
| Timeouts (client, 180 s) | 0 |
| HTTP errors | 0 |
| Other failures (bad/no tool call, stream error) | 0 |
| TTFB p50 / p95 | 54.3 s / 74.8 s |
| TTFT p50 / p95 (requests that produced a token) | 54.3 s / 74.8 s |
| Total time p50 / p95 (successful) | 73.0 s / 75.2 s |
| Peak footprint (sum of matched processes) | 25.2 GB |

Raw: `raw.tsv`, `footprint.tsv`.
