# Phase 0 — baseline concurrency bench (current stack)

**Date:** 2026-10-31. **Plan:** `docs/MIGRATION-LMSTUDIO.md` phase 0.
**Stack:** LiteLLM `:4000` → Ollama MLX runner, role `local-big`, key
`LITELLM_PRIVATE_KEY`. `mlx-watchdog` active (no kills during either run).
`iogpu.wired_limit_mb = 0` (default ~48 GB).

**Method:** `scripts/concurrency-bench.sh`, 10 rounds, ~28.1K actual prompt
tokens (target 30K), 6 tool schemas, `stream: true`, per-request nonce so every
request pays full prefill, client timeout 180 s. A round fires N requests at
once and waits for all.

| | c1 | c3 |
|---|---|---|
| Valid `read_file` calls | 10 / 10 | 30 / 30 |
| Timeouts / HTTP errors | 0 / 0 | 0 / 0 |
| TTFT p50 / p95 | 20.5 s / 21.0 s | 39.9 s / 65.8 s |
| Total p50 / p95 | 21.0 s / 21.6 s | 40.3 s / 66.3 s |
| Wall time | 210 s | 625 s |
| Peak footprint (runner + serve) | 36.0 GB | 37.0 GB |

## Reading

- **Strict serialisation (F1 confirmed).** At c3 every round is a staircase:
  ~20 s, ~40 s, ~60 s. Three clients get one slot; the third waits for two
  full prefills. Throughput is identical to c1 (≈ 20 s per request).
- **No stall reproduced (F3 not triggered).** Footprint peaked at 37 GB, under
  the watchdog's 38 GB line, and no request failed. The plan expected failures
  at c3; this workload did not produce them. Likely why: output is a ~10-token
  tool call, so each slot is almost entirely prefill. Real Zed turns generate
  longer and grow context across a thread.
- **Headroom to failure is small.** The third request lands at ~66 s against
  LiteLLM's 90 s `local-big` timeout. A fourth concurrent client (~80 s) is at
  the edge; a fifth would time out.
- **TTFB = TTFT** through LiteLLM: the gateway sends no bytes until the first
  token, so a queued request is indistinguishable from a dead one at the
  client — the mechanism behind F1's "looks dead".

## Numbers to beat in phase 1

- c3 TTFT p95 **< 65.8 s** (gate). Real concurrency should bring it near c1.
- Zero timeouts and zero invalid tool calls at c3.
- Peak footprint ≥ 4 GB under the wired limit.

Per-run detail: `c1/report.md`, `c3/report.md` (+ `raw.tsv`, `footprint.tsv`,
console logs `c1.log`, `c3.log`).
