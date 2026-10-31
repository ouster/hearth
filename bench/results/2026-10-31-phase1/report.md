# Phase 1 — LM Studio (llmster) beside the current stack

**Date:** 2026-10-31. **Plan:** `docs/MIGRATION-LMSTUDIO.md` phase 1.
**Stack:** llmster 0.0.27-1 on `127.0.0.1:1234`, MLX runtime 1.13.1, role
`local-big` loaded per `config/roles.tsv` (65536 ctx, `--parallel 3`),
`local-embed` beside it. Token `LMSTUDIO_HOST_TOKEN`. Auth/CORS/LAN/JIT set
once in the LM Studio 0.4.28 app, then the app quit; llmster honours them.
Ollama could not compete for GPU: Ollama.app was moved to the Trash before
the run, so no runner could start.

Same method as phase 0: `scripts/concurrency-bench.sh`, 10 rounds, ~28.7K
actual prompt tokens, unique prefix per request, 180 s client timeout.

| | Phase 0 c1 | Phase 1 c1 | Phase 0 c3 | Phase 1 c3 |
|---|---|---|---|---|
| Valid `read_file` calls | 10/10 | 9/10 | 30/30 | 28/30 |
| Timeouts / HTTP errors | 0/0 | 0/0 | 0/0 | 0/0 |
| TTFT p50 / p95 | 20.5 / 21.0 s | 19.5 / 19.9 s | 39.9 / 65.8 s | 43.8 / **59.9 s** |
| Total p50 / p95 | 21.0 / 21.6 s | 20.6 / 24.2 s | 40.3 / 66.3 s | **61.0 / 62.2 s** |
| Wall, 10 rounds | 210 s | — | 625 s | 616 s |
| Peak footprint | 36.0 GB | 26.7 GB | 37.0 GB | 29.7 GB |

## Gate

| Condition | Result |
|---|---|
| tool-smoke passes | **pass** (`read_file` → `write_file`, `<` preserved) |
| c3 × 10: zero timeouts | **pass** |
| c3 × 10: zero invalid tool calls | **fail, strictly**: 2/30 (and 1/10 at c1) returned a well-formed `grep` call instead of the requested `read_file` |
| c3 p95 TTFT better than 65.8 s | **pass, narrowly**: 59.9 s |
| Peak footprint ≥ 4 GB under wired limit (~48 GB) | **pass**: 29.7 GB, ~18 GB headroom |
| No token → 401 | **pass** (no token 401, bad token 401, host token 200, LAN IP no answer) |

## Reading

- **Prefill is still serialised.** At c3 TTFT steps ~24 / ~44 / ~60 s, the
  same staircase as Ollama. `--parallel 3` batches decode, not prefill.
- **And decode waits for every prefill.** All three requests in a round
  finish together at ~61 s. Under Ollama the first finished at ~20 s. So
  median completion at c3 is *worse* (61 s vs 40 s); only the worst case
  improved. Throughput is unchanged (610 s vs 625 s wall).
- **Memory is the clear win.** 29.7 GB at 3 × 64K vs 37 GB for one slot on
  Ollama, and no eviction path. Phase 2 (wired limit) has nothing to fix.
- **Wrong-tool picks (3/40)** are well-formed calls to the wrong tool, not
  parse failures. Phase 0 on the Ollama build had 0/40. Different
  quantisation and chat template; cause not isolated.
- c1 TTFT is ~1 s better; the ~600 ms gateway hop is gone.

Per-run detail: `c1/`, `c3/` (`report.md`, `raw.tsv`, `footprint.tsv`, logs).
