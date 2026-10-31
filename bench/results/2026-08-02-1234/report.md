# Bench — 2026-08-02-1234

Host: M4 Max, 64 GB. Ollama direct.

## Speed and auto-checks

| Model | tokens | total s | avg tok/s | syntax ok | syntax fail | errors |
|---|---|---|---|---|---|---|
| `gpt-oss:20b` | 5950 | 63.7 | 93.4 | 2 | 0 | 0 |
| `qwen3-coder:30b` | 1254 | 11.5 | 109.0 | 2 | 0 | 0 |
| `qwen3:8b` | 10309 | 133.6 | 77.2 | 2 | 0 | 0 |

## Per task

| Model | Task | tok/s | verdict |
|---|---|---|---|
| `qwen3-coder:30b` | 01-bash-launchd | 123.3 | syntax-ok |
| `qwen3-coder:30b` | 02-python-mcp-tool | 120.0 | syntax-ok |
| `qwen3-coder:30b` | 03-refactor-judgment | 118.0 | needs-reading |
| `qwen3-coder:30b` | 04-long-context | 85.0 | needs-reading |
| `gpt-oss:20b` | 01-bash-launchd | 95.0 | syntax-ok |
| `gpt-oss:20b` | 02-python-mcp-tool | 95.4 | syntax-ok |
| `gpt-oss:20b` | 03-refactor-judgment | 94.0 | needs-reading |
| `gpt-oss:20b` | 04-long-context | 88.7 | needs-reading |
| `qwen3:8b` | 01-bash-launchd | 79.7 | syntax-ok |
| `qwen3:8b` | 02-python-mcp-tool | 77.4 | syntax-ok |
| `qwen3:8b` | 03-refactor-judgment | 78.5 | needs-reading |
| `qwen3:8b` | 04-long-context | 66.3 | needs-reading |

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
/Users/colinnevin/dev/hearth/bench/results/2026-08-02-1234
```

## Decision

If a candidate wins, use `scripts/swap-role.sh <role> <model>`, then update
`docs/MODELS.md` and write an ADR. Nothing is promoted on speed alone.

