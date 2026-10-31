# Concurrency bench — phase 0 baseline, LiteLLM → Ollama MLX, c3

| | |
|---|---|
| Base URL | `http://127.0.0.1:4000/v1` |
| Role | `local-big` |
| Concurrency × rounds | 3 × 10 = 30 requests |
| Target prompt tokens | 30000 (actual median 28134) |
| Client timeout | 180 s |
| Run | 2026-10-31T10:44:37 → 2026-10-31T10:55:02 (625 s wall) |
| Footprint process match | `ollama (runner|serve)` |

## Result

| Metric | Value |
|---|---|
| Valid `read_file` tool calls | 30 / 30 |
| Timeouts (client, 180 s) | 0 |
| HTTP errors | 0 |
| Other failures (bad/no tool call, stream error) | 0 |
| TTFB p50 / p95 | 39.9 s / 65.8 s |
| TTFT p50 / p95 (requests that produced a token) | 39.9 s / 65.8 s |
| Total time p50 / p95 (successful) | 40.3 s / 66.3 s |
| Peak footprint (sum of matched processes) | 37.0 GB |

## Log lines during the run

None.

Raw: `raw.tsv`, `footprint.tsv`.
