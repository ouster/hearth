# Bench — 2026-10-22-0816

Host: M4 Max, 64 GB. Ollama direct.

## Verbosity and speed

Tokens emitted is the number that matters. Throughput barely varies between
models on this machine — it is memory-bandwidth bound — so wall-clock is
driven by how much a model chooses to say. A *thinking* model can be the
slowest role while being the smallest.

| Model | tokens | total s | avg tok/s | syntax ok | syntax fail | errors |
|---|---|---|---|---|---|---|
| `qwen3.6:35b-mlx` | 21972 (1.0x) | 197.0 | 111.5 | 2 | 0 | 0 |

## Per task

| Model | Task | tok/s | verdict |
|---|---|---|---|
| `qwen3.6:35b-mlx` | 01-bash-launchd | 111.6 | syntax-ok |
| `qwen3.6:35b-mlx` | 02-python-mcp-tool | 111.7 | syntax-ok |
| `qwen3.6:35b-mlx` | 03-refactor-judgment | 115.0 | needs-reading |
| `qwen3.6:35b-mlx` | 04-long-context | 96.7 | needs-reading |

## Quality — read these yourself

Syntax checks prove a model emitted parseable code, nothing more.

The two discriminating tasks cannot be scored automatically:

- **03-refactor-judgment** hides a float-for-currency bug in money
  arithmetic. A weak model fixes the obvious `range(len())` and misses the one
  that matters. This is the task that should decide `local-big`.
- **04-long-context** feeds the repo's own docs in. It separates models that
  genuinely use long context from ones that skim the start and confabulate.

Outputs:

```
/Users/colinnevin/dev/hearth/bench/results/2026-10-22-0816
```

## Decision

If a candidate wins, use `scripts/swap-role.sh <role> <model>`, then update
`docs/MODELS.md` and write an ADR. Nothing is promoted on speed alone.

