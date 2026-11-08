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
| 2026-11-01 | Notify when a prompt is trimmed to fit the context window | The server drops the middle and still returns a normal reply, so an agent thread repeats work it can no longer see | Notification names the role, prompt size, and tokens dropped. The turn still runs | `scripts/context-watch.sh` |
| 2026-11-04 | oMLX trial on `:1234` with RAM and SSD prefix cache | Same 30,260-token prompt: 23.4 s then 3.0 s to the first token. A changed prefix stayed at ~25 s. Thinking parsed, tool-smoke passed. Footprint 24 GB. A pasted laptop token is a sub-key: it can call the model and cannot log in as admin. Login boot still starts LM Studio | Trial only | ADR 0025, `scripts/omlx-try.sh` |
| 2026-11-04 | Boot oMLX; resident weights copied to `~/.hearth/models` | Repeat of the same 30,244-token prompt: 26.1 s then 4.6 s. Cold prefill matches the 2026-11-01 LM Studio run. `local-deep` still needs LM Studio and the port | Login serves oMLX. `omlx-try.sh down` is the rollback | ADR 0026, `bench/results/2026-11-04-2150-omlx-cache` |
| 2026-11-04 | `local-deep` weights copied; GPU wired limit raised to 56 GB | `ask-deep` swaps inside oMLX. The two roles are still not loaded together. 62259 MB was left unused because it leaves ~3 GB for macOS | Kept | ADR 0027 |
| 2026-11-04 | Drop the LM Studio rollback; load both roles together | `down` stops oMLX and leaves the port empty. `local-deep` loads beside `local-main`. The 49.9 GB peak from 2026-11-01 fits under the 56 GB cap | Kept | ADR 0028 |
| 2026-11-04 | Rename the serving script | `scripts/omlx.sh up` and `down`. Login boot still runs `up` | Kept | — |

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
| 2026-11-01 | `local-main` restored to the 26B-A4B | The looping thread was already past the context window on both residents; a trim is now notified | Bench winner restored, 128K × 3, no draft. Tool-smoke passed. No new bench | ADR 0024 |
| 2026-11-06 | `local-main` returned to the 35B-A3B | Faster decode and the better long-context answer; short tasks emit 2.2× the tokens. c3 30/30, TTFT p50 60.7 s vs 79.2 s, peak 34.0 GB vs 31.0 GB | Adopted, 128K × 3, no draft | ADR 0030, `2026-11-06-1801`, `2026-11-06-1956-concurrency-c3-local-main`, `2026-11-06-2012-concurrency-c3-qwen3.6` |
| 2026-11-07 | GPU ceiling sized from RAM; `local-deep` swaps below 64 GB | A 48 GB Mac should host. 34.0 GB resident fits a 40 GB ceiling; the pair does not | Adopted. Not yet benched on 48 GB | ADR 0031 |
| 2026-11-07 | Roles tiered by RAM (`min_ram` column; load `beside`/`swap`) | One role set could not serve 32–512 GB hosts; co-load is per-tier data | Adopted. Tiers 48 and 64 have rows; other sizes are unbenched candidates in MODELS.md | ADR 0032 |
| 2026-11-07 | Alternate MLX quant recipes listed as bench candidates for the live roles | Same bases, different publishers (oQe, UD, OptiQ, control twin); not roles until they win a bench | Candidates only — `docs/MODELS.md` | — |
| 2026-11-07 | `local-edit` for editor edit prediction; `local-deep` swaps on 64 GB | Zed's default prediction sends file text to Zed; a 1.5B next-edit model converted from GGUF to MLX 8-bit | Adopted on laptops. Host alone p95 281 ms; beside c3 p95 5747 ms — host does not load it. Paid Zed Zeta remains a cloud opt-in | ADR 0033, `2026-11-07-0905-edit-laptop`, `2026-11-07-0929-edit`, `2026-11-07-0930-edit`, `2026-11-07-0930-concurrency-c3` |
| 2026-11-07 | Quant A/B for `local-main`: Jundot oQ4e, Unsloth UD, OptiQ-4bit vs uniform MLX-4bit | All 30/30 tools; OptiQ TTFT p95 62.1 s (tightest) | OptiQ adopted as `local-main` | ADR 0035, `2026-11-07-0754-concurrency-c3-jundot-oq4e`, `2026-11-07-1427-concurrency-c3-unsloth-ud`, `2026-11-07-1542-concurrency-c3-optiq` |
| 2026-11-08 | VS Code and Cline on trial beside Zed, with a PreToolUse loop guard | Operator wants a customisable agent flow and loop prevention. oMLX refuses oversized prompts, so the ADR 0024 trim loop is gone. The guard targets repeated tool calls and a per-session budget | Trial. Guard self-test passes. `tool-smoke` PASS through a laptop tunnel (turn 1: 2 reads, turn 2: write with `<`). Cline Desktop and PyCharm: tool loop pass. The global loop guard stopped the third identical read in both. No-fallback check passed (ConnectionRefused). Composio connector beta found and turned off. VS Code 1.144.1: the guard refused the third identical read | ADR 0036 |
