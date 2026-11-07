# Concurrency bench — Jundot Qwen3.6-35B-A3B-oQ4e-mtp, thinking on, 128K x 3

| | |
|---|---|
| Base URL | `http://127.0.0.1:1234/v1` |
| Role | `local-main` |
| Concurrency × rounds | 3 × 10 = 30 requests |
| Target prompt tokens | 30000 (actual median 31426) |
| Client timeout | 180 s |
| Run | 2026-11-07T07:56:45 → 2026-11-07T08:07:20 (635 s wall) |
| Footprint process match | `\.omlx/` |

## Result

| Metric | Value |
|---|---|
| Valid `read_file` tool calls | 30 / 30 |
| Timeouts (client, 180 s) | 0 |
| HTTP errors | 0 |
| Other failures (bad/no tool call, stream error) | 0 |
| TTFB p50 / p95 | 0.1 s / 0.2 s |
| TTFT p50 / p95 (requests that produced a token) | 61.2 s / 63.4 s |
| Total time p50 / p95 (successful) | 63.1 s / 63.8 s |
| Peak footprint (sum of matched processes) | 33.0 GB |

Raw: `raw.tsv`, `footprint.tsv`.
