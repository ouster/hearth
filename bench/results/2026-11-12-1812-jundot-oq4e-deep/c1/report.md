# Concurrency bench — jundot-qwen3.8-27b-oq4e-mtp deep challenger

| | |
|---|---|
| Base URL | `http://127.0.0.1:1234/v1` |
| Role | `Qwen3.8-27B-oQ4e-mtp` |
| Concurrency × rounds | 1 × 10 = 10 requests |
| Target prompt tokens | 30000 (actual median 30356) |
| Client timeout | 180 s |
| Run | 2026-11-12T18:12:34 → 2026-11-12T18:34:33 (1319 s wall) |
| Footprint process match | `omlx-server` |

## Result

| Metric | Value |
|---|---|
| Valid `read_file` tool calls | 10 / 10 |
| Timeouts (client, 180 s) | 0 |
| HTTP errors | 0 |
| Other failures (bad/no tool call, stream error) | 0 |
| TTFB p50 / p95 | 0.0 s / 0.1 s |
| TTFT p50 / p95 (requests that produced a token) | 129.6 s / 136.7 s |
| Total time p50 / p95 (successful) | 130.5 s / 137.8 s |
| Peak footprint (sum of matched processes) | 38.0 GB |

Raw: `raw.tsv`, `footprint.tsv`.
