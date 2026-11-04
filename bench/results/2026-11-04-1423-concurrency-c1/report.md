# Concurrency bench — oMLX trial, same 30k prompt twice

| | |
|---|---|
| Base URL | `http://127.0.0.1:1234/v1` |
| Role | `local-main` |
| Concurrency × rounds | 1 × 2 = 2 requests |
| Target prompt tokens | 30000 (actual median 30728) |
| Client timeout | 300 s |
| Run | 2026-11-04T14:23:08 → 2026-11-04T14:23:58 (50 s wall) |
| Footprint process match | `omlx serve` |

## Result

| Metric | Value |
|---|---|
| Valid `read_file` tool calls | 2 / 2 |
| Timeouts (client, 300 s) | 0 |
| HTTP errors | 0 |
| Other failures (bad/no tool call, stream error) | 0 |
| TTFB p50 / p95 | 0.0 s / 0.1 s |
| TTFT p50 / p95 (requests that produced a token) | 24.3 s / 25.0 s |
| Total time p50 / p95 (successful) | 24.6 s / 25.8 s |
| Peak footprint (sum of matched processes) | 0.0 GB — the listener is Python, not `omlx serve`, so this match saw nothing. The cache bench sampled that pid |

Raw: `raw.tsv`, `footprint.tsv`.
