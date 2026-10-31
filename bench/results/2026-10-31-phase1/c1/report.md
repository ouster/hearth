# Concurrency bench — phase 1, llmster direct, 3 slots x 64K, c1

| | |
|---|---|
| Base URL | `http://127.0.0.1:1234/v1` |
| Role | `local-big` |
| Concurrency × rounds | 1 × 10 = 10 requests |
| Target prompt tokens | 30000 (actual median 28701) |
| Client timeout | 180 s |
| Run | 2026-10-31T12:05:26 → 2026-10-31T12:08:55 (209 s wall) |
| Footprint process match | `(\.lmstudio/|^llmster)` |

## Result

| Metric | Value |
|---|---|
| Valid `read_file` tool calls | 9 / 10 |
| Timeouts (client, 180 s) | 0 |
| HTTP errors | 0 |
| Other failures (bad/no tool call, stream error) | 1 |
| TTFB p50 / p95 | 19.5 s / 19.9 s |
| TTFT p50 / p95 (requests that produced a token) | 19.5 s / 19.9 s |
| Total time p50 / p95 (successful) | 20.6 s / 24.2 s |
| Peak footprint (sum of matched processes) | 26.7 GB |

## Failures

| Round | Slot | HTTP | TTFT | Total | Finish | Error |
|---|---|---|---|---|---|---|
| 9 | 0 | 200 | 19.545 | 21.092 | tool_calls | no valid read_file call |

Raw: `raw.tsv`, `footprint.tsv`.
