# Bench — 2026-11-07-0754

Host: M4 Max, 64 GB. oMLX on :1234. Seconds are wall time per request, including prefill.

## Verbosity and speed

Tokens emitted is the number that matters. Throughput barely varies between
models on this machine — it is memory-bandwidth bound — so wall-clock is
driven by how much a model chooses to say.

| Model | tokens | total s | avg tok/s | syntax ok | syntax fail | errors |
|---|---|---|---|---|---|---|
| `local-main` | 16336 (1.0x) | 138.4 | 118.0 | 2 | 0 | 0 |

## Per task

| Model | Task | tok/s | verdict |
|---|---|---|---|
| `local-main` | 01-bash-launchd | 170.9 | syntax-ok |
| `local-main` | 02-python-mcp-tool | 172.5 | syntax-ok |
| `local-main` | 03-refactor-judgment | 172.3 | needs-reading |
| `local-main` | 04-long-context | 49.6 | needs-reading |

## Quality — read these yourself

Syntax checks prove a model emitted parseable code, nothing more.

- **03-refactor-judgment** hides a float-for-currency bug in money
  arithmetic. A weak model fixes the obvious `range(len())` and misses the one
  that matters. This is the task that should decide `local-main`.
- **04-long-context** feeds the repo's own docs in. It separates models that
  genuinely use long context from ones that skim the start and confabulate.

Outputs:

```
/Users/colinnevin/dev/hearth/bench/results/2026-11-07-0754
```

## Decision

If a candidate wins, also run `scripts/concurrency-bench.sh` against it, then
point the role at those weights in `config/roles.tsv`, update `docs/MODELS.md`,
and write an ADR. Nothing is promoted on speed alone.

