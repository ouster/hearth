# Bench — 2026-09-04-1948

Host: M4 Max, 64 GB. Ollama direct.

## Verbosity and speed

Tokens emitted is the number that matters. Throughput barely varies between
models on this machine — it is memory-bandwidth bound — so wall-clock is
driven by how much a model chooses to say. A *thinking* model can be the
slowest role while being the smallest.

| Model | tokens | total s | avg tok/s | syntax ok | syntax fail | errors |
|---|---|---|---|---|---|---|
| `qwen3-coder:30b` | 1326 (1.0x) | 14.8 | 89.6 | 2 | 0 | 0 |
| `qwen3.6:27b-coding-mtp-q4_K_M` | 18648 (14.1x) | 970.2 | 19.2 | 2 | 0 | 0 |

## Per task

| Model | Task | tok/s | verdict |
|---|---|---|---|
| `qwen3-coder:30b` | 01-bash-launchd | 114.5 | syntax-ok |
| `qwen3-coder:30b` | 02-python-mcp-tool | 116.7 | syntax-ok |
| `qwen3-coder:30b` | 03-refactor-judgment | 112.5 | needs-reading |
| `qwen3-coder:30b` | 04-long-context | 57.3 | needs-reading |
| `qwen3.6:27b-coding-mtp-q4_K_M` | 01-bash-launchd | 19.2 | syntax-ok |
| `qwen3.6:27b-coding-mtp-q4_K_M` | 02-python-mcp-tool | 19.3 | syntax-ok |
| `qwen3.6:27b-coding-mtp-q4_K_M` | 03-refactor-judgment | 18.8 | needs-reading |
| `qwen3.6:27b-coding-mtp-q4_K_M` | 04-long-context | 20.2 | needs-reading |

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
/Users/colinnevin/dev/hearth/bench/results/2026-09-04-1948
```

## Decision

If a candidate wins, use `scripts/swap-role.sh <role> <model>`, then update
`docs/MODELS.md` and write an ADR. Nothing is promoted on speed alone.

