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
| 2026-10-31 | `local-big` context raised to 128K, still 3 slots | Model card asks for ≥128K so thinking holds. Reload honored 131072 (not 262144). Idle footprint 20.7 GB; c3 bench not re-run | Kept | ADR 0017 |
| 2026-11-01 | Draft MTP on for `local-big` | Same weights. Speeds decode, not the prefill wait. `lms load` accepted the flag; the server log does not name the drafter, and `lms ps` cannot show it | Flag set | — |
| 2026-11-01 | Drop `local-embed` | Nothing requested embeddings except healthcheck. Weights stay on disk, unloaded | Removed | ADR 0018 |
| 2026-11-01 | `local-big` c3 re-run at 128K; then 1 slot vs 3 | 128K costs nothing over 64K at ~30K prompts (29.7 GB peak). 1 slot: median finish 48 s vs 63 s, but p95 72 s vs 66 s and 12% less throughput | Kept 3 slots | `2026-11-01-128k` |

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
| 2026-11-01 | 27B dense model as `local-big` candidate | Best `bench/tasks` 03 answer, but ~26 tok/s and 2.5–5.5× the tokens: 10–24× the wall time | Not adopted as `local-big` | `2026-11-01-1140` |
| 2026-11-01 | 26B-A4B MoE (QAT) as `local-big`, thinking off | Fast, but task 04 dropped two keys; a simple sum wrong 3 times | Thinking turned on in the app | `2026-11-01-1243` |
| 2026-11-01 | Same, thinking on | All four tasks correct, 12–64 s each; 40/40 tool calls; ~15% slower prefill, 25.2 GB c3 peak | Became `local-big` | ADR 0019, `2026-11-01-1307`, `2026-11-01-gemma-concurrency` |
| 2026-11-01 | The 27B dense model as on-demand `local-deep` beside `local-big` | Loads in ~12 s; 33.3 GB with both idle; **49.9 GB** peak with both busy (over the ceiling, swap ~5 GB), and the 3 `local-big` requests overlapping its 193 s prefill timed out | Swapped in instead of `local-big`, never beside it | ADR 0020 |
| 2026-11-01 | Rename `local-big` to `local-main` | Size no longer described it (26B resident, 27B on demand); `local-code` rejected as a retired name | Renamed | ADR 0021 |
| 2026-11-01 | Snyk monitoring of the WebUI and SearXNG images | No manifests in the repo; the containers are the third-party code | Kept, re-run on `up` | `scripts/snyk-monitor.sh` |
| 2026-11-01 | SearXNG MCP server for the Zed agent, `web` profile | ~12 candidates vetted; one passed. Search only; URL reader off and refuses private addresses | Kept | ADR 0022 |
| 2026-11-01 | Tunnel keys also forward `:8888` (SearXNG) for laptops | Throwaway sshd: `:8888`/`:1234` forward; commands, `:22`, `-R` refused. Existing key widened in place | Kept | ADR 0022 |
| 2026-11-01 | Review fixes for the tunnel, `ask-deep`, and the loopback lock | Interrupted `ask-deep` restores the resident role; a partial tunnel is a failure; key update refuses a full-shell `hearth-tunnel-*` line and keeps extra options; boot confirms loopback and CORS from the saved settings | Kept | — |
| 2026-11-01 | `local-main` rolled back off the 26B-A4B | Zed agent turns kept looping after sampling matched that model's generation config | Previous resident restored, 128K × 3, MTP on. Tool-smoke passed. No new bench | ADR 0023 |
