# Concurrency bench — Gemma 4 26B-A4B QAT, thinking on, 3 slots x 128K, c1

| | |
|---|---|
| Base URL | `http://127.0.0.1:1234/v1` |
| Role | `bench-candidate` |
| Concurrency × rounds | 1 × 10 = 10 requests |
| Target prompt tokens | 30000 (actual median 30172) |
| Client timeout | 180 s |
| Run | 2026-11-01T13:11:58 → 2026-11-01T13:16:06 (248 s wall) |
| Footprint process match | `(\.lmstudio/|LM Studio)` |

## Result

| Metric | Value |
|---|---|
| Valid `read_file` tool calls | 10 / 10 |
| Timeouts (client, 180 s) | 0 |
| HTTP errors | 0 |
| Other failures (bad/no tool call, stream error) | 0 |
| TTFB p50 / p95 | 24.3 s / 25.0 s |
| TTFT p50 / p95 (requests that produced a token) | 24.3 s / 25.0 s |
| Total time p50 / p95 (successful) | 24.6 s / 26.6 s |
| Peak footprint (sum of matched processes) | 23.9 GB |

Raw: `raw.tsv`, `footprint.tsv`.
