# Concurrency bench — qwen3.6, thinking on, 128K x 3, kernels

| | |
|---|---|
| Base URL | `http://127.0.0.1:1234/v1` |
| Role | `qwen3.6` |
| Concurrency × rounds | 3 × 10 = 30 requests |
| Target prompt tokens | 30000 (actual median 30587) |
| Client timeout | 180 s |
| Run | 2026-11-06T20:12:41 → 2026-11-06T20:22:59 (618 s wall) |
| Footprint process match | `\.omlx/` |

## Result

| Metric | Value |
|---|---|
| Valid `read_file` tool calls | 30 / 30 |
| Timeouts (client, 180 s) | 0 |
| HTTP errors | 0 |
| Other failures (bad/no tool call, stream error) | 0 |
| TTFB p50 / p95 | 0.1 s / 0.2 s |
| TTFT p50 / p95 (requests that produced a token) | 60.7 s / 61.5 s |
| Total time p50 / p95 (successful) | 61.6 s / 62.3 s |
| Peak footprint (sum of matched processes) | 34.0 GB |

Raw: `raw.tsv`, `footprint.tsv`.
