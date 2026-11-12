# Concurrency bench — qwen3-coder-next-4bit main challenger ctx98k

| | |
|---|---|
| Base URL | `http://127.0.0.1:1234/v1` |
| Role | `Qwen3-Coder-Next-4bit` |
| Concurrency × rounds | 1 × 10 = 10 requests |
| Target prompt tokens | 30000 (actual median 29673) |
| Client timeout | 600 s |
| Run | 2026-11-12T19:03:09 → 2026-11-12T19:07:42 (272 s wall) |
| Footprint process match | `omlx-server` |

## Result

| Metric | Value |
|---|---|
| Valid `read_file` tool calls | 10 / 10 |
| Timeouts (client, 600 s) | 0 |
| HTTP errors | 0 |
| Other failures (bad/no tool call, stream error) | 0 |
| TTFB p50 / p95 | 0.0 s / 0.1 s |
| TTFT p50 / p95 (requests that produced a token) | 27.2 s / 27.3 s |
| Total time p50 / p95 (successful) | 27.2 s / 27.3 s |
| Peak footprint (sum of matched processes) | 52.0 GB |

Raw: `raw.tsv`, `footprint.tsv`.
