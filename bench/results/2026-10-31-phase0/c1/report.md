# Concurrency bench — phase 0 baseline, LiteLLM → Ollama MLX, c1

| | |
|---|---|
| Base URL | `http://127.0.0.1:4000/v1` |
| Role | `local-big` |
| Concurrency × rounds | 1 × 10 = 10 requests |
| Target prompt tokens | 30000 (actual median 28132) |
| Client timeout | 180 s |
| Run | 2026-10-31T10:41:07 → 2026-10-31T10:44:37 (210 s wall) |
| Footprint process match | `ollama (runner|serve)` |

## Result

| Metric | Value |
|---|---|
| Valid `read_file` tool calls | 10 / 10 |
| Timeouts (client, 180 s) | 0 |
| HTTP errors | 0 |
| Other failures (bad/no tool call, stream error) | 0 |
| TTFB p50 / p95 | 20.5 s / 21.0 s |
| TTFT p50 / p95 (requests that produced a token) | 20.5 s / 21.0 s |
| Total time p50 / p95 (successful) | 21.0 s / 21.6 s |
| Peak footprint (sum of matched processes) | 36.0 GB |

## Log lines during the run

None.

Raw: `raw.tsv`, `footprint.tsv`.
