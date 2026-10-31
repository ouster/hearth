# Concurrency bench — phase 1, llmster direct, 3 slots x 64K, c3

| | |
|---|---|
| Base URL | `http://127.0.0.1:1234/v1` |
| Role | `local-big` |
| Concurrency × rounds | 3 × 10 = 30 requests |
| Target prompt tokens | 30000 (actual median 28700) |
| Client timeout | 180 s |
| Run | 2026-10-31T12:08:56 → 2026-10-31T12:19:12 (616 s wall) |
| Footprint process match | `(\.lmstudio/|^llmster)` |

## Result

| Metric | Value |
|---|---|
| Valid `read_file` tool calls | 28 / 30 |
| Timeouts (client, 180 s) | 0 |
| HTTP errors | 0 |
| Other failures (bad/no tool call, stream error) | 2 |
| TTFB p50 / p95 | 43.8 s / 59.9 s |
| TTFT p50 / p95 (requests that produced a token) | 43.8 s / 59.9 s |
| Total time p50 / p95 (successful) | 61.0 s / 62.2 s |
| Peak footprint (sum of matched processes) | 29.7 GB |

## Failures

| Round | Slot | HTTP | TTFT | Total | Finish | Error |
|---|---|---|---|---|---|---|
| 6 | 1 | 200 | 43.725 | 61.625 | tool_calls | no valid read_file call |
| 9 | 2 | 200 | 59.191 | 61.653 | tool_calls | no valid read_file call |

Raw: `raw.tsv`, `footprint.tsv`.
