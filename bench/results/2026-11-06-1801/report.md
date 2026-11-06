# Bench — 2026-11-06-1801

Host: M4 Max, 64 GB. oMLX 0.7.3 on :1234, native kernels built. One model loaded at a time. Seconds are wall time per request, including prefill.

Weights: `local-main` Gemma 4 26B-A4B, `qwen3.6` Qwen3.6 35B-A3B (in `~/.hearth/models`, not a role), `local-deep` Qwen3.8 27B. Thinking on. Context 128K for the first two, 64K for `local-deep`. `local-deep` max output 32768, the others 65536.

## Verbosity and speed

| Model | tokens | total s | avg tok/s | syntax ok | syntax fail |
|---|---|---|---|---|---|
| `local-main` (Gemma 4) | 9488 (1.0x) | 171.7 | 55.3 | 2 | 0 |
| `qwen3.6` | 20503 (2.2x) | 170.8 | 120.0 | 2 | 0 |
| `local-deep` (Qwen 3.8) | 78276 (8.2x) | 3046.8 | 25.7 | 1 | 1 |

## Per task

| Model | Task | prompt | tokens | s | tok/s | verdict |
|---|---|---|---|---|---|---|
| `local-main` | 01-bash-launchd | 124 | 1681 | 17.2 | 97.9 | syntax-ok |
| `local-main` | 02-python-mcp-tool | 154 | 2691 | 27.9 | 96.4 | syntax-ok |
| `local-main` | 03-refactor-judgment | 179 | 2996 | 31.4 | 95.3 | needs-reading |
| `local-main` | 04-long-context | 44222 | 2120 | 95.2 | 22.3 | needs-reading |
| `qwen3.6` | 01-bash-launchd | 110 | 3334 | 21.8 | 153.0 | syntax-ok |
| `qwen3.6` | 02-python-mcp-tool | 144 | 8058 | 51.2 | 157.2 | syntax-ok |
| `qwen3.6` | 03-refactor-judgment | 162 | 6616 | 42.0 | 157.7 | needs-reading |
| `qwen3.6` | 04-long-context | 43361 | 2495 | 55.8 | 44.7 | needs-reading |
| `local-deep` | 01-bash-launchd | 152 | 20905 | 762.1 | 27.4 | syntax-ok |
| `local-deep` | 02-python-mcp-tool | 186 | 20062 | 706.1 | 28.4 | SYNTAX-FAIL |
| `local-deep` | 03-refactor-judgment | 204 | 32768 | 1190.0 | 27.5 | needs-reading |
| `local-deep` | 04-long-context | 43403 | 4541 | 388.6 | 11.7 | needs-reading |

## Quality

- **03.** Gemma 4 and Qwen 3.6 both name the float-for-currency bug and rewrite it with `Decimal` and `ROUND_HALF_UP`. Qwen 3.8 hit the 32768 output cap (`finish_reason=length`) and the visible answer is empty.
- **04.** Qwen 3.6 and Qwen 3.8 both say there is no `cloud-frontier` fallback chain, list all four dormant roles with what each is blocked on, and say Postgres is `:5433` with the reason absent. Gemma 4 says the fallback is not in the file and omits `cloud-frontier-direct`.
- **02.** Qwen 3.8's syntax fail is the auto-check parsing the whole unfenced answer, prose included. The function at the top is Python.

## Reading

No swap. Gemma 4 remains the better `local-main`: the three short tasks finish sooner, it uses about half the tokens of Qwen 3.6, and the weights are smaller. Qwen 3.6 decodes much faster and is the better long-context answer, at 2.2× the tokens and 19 GB on disk. Qwen 3.8 is slower at every task and spent twenty minutes on the money question without an answer. A concurrency run is still required before pointing `local-main` at Qwen 3.6.
