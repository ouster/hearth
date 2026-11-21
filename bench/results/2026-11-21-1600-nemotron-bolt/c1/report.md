# Concurrency bench — nemotron-bolt-74b-4bit

| | |
|---|---|
| Base URL | `http://127.0.0.1:1234/v1` |
| Role | `NVIDIA-Nemotron-3.5-Bolt-74B-A9B-4bit` |
| Concurrency × rounds | 1 × 10 = 10 requests |
| Target prompt tokens | 30000 (actual median 30477) |
| Client timeout | 600 s |
| Run | 2026-11-21T16:16:14 → 2026-11-21T16:26:28 (614 s wall) |
| Footprint process match | `\.omlx/` |

## Result

| Metric | Value |
|---|---|
| Valid `read_file` tool calls | 10 / 10 |
| Timeouts (client, 600 s) | 0 |
| HTTP errors | 0 |
| Other failures (bad/no tool call, stream error) | 0 |
| TTFB p50 / p95 | 0.0 s / 0.1 s |
| TTFT p50 / p95 (requests that produced a token) | 60.0 s / 63.9 s |
| Total time p50 / p95 (successful) | 60.5 s / 64.4 s |
| Peak footprint (sum of matched processes) | 0.0 GB |

Raw: `raw.tsv`, `footprint.tsv`.
