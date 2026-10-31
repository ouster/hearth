# What we have tried

A running record of serving-stack and role experiments: what was tried, what
it measured, and why it stayed or went. Newest last. Add a row whenever an
ADR lands or a bench run changes a decision.

Model names stay out of this file (hard rule 1) — which weights each role
used is in `docs/MODELS.md` (Live / Retired). Raw numbers are in
`bench/results/<run>/`, committed since 2026-10-31. Runs before that were
re-checked in and had domain wording in old task prompts and model answers
redacted (billing/invoice substituted); figures are unchanged.

## Serving stack

| Date | Tried | Result | Outcome | Record |
|---|---|---|---|---|
| 2026-08-01 | Inherited setup: Ollama + LiteLLM, ad-hoc model names | Worked, no role discipline, no privacy boundary | Rebuilt around roles and scoped keys | ADR 0001 |
| 2026-08-02 | Postgres + Prisma for LiteLLM virtual keys | Per-key scope; leak test passes | Kept until 0016 | ADR 0002 |
| 2026-08-02 | Ollama bound to localhost; LAN via gateway only | LAN probe unreachable | Kept until 0016 | ADR 0003 |
| 2026-08-02 | Agents under `sandboxed.sh`, egress only to the gateway | Probe proves nothing else reachable | Kept; target port moves to `:1234` | ADR 0007 |
| 2026-08-02 | MCP tools through the gateway, deny by default, scoped by key | Works; adds gateway coupling | Superseded by 0016 (MCP moves to the client) | ADR 0008 |
| 2026-09-04 | Context capped at 64K for local roles | Fits the RAM envelope | Kept | ADR 0010 |
| 2026-09-04 | Ollama memory knobs: flash attention, q8_0 KV, 1 loaded model, 1 parallel | One slot for every client; any role switch evicts the agent model | Superseded by 0016 (F1, F2) | ADR 0011 |
| 2026-09-06 | `local-big` on Rapid-MLX `:8000` | Tool smoke 2.6 s vs 12–18 s on Ollama | Superseded by 0013 (second server to supervise) | ADR 0012, `2026-09-06-1229-tool-smoke` |
| 2026-10-22 | `local-big` on Ollama's MLX runner, one inference server | ~111 tok/s; Zed agent loops still stall under load | Superseded by 0016 | ADR 0013, `2026-10-22-0816` |
| 2026-10-31 | Stall handling: 90 s timeout, no retries, `mlx-watchdog` kills a stuck runner | Treats the symptom (F7) | Superseded by 0016 | ADR 0015 |
| 2026-10-31 | Phase 0 concurrency baseline on that stack | c1 TTFT p95 21.0 s; c3 p95 65.8 s, strictly serialised; no failures, peak 37 GB | Numbers to beat | `2026-10-31-phase0` |
| 2026-10-31 | D6 switched to the LM Studio app owning the server | llmster and the app cannot share `~/.lmstudio`; app costs ~1.1 GB | Kept | ADR 0016 |
| 2026-10-31 | Podman VM died after login | launchd kills a job's leftover processes when it exits; reproduced with a test job | `AbandonProcessGroup` on `com.hearth.boot`; VM survives the job | — |
| 2026-10-31 | Phase 4 as an SSH tunnel with tunnel-only keys (D8), not LAN serving | Host unexposed; tested against a throwaway sshd: `restrict` alone still ran remote commands, a forced command fixed it | Kept; laptop gate pending | ADR 0016, `docs/LAPTOP.md` |
| 2026-10-31 | Zed picker labels generated from roles.tsv (`zed-sync.sh`) | Clients still call `local-big`; label cannot go stale | Kept; rule 1 amended for generated labels | — |
| 2026-10-31 | Phase 5 scripts against LM Studio; weight hashing (D4); login agent | healthcheck 10 pass / 1 warn, preflight 29 pass; negative controls fail as designed; found saved settings drifted to 0.0.0.0 + CORS, and unknown model names served by local-big | Kept | ADR 0016 |
| 2026-10-31 | Old stack deleted without a soak | Ports 4000/5433/11434 free; tool-smoke and sandbox-probe still pass | No rollback; backups in `~/hearth-backups/` | ADR 0016 |
| 2026-10-31 | Phase 1: llmster direct, `local-big` 3 parallel × 64K | c3 TTFT p95 59.9 s (was 65.8); prefill still serialised, all three finish at ~61 s; peak 29.7 GB; 3/40 wrong-tool picks | Accepted by operator; no further bench | ADR 0016, `2026-10-31-phase1` |

## Roles

| Date | Tried | Result | Outcome | Record |
|---|---|---|---|---|
| 2026-08-02 | 70B dense model as `local-big` | 42 GB, could not stay resident; 440 s to first reply | Retired | ADR 0004 |
| 2026-08-02 | 30B MoE as `local-big` / `local-code` | Fits beside other roles; fast | `local-code` kept; `local-big` reassigned | ADR 0004, 0005 |
| 2026-08-02 | Separate `local-fast` small coder | MoE already generates at small-model speed | Role retired | ADR 0005 |
| 2026-08-02 | `local-chat` small general model, thinking on | Very verbose: 7–11× the tokens of the coder | Thinking disabled: 29.7 s → 5.1 s | ADR 0005, 0006, `2026-08-02-*` |
| 2026-09-04 | 27B dense MTP coding model as candidate | 19 tok/s, 14× tokens | Not adopted | `2026-09-04-1948` |
| 2026-09-06 | 20B reasoning model as `local-big` | Slower tool smoke than the MLX agent model | Retired | ADR 0012 |
| 2026-10-22 | `cloud-cheap` on a newer Flash tier | Thinks by default; tiny caps return empty | Kept, reasoning advertised | ADR 0014 |
| 2026-10-31 | Collapse `local-code` / `local-chat` into `local-big` (D1) | Decided; avoids evicting the agent model | Phase 1 onward | ADR 0016 |
