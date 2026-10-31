# Bench — 2026-08-02-1726

Host: M4 Max, 64 GB. Ollama direct.

## Verbosity and speed

Tokens emitted is the number that matters. Throughput barely varies between
models on this machine — it is memory-bandwidth bound — so wall-clock is
driven by how much a model chooses to say. A *thinking* model can be the
slowest role while being the smallest.

| Model | tokens | total s | avg tok/s | syntax ok | syntax fail | errors |
|---|---|---|---|---|---|---|
| `qwen3-coder:30b` | 1162 (1.0x) | 12.4 | 93.7 | 2 | 0 | 0 |
| `gpt-oss:20b` | 7178 (6.2x) | 80.6 | 89.1 | 2 | 0 | 0 |
| `qwen3:8b` | 12710 (10.9x) | 175.1 | 72.6 | 2 | 0 | 0 |

## Per task

| Model | Task | tok/s | verdict |
|---|---|---|---|
| `qwen3-coder:30b` | 01-bash-launchd | 114.5 | syntax-ok |
| `qwen3-coder:30b` | 02-python-mcp-tool | 120.0 | syntax-ok |
| `qwen3-coder:30b` | 03-refactor-judgment | 118.6 | needs-reading |
| `qwen3-coder:30b` | 04-long-context | 61.9 | needs-reading |
| `gpt-oss:20b` | 01-bash-launchd | 95.3 | syntax-ok |
| `gpt-oss:20b` | 02-python-mcp-tool | 95.6 | syntax-ok |
| `gpt-oss:20b` | 03-refactor-judgment | 94.7 | needs-reading |
| `gpt-oss:20b` | 04-long-context | 80.9 | needs-reading |
| `qwen3:8b` | 01-bash-launchd | 78.4 | syntax-ok |
| `qwen3:8b` | 02-python-mcp-tool | 72.9 | syntax-ok |
| `qwen3:8b` | 03-refactor-judgment | 75.5 | needs-reading |
| `qwen3:8b` | 04-long-context | 49.4 | needs-reading |

## Quality — read these yourself

Syntax checks prove a model emitted parseable code, nothing more.

The two discriminating tasks cannot be scored automatically:

- **03-refactor-judgment** hides a float-for-currency bug in invoice
  arithmetic. A weak model fixes the obvious `range(len())` and misses the one
  that matters. This is the task that should decide `local-big`.
- **04-long-context** feeds the repo's own docs in. It separates models that
  genuinely use long context from ones that skim the start and confabulate.

Outputs:

```
/Users/colinnevin/dev/hearth/bench/results/2026-08-02-1726
```

## Decision

If a candidate wins, use `scripts/swap-role.sh <role> <model>`, then update
`docs/MODELS.md` and write an ADR. Nothing is promoted on speed alone.

