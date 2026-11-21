# Ripple-65B Preview MLX 4-bit — coding-brain challenger

Date: 2026-11-21. Not a role change. Weights:
`frogggias/Ripple-65B-Preview-MLX-4bit` (~34 GB *(repo)*). Apache 2.0.
Requires oMLX per-model `trust_remote_code` (reviewed `ricursive.py`: pure
MLX, no network/IO). Loaded after unloading OptiQ. Ctx raised to 32768 for
c1, 65536 for task 04.

| | Live coding-brain Coder-Next (2026-11-12 c1 × 10) | Ripple 4bit (this run, c1 × 10) |
|---|---|---|
| Tool-smoke | PASS | PASS |
| Valid tools | 10 / 10 | 10 / 10 |
| TTFT p50 / p95 | 27.2 / 27.3 s | 322.6 / 330.3 s |
| Peak footprint | 52.0 GB | ~54 GB (manual `footprint`; bench matcher missed `omlx-server`) |
| Slots | 1 | 1 |
| Gen tok/s (short) | — | ~10 |

~12× slower TTFT on ~28k tool turns. Dense 65B vs MoE 80B-A3B.

## Quality (`bench/tasks`)

| Task | tokens | s | Auto | Read |
|---|---|---|---|---|
| 01-bash-launchd | 162 | 15.5 | syntax-ok | — |
| 02-python-mcp-tool | 1655 | 150.0 | syntax-ok | Verbose |
| 03-refactor-judgment | 598 | 55.2 | — | **Catches float-for-currency.** Decimal / cents; validation. Tighter than Coder-Next's ~4k-token answer |
| 04-long-context | 490 | 829.7 | — | **Uses the docs** at 64K ctx (failed at 32K). Four dormant cloud roles; Postgres `:5433`; no cloud-frontier fallback |

## Verdict

Quality is competitive with Coder-Next on 03/04. Agent latency is not:
322 s TTFT vs 27 s makes it a poor swap for interactive coding on this
64 GB host. Keep as an optional deep/coding one-shot candidate only if
someone accepts the wait. Do not point `roles.tsv` at it.
