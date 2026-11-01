# Bench — 2026-11-01-1307

Host: M4 Max, 64 GB. LM Studio on :1234. Seconds are wall time per request, including prefill.

## Verbosity and speed

Tokens emitted is the number that matters. Throughput barely varies between
models on this machine — it is memory-bandwidth bound — so wall-clock is
driven by how much a model chooses to say.

| Model | tokens | total s | avg tok/s | syntax ok | syntax fail | errors |
|---|---|---|---|---|---|---|
| `gemma-4-26b-a4b-it-qat-mlx` | 8477 (1.0x) | 118.1 | 71.8 | 2 | 0 | 0 |

## Per task

| Model | Task | tok/s | verdict |
|---|---|---|---|
| `gemma-4-26b-a4b-it-qat-mlx` | 01-bash-launchd | 107.7 | syntax-ok |
| `gemma-4-26b-a4b-it-qat-mlx` | 02-python-mcp-tool | 107.2 | syntax-ok |
| `gemma-4-26b-a4b-it-qat-mlx` | 03-refactor-judgment | 106.7 | needs-reading |
| `gemma-4-26b-a4b-it-qat-mlx` | 04-long-context | 42.1 | needs-reading |

## Quality — read these yourself

Syntax checks prove a model emitted parseable code, nothing more.

- **03-refactor-judgment** hides a float-for-currency bug in money
  arithmetic. A weak model fixes the obvious `range(len())` and misses the one
  that matters. This is the task that should decide `local-big`.
- **04-long-context** feeds the repo's own docs in. It separates models that
  genuinely use long context from ones that skim the start and confabulate.

Outputs:

```
/Users/colinnevin/dev/hearth/bench/results/2026-11-01-1307
```

## Decision

If a candidate wins, also run `scripts/concurrency-bench.sh` against it, then
`scripts/swap-role.sh <role> <model key> <weights path>`, update
`docs/MODELS.md` and write an ADR. Nothing is promoted on speed alone.

