# Bench quality — 2026-11-12-1923 — Qwen3-Coder-Next-4bit

Challenger only. Not a role. Ctx 98304. `main-brain` restored after.

Host: M4 Max, 64 GB. oMLX on :1234. Seconds are wall time per request,
including prefill.

## Verbosity and speed

| Model | tokens | total s | avg tok/s | syntax ok | syntax fail | errors |
|---|---|---|---|---|---|---|
| `Qwen3-Coder-Next-4bit` | 4739 | 154.8 | 30.6 | 2 | 0 | 0 |

## Per task

| Model | Task | tokens | s | tok/s | verdict |
|---|---|---|---|---|---|
| `Qwen3-Coder-Next-4bit` | 01-bash-launchd | 118 | 16.4 | 7.2 | syntax-ok |
| `Qwen3-Coder-Next-4bit` | 02-python-mcp-tool | 260 | 3.6 | 72.2 | syntax-ok |
| `Qwen3-Coder-Next-4bit` | 03-refactor-judgment | 3952 | 53.9 | 73.3 | needs-reading |
| `Qwen3-Coder-Next-4bit` | 04-long-context | 409 | 80.9 | 5.1 | needs-reading |

Prompt tokens on 04: 62,389. No `reasoning_content` on any task.

## Quality — read these yourself

Syntax checks prove a model emitted parseable code, nothing more.

- **03-refactor-judgment** hides a float-for-currency bug in money
  arithmetic. A weak model fixes the obvious `range(len())` and misses the one
  that matters. This is the task that should decide `main-brain`.
- **04-long-context** feeds the repo's own docs in. It separates models that
  genuinely use long context from ones that skim the start and confabulate.

Outputs: `bench/results/2026-11-12-1923-coder-next-quality/`

## Decision

If a candidate wins, also run `scripts/concurrency-bench.sh` against it, then
point the role at those weights in `config/roles.tsv`, update `docs/MODELS.md`,
and write an ADR. Nothing is promoted on speed alone. Coder-Next already has
a c1 tool gate (`…-1903-coder-next-4bit`); this run is the quality read.
