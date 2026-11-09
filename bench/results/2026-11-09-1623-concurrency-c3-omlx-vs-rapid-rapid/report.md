# Concurrency bench — rapid-optiq

| | |
|---|---|
| Base URL | `http://127.0.0.1:8000/v1` |
| Role | `main-brain` |
| Concurrency × rounds | 3 × 10 = 30 requests |
| Target prompt tokens | 30000 (actual median 29893) |
| Client timeout | 180 s |
| Run | 2026-11-09T16:23:51 → 2026-11-09T16:34:42 (650 s wall) |
| Footprint process match | `rapid-mlx|vllm_mlx|BatchedEngine` |

## Result

| Metric | Value |
|---|---|
| Valid `read_file` tool calls | 30 / 30 |
| Timeouts (client, 180 s) | 0 |
| HTTP errors | 0 |
| Other failures (bad/no tool call, stream error) | 0 |
| TTFB p50 / p95 | 0.3 s / 0.3 s |
| TTFT p50 / p95 (requests that produced a token) | 45.3 s / 64.8 s |
| Total time p50 / p95 (successful) | 54.1 s / 65.1 s |
| Peak footprint (sum of matched processes) | 30.0 GB |

Raw: `raw.tsv`, `footprint.tsv`.
