# Qwen3-Coder-Next-4bit — quality (`bench/tasks`)

Date: 2026-11-12. Not a role change. Weights:
`mlx-community/Qwen3-Coder-Next-4bit` at ctx 98304. Live OptiQ was unloaded
for the run and loaded again after.

| Task | tokens | s | Auto | Read |
|---|---|---|---|---|
| 01-bash-launchd | 118 | 16.4 | syntax-ok | — |
| 02-python-mcp-tool | 260 | 3.6 | syntax-ok | — |
| 03-refactor-judgment | 3952 | 53.9 | — | **Catches float-for-currency.** Leads with Decimal / cents; also banker's rounding and validation. Very verbose (~4k tokens). |
| 04-long-context | 409 | 80.9 | — | **Uses the docs.** No fallback for `cloud-frontier`; four dormant cloud roles with the right blockers; Postgres on `:5433`. Some extra LiteLLM-era colour on why 5433. |

No thinking channel. Prior c1 tool gate: 10/10, TTFT p50 27.2 s, peak 52.0 GB
(`bench/results/2026-11-12-1903-coder-next-4bit`). Still one slot under the
56 GB ceiling; no `deep-brain` beside.

Quality is strong enough to keep as a challenger. It does not replace the
3 × 256K OptiQ resident without a different load story (TurboQuant KV, lower
ctx, or more RAM).
