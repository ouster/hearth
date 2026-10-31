# Bench — 2026-08-02-1327

Host: M4 Max, 64 GB. Ollama direct.

## Verbosity and speed

Tokens emitted is the number that matters. Throughput barely varies between
models on this machine — it is memory-bandwidth bound — so wall-clock is
driven by how much a model chooses to say. A *thinking* model can be the
slowest role while being the smallest.

| Model | tokens | total s | avg tok/s | syntax ok | syntax fail | errors |
|---|---|---|---|---|---|---|
| `qwen3-coder:30b` | 1375 (1.0x) | 12.9 | 106.6 | 2 | 0 | 0 |
| `gpt-oss:20b` | 5082 (3.7x) | 65.0 | 78.2 | 2 | 0 | 0 |
| `qwen3:8b` | 9895 (7.2x) | 127.6 | 77.5 | 2 | 0 | 0 |

## Per task

| Model | Task | tok/s | verdict |
|---|---|---|---|
| `qwen3-coder:30b` | 01-bash-launchd | 116.0 | syntax-ok |
| `qwen3-coder:30b` | 02-python-mcp-tool | 120.0 | syntax-ok |
| `qwen3-coder:30b` | 03-refactor-judgment | 118.2 | needs-reading |
| `qwen3-coder:30b` | 04-long-context | 83.3 | needs-reading |
| `gpt-oss:20b` | 01-bash-launchd | 73.4 | syntax-ok |
| `gpt-oss:20b` | 02-python-mcp-tool | 60.3 | syntax-ok |
| `gpt-oss:20b` | 03-refactor-judgment | 94.6 | needs-reading |
| `gpt-oss:20b` | 04-long-context | 88.9 | needs-reading |
| `qwen3:8b` | 01-bash-launchd | 80.2 | syntax-ok |
| `qwen3:8b` | 02-python-mcp-tool | 78.1 | syntax-ok |
| `qwen3:8b` | 03-refactor-judgment | 79.2 | needs-reading |
| `qwen3:8b` | 04-long-context | 64.6 | needs-reading |

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
/Users/colinnevin/dev/hearth/bench/results/2026-08-02-1327
```

## Decision

If a candidate wins, use `scripts/swap-role.sh <role> <model>`, then update
`docs/MODELS.md` and write an ADR. Nothing is promoted on speed alone.

