# Model registry

Role → model. This file and `config/roles.tsv` are the only places a concrete
model name is written by hand. Update both together, plus an ADR. Generated
copies: Zed `display_name` labels (`scripts/zed-sync.sh`) and the key plus
weights path in `pins/digests.tsv` (`scripts/pin-digests.sh`). (Before ADR 0016
the second file was `litellm/config.yaml`.)

**Hardware envelope:** the ceiling is installed RAM minus 8 GB (ADR 0031):
**56 GB** on the 64 GB host, **40 GB** on a 48 GB host. `iogpu.wired_limit_mb`
and the oMLX guard both follow it. macOS's default GPU cap (~75% of RAM)
applies until `scripts/iogpu-wired.sh` runs. `deep-brain` evicts
`main-brain` for its session on every tier (ADR 0033). `edit-brain` runs on
a laptop's own oMLX, not on the host. The resident set matters more than any
single model's size — see the measurement below.

## Live — oMLX (ADR 0026)

oMLX serves these from `~/.hearth/models`. Machine-read copy:
`config/roles.tsv`. The `weights` directory names are the source repos.

| Role | Model key | Source | Size | Load | Set | Why |
|---|---|---|---|---|---|---|
| `main-brain` | `qwen3.6-35b-a3b-mlx` | `mlx-community/Qwen3.6-35B-A3B-OptiQ-4bit` @ `08567bc` | 22 GB | 128K × 3 parallel, no draft, **thinking on (set by `scripts/omlx.sh`)** | 2026-11-07 | MoE, ~3B active, OptiQ mixed 4/8-bit. Won the 2026-11-07 quant A/B: c3 30/30, TTFT p50 61.9 s / p95 62.1 s (tightest of lmstudio uniform-4bit, Jundot oQ4e, Unsloth UD). Tool-smoke pass. Previous uniform pin stays on disk unloaded. ADR 0035. Native window 262,144 |
| `deep-brain` | `qwen3.8-27b-mlx` | `lmstudio-community/Qwen3.8-27B-MLX-4bit` @ `6067b15` | 16.1 GB | 64K × 1, **on demand**: `ask-deep` loads it beside `main-brain` and unloads it on the way out | 2026-11-01 | Dense 27B. Best `bench/tasks` 03 answer of the three benched; ~26 tok/s and 2.5–5.5× the tokens of the 26B-A4B, so 10–24× slower. For hard one-off questions, never agent loops. Thinks by default (its template). Beside the resident, both peaked at 49.9 GB on 2026-11-01, over the old ~48 GB cap, and the resident's requests timed out during a long prefill. The cap is now 56 GB, so the two may be loaded together on 64 GB (ADR 0028). On a 48 GB host (40 GB ceiling) `ask-deep` evicts `main-brain` instead (ADR 0031). ADR 0020 |
| `edit-brain` | `sweep-next-edit-1.5b-mlx-8bit` | `sweepai/sweep-next-edit-1.5B` @ `4090165` (`sweep-next-edit-1.5b.q8_0.v2.gguf`, sha256 `1321ea5e…`), tokenizer rebuilt from the GGUF's pruned 43,839-token vocabulary (template `Qwen/Qwen2.5-Coder-1.5B` @ `df3ce67`), converted to MLX 8-bit at `~/.hearth/models/hearth/sweep-next-edit-1.5B-MLX-8bit` | 1.4 GB | 8K × 2, **edit**: laptop oMLX only, `/v1/completions`, greedy, 512 max tokens | 2026-11-07 | Editor edit prediction (Zed `open_ai_compatible_api`, prompt format `sweep`). Apache 2.0, Qwen2.5-Coder base. Laptop bench 2026-11-07: p50 350 / p95 398 ms, 24/30 (misses `02-add-field`). Host alone p95 281 ms; beside c3 p95 5747 ms and `main-brain` TTFT p95 89.7 s — **host does not load it** (ADR 0033 amend). Paid Zed Zeta is a separate cloud opt-in (`docs/IDES.md`) |
| `cloud-cheap` | `gemini-3.6-flash` | Google, laptop `ask-cloud` only (client-only, ADR 0038) | — | — | 2026-10-22 | 1M ctx, 65K output. ADR 0014 |

**Resident set:** OptiQ c3 tool gate 30/30 at 128K × 3, ~30K-token prompts
(`bench/results/2026-11-07-1542-concurrency-c3-optiq`; footprint probe
returned 0 that run — re-measure if needed). The previous uniform-4bit
resident peaked at 34.0 GB
(`bench/results/2026-11-06-2012-concurrency-c3-qwen3.6`). Loaded beside
`deep-brain` was not re-measured; the last combined peak was 49.9 GB with
the smaller resident (ADR 0028).

**Thinking is set by `scripts/omlx.sh`.** `main-brain` gets `enable_thinking`
and the qwen reasoning parser. Sampling follows the weights' generation
config: temperature 1.0, top-k 20, top-p 0.95, repetition penalty 1.0. Zed
also pins `temperature: 1.0` for `main-brain` in `agent.model_parameters`.
The previous resident looped in thinking at a lower temperature (Zed agent
turns, 2026-11-01); that sampling does not follow the role.

`scripts/omlx.sh up` writes those settings again. `scripts/healthcheck.sh` fails if
`main-brain` returns no `reasoning_content` or leaks thought markers into the
answer. Without thinking it answered a simple change sum wrongly three times.

`local-code` and `local-chat` were collapsed into `local-big` (now `main-brain`, ADR 0021) on 2026-10-31
(D1). The Ollama weights were deleted the same day with the rest of the old
stack.

**Weight drift:** recorded and checked — see Weight pinning below (D4).

**Bench candidate (not a role):** `qwen3.6:27b-coding-mtp-q4_K_M` on Ollama
(~18 GB) — rejected for verbosity vs `qwen3-coder:30b` (ADR 0005 era bench).

## Tiers (ADR 0032)

`config/roles.tsv` column 9, `min_ram`: per role, a host serves the row with
the largest `min_ram` at or below its RAM. `HEARTH_RAM_GB` overrides the
detected size. Ceiling is RAM minus 8 (ADR 0031).

| RAM | Ceiling | `main-brain` | `deep-brain` | Status |
|---|---|---|---|---|
| < 48 GB | — | none: `omlx.sh up` refuses | — | no tier benched |
| 48 GB and up | RAM − 8 | `qwen3.6-35b-a3b-mlx`, 128K × 3 | `qwen3.8-27b-mlx`, **swap** | live on 64 GB. The same row is what a 48 GB host loads (`min_ram` 48); a c3 on 48 GB hardware is still outstanding: 30/30, peak ≤ 36 GB, host's `\.omlx/` matcher. `edit-brain` is laptop-only (ADR 0033 amend) |

### Candidates by RAM (unbenched)

Not roles. Each needs `bench/tasks` and `scripts/concurrency-bench.sh` on
that hardware before it gets a row (rule 5). Web search, 2026-11-07; 24 GB row
added 2026-11-08 (blogs, unverified; check tool calling with oMLX's parser). Sources
are mostly blogs, Hugging Face cards and leaderboards, and they often
disagree: sizes are as reported unless marked *(repo)*, which means measured
here. Usable = RAM minus 8 (ADR 0031); weights plus KV cache must fit under
it. *Agent* = MoE with ~3–4B active, for resident tool loops. *Deep* =
slower and stronger, for one-off questions.

**Shortlist to bench first**

| RAM (usable) | Agent | Deep | Load |
|---|---|---|---|
| 24 GB (16) | gpt-oss-20b (MXFP4, ~12–13 GB; most-cited small MoE with tool calling). Alternative: Devstral Small 2 24B at 4-bit (dense, slow) | none beside it | — |
| 32 GB (24) | Gemma 4 26B-A4B (≈15 GB 4-bit per blogs; ran here as the resident, c3 peak 25.2 GB, ADR 0019) | Devstral Small 2 24B or Qwen3.8-27B | swap |
| 48 GB (40) | Qwen3.6 35B-A3B (tier row) | Qwen3.8-27B (tier row) | swap |
| 64 GB (56) | Qwen3.6 35B-A3B (tier row); alternative Qwen3-Coder-Next 80B-A3B with no deep beside | Qwen3.8-27B (tier row) | beside |
| 128 GB (120) | Qwen3.6 35B-A3B | Qwen3.5-122B-A10B or gpt-oss-120b | beside (~109 GB with the 122B, tight) |
| 256 GB (248) | Qwen3.6 35B-A3B | DeepSeek V4 Flash | beside |
| 512 GB (504) | Qwen3.6 35B-A3B | MiniMax M3 (beside) or GLM-5.3 (swap) | see below |

**Quant recipe A/B (same bases as live roles)**

Not new families — alternate MLX quants of the incumbent bases, recorded
2026-11-07 from a web scan (`mlx-alt-weights-research` canvas). Goal: see
whether a mixed-precision recipe beats the live `lmstudio-community` MLX-4bit
pins on `bench/tasks`, tool-smoke, and `scripts/concurrency-bench.sh` under
the RAM-minus-8 ceiling. Download under `~/.hearth/models/<weights>` (HF
org/name). Do **not** point `roles.tsv` at these until a bench wins (rule 5).

| Priority | Challenges | Weights path (HF) | Kind | Size (card) | Why |
|---|---|---|---|---|---|
| 1 | `main-brain` | `Jundot/Qwen3.6-35B-A3B-oQ4e-mtp` | oQe mixed (oMLX 0.7.3), MTP + vision | ~22 GB | oMLX-author quant; r/oMLX prefers oQ for this server |
| 2 | `main-brain` | `unsloth/Qwen3.6-35B-A3B-UD-MLX-4bit` | Unsloth UD dynamic 4-bit | ~23 GB class | Often ranked above native mlx-community 4-bit |
| 3 | `main-brain` | `mlx-community/Qwen3.6-35B-A3B-OptiQ-4bit` | OptiQ mixed 4/8, MTP sidecar | ~22 GB | Sensitivity-aware; Capability Score claims vs uniform-4bit |
| control | `main-brain` | `mlx-community/Qwen3.6-35B-A3B-4bit` | uniform mlx-vlm 4-bit | 20.4 GB | Same size class as the live pin — publisher/control twin |
| 1 | `deep-brain` | `Jundot/Qwen3.6-27B-oQ4e-mtp` | oQ4e imatrix + MTP | ~17 GB | Dense 27B class; their table edged mlx-lm 4bit avg |
| later | either | `nightmedia/*-qx64-hi-mlx` (matching base) | Deckard hybrid qx | varies | Obscure hybrid; tool-smoke first |
| catalog | either | `majentik/garden` TurboQuant / RotorQuant tiers | smoke-gated | varies | Only after a named repo is picked; verify text vs full tower |

Live pins: `mlx-community/Qwen3.6-35B-A3B-OptiQ-4bit` (`main-brain`,
ADR 0035), `lmstudio-community/Qwen3.8-27B-MLX-4bit` (`deep-brain`). The
uniform lmstudio, Jundot oQ4e, and Unsloth UD leaves stay on disk unloaded.
Skip GGUF orgs for oMLX (no GGUF→MLX path).

**Alternatives by tier**

| Tier | Model | Kind | 4-bit size | Notes |
|---|---|---|---|---|
| 32 | Gemma 4 26B-A4B | agent | ~15 GB *(repo)* | Laptop c3 30/30, peak 22 GB (`[o]mlx` matcher) |
| 32 | Qwen3.6 35B-A3B | agent | 20.4 GB *(repo)* | Only ~32K × 1 at this ceiling |
| 32 | GLM-4.7-Flash 30B-A3B | agent | ~19 GB | Little data |
| 32 | Nemotron 3.5 Lightning 31.6B-A3.6B | agent | 17.8–23 GB | SWE-bench Verified 51.6 vs 70.1 for Qwen3.6 35B-A3B |
| 32 | Qwen3-Coder 30B-A3B | agent | ~22 GB in memory | Older generation |
| 32 | Devstral Small 2 24B | deep | ~14 GB est. | Apache 2.0. KV cache large at long context |
| 32 | Qwen3.8-27B | deep | 16.1 GB *(repo)* | Terminal-Bench 2.1 73.0. Here: ~26 tok/s, verbose; laptop c3 20/30 timeouts |
| 32 | Gemma 4 31B, Qwen3.6-27B | deep | ~17 GB | Dense |
| 48 | Gemma 4 26B-A4B | agent | ~15 GB *(repo)* | Fallback if Qwen3.6 exceeds 36 GB on 48 GB |
| 48 | Devstral Small 2, Gemma 4 31B, Qwen3.6-27B | deep | 14–17 GB | Swap alternatives to Qwen3.8-27B |
| 64 | Qwen3-Coder-Next 80B-A3B | agent | ~46 GB | SWE-bench Verified 70.6 (vendor). ~10 GB left for KV; no deep beside |
| 64 | gpt-oss-120b, Nemotron 3 Super 120B-A12B | deep | 64–72 GB | Do not fit; need 96 GB+ |
| 128 | Qwen3.5-122B-A10B | deep or agent | 63–75 GB peak | oMLX bench, M3 Max: 42 tok/s, 63.4 GB. ~65 tok/s reported on M5 Max |
| 128 | gpt-oss-120b | deep | ~65 GB | Reported as the most reliable open-weight tool caller |
| 128 | Nemotron 3 Super 120B-A12B | deep | 64–72 GB | |
| 128 | Devstral 2 123B | deep | ~75 GB | SWE-bench Verified 72.2. Dense, so slow on a Mac. No MLX build found |
| 128 | Qwen3-Coder-Next 80B-A3B | agent | ~46 GB | Pairs with Qwen3.8-27B 8-bit (~29 GB) |
| 128 | Qwen3.8-Flash-Next 125B-A6B | deep | 81 GB at 2-bit only | Licence limits some commercial use |
| 256 | DeepSeek V4 Flash | deep | 145–167 GB | oMLX on M3 Ultra 256 GB: 26 tok/s, 42 with MTP. ~75 tok/s prefill, so ~400 s for a 30K prompt |
| 256 | GLM-5.3-Flash 320B-A18B | deep | 182–204 GB | MIT. Too big beside the resident: swap |
| 256 | Qwen3.5-397B-A17B | deep | ~220 GB est. | No Mac bench found |
| 256 | MiniMax M3 427B-A23B | deep | ~240 GB | SWE-bench Verified 80.5. No room for KV under 248 |
| 512 | MiniMax M3 / M3.1 Flash | deep | ~240 / ~249 GB peak | Fits beside the resident |
| 512 | GLM-5.3 753B-A40B | deep | 418 GB | One source only; other searches find only GLM-5.3-Flash. Confirm it exists. Swap |
| 512 | DeepSeek V4 Flash | deep | 145–167 GB | Fits with wide margin |
| 512 | Kimi K3, Muse Spark Open, DeepSeek V4 Pro | — | 1.56 TB / 533 GB / conflicting | Do not fit one 512 GB host |

`main-brain` stays a ~3B-active MoE at every tier: wall time is set by active
parameters and tokens emitted (see *Verbosity, not speed*). More RAM buys a
better `deep-brain`, keeps it loaded, and adds slots. Large `deep-brain`
models prefill slowly; they suit short hard questions, not long context.

### Building `edit-brain` (ADR 0033)

On the host, or on a laptop for its own oMLX. Downloads ~1.5 GB of GGUF
and the base model's tokenizer files into `~/.hearth/models/.src`.

```bash
client/edit-model.sh convert sweepai/sweep-next-edit-1.5B 409016591c6c1a94f545f22328a85a3516118f34 \
  sweep-next-edit-1.5b.q8_0.v2.gguf Qwen/Qwen2.5-Coder-1.5B df3ce67c0e24480f20468b6ef2894622d69eb73b
```

Then pin on the host (`scripts/pin-digests.sh`) so digests stay shared. Serve
and bench on a laptop: `client/edit-model.sh laptop-up`, then
`client/edit-model.sh bench`. Host `omlx.sh up` does not load `edit-brain`.

### Edit prediction candidates (unbenched)

For Zed's `open_ai_compatible_api` edit prediction provider (`docs/IDES.md`).
No role yet: a `edit-brain` row needs a latency bench, an ADR, and a check
that predictions do not starve agent turns of oMLX's request slots. Web
search, 2026-11-07. Scores are each vendor's own benchmark and are not
comparable across vendors.

| Model | Size | Zed prompt format | Notes |
|---|---|---|---|
| **Sweep Next-Edit 1.5B** (`sweepai/sweep-next-edit-1.5B`) — now `edit-brain` | ~1.6 GB at Q8; under 1 GB at 4-bit | `sweep` | First pick. Apache 2.0, Qwen2.5-Coder base, 8K context. Sweep's benchmark: 67.8% against 43.3% for Zed's hosted model. Under 500 ms on a laptop with speculative decoding (vendor). No MLX build found; would be converted with `mlx_lm.convert` and pinned |
| Sweep Next-Edit v2 7B | ~4.5 GB at 4-bit | `sweep` | Higher quality (v1 7B scored 81.3% on the same benchmark). Community MLX fp16 conversion exists. Fits 48 GB beside `main-brain` only just |
| Zeta 2.1 (`zed-industries/zeta-2.1`) | 8B (Seed-Coder base), ~5 GB at 4-bit | `zeta2_1` | Zed's own model, Zed's native prompt format. Community MLX 4-bit conversion |
| Instinct (`continuedev/instinct`) | 7B (Qwen2.5-Coder) | none built in | Apache 2.0. Sweep reports it repeats itself ~10% of the time. Not a fit for Zed's formats |
| Qwen2.5-Coder 1.5B base | ~1 GB at 4-bit | `qwen` | Plain fill-in-the-middle, not next-edit. Baseline only |

## Dormant

Four roles, no keys: `cloud-code`, `cloud-frontier`, `cloud-frontier-direct`, `cloud-frontier-fast`. In the gateway era these were commented-out blocks in `config.yaml`;
after ADR 0016 a cloud role would be a `gemini` (or other explicit cloud
backend) row in `config/roles.tsv` plus an alias that passes its own key —
never an `omlx` row. A remote model on `:1234` would break the boundary.

| Role | Model | Blocked on |
|---|---|---|
| `cloud-code` | `claude-sonnet-5` | Anthropic API key — **deliberately unset**. A Console key bills separately from any Claude subscription. Only worth opening if aider, Zed or a laptop should reach Claude through the gateway |
| `cloud-frontier` | `kimi-k3` via OpenRouter | OpenRouter key. Primary frontier route |
| `cloud-frontier-direct` | `kimi-k3` via Moonshot | Moonshot key. Same price, best K3 caching |
| `cloud-frontier-fast` | `kimi-k3` via Fireworks | Fireworks key. Dearest; throughput or LoRA only |


There is **no local Kimi K3**. The smallest community quant is ~540 GB at 1.56
bits, and Ollama cannot load it — support is an open llama.cpp pull request.
Frontier is cloud-only by necessity, which is what these roles are for.

## Retired

| Model | Was | Removed | Why |
|---|---|---|---|
| `gemma-4-26b-a4b-it-qat-mlx` (`lmstudio-community/gemma-4-26B-A4B-it-QAT-MLX-4bit` @ `aa5e2e5`) | `main-brain` | 2026-11-06 | Resident from ADR 0024. Short tasks finished sooner and the weights are smaller. Lost the 2026-11-06 long-context answer and the c3 prefill (TTFT p50 79.2 s, peak 31.0 GB). Weights kept. ADR 0030 |
| `qwen3.6:35b-mlx` (Ollama) | `local-big` | 2026-10-31 | Ollama build of the same 35B-A3B, now `main-brain` again. ADR 0016, 0030 |
| `qwen3-coder:30b` | `local-code` | 2026-10-31 | Role collapsed into `local-big` (D1). ADR 0016 |
| `qwen3:8b` | `local-chat` | 2026-10-31 | Role collapsed into `local-big` (D1). ADR 0016 |
| `nomic-embed-text` (Ollama, then an f16 GGUF) | `local-embed` | 2026-11-01 | Nothing called it. Healthcheck was the only request. ADR 0018 |
| `gpt-oss:20b` | `local-big` | 2026-09-06 | Slower tool-smoke than the Qwen3.6 agent. ADR 0012, then 0013 |
| `llama3.3:70b` | `local-big` | 2026-08-02 | 42 GB, could not stay resident. 440 s to first reply. ADR 0004 |
| `qwen2.5-coder:32b` | `local-code` | 2026-08-02 | Superseded by the 30B MoE at the same size |
| `qwen2.5-coder:7b` | `local-fast` | 2026-08-02 | Role retired — the MoE made a separate fast coder redundant. ADR 0005 |

Note on the last one: Qwen3-Coder has **no variant below 30B**, so
`qwen2.5-coder:7b` remained the best sub-10 GB coding model available. It went
because the role became unnecessary, not because it was outdated. If a small
dense coder appears, the role can return.

## Verbosity, not speed

Second measurement, from the first real bench run:

| Model | tokens over 4 tasks | wall clock | avg tok/s |
|---|---|---|---|
| `qwen3-coder:30b` | 1,218 | 11.2 s | 108.8 |
| `gpt-oss:20b` | 4,466 (3.7x) | 47.6 s | 93.8 |
| `qwen3:8b` (thinking on) | 13,840 (11.4x) | 181.4 s | 76.3 |

Throughput barely moves — 65–120 tok/s across everything, because the machine
is memory-bandwidth bound. **Wall clock is set by how many tokens a model emits,
not how fast.** A hybrid reasoning model can be the slowest role while being the
smallest.

Disabling thinking on `local-chat` took it from 2,370 tokens / 29.7 s to
**386 tokens / 5.1 s** through the gateway. See ADR 0006.

## The measurement that drove all of this

Through the gateway, one short prompt each, from cold:

| Role | Before | Time | After | Time |
|---|---|---|---|---|
| `local-code` | qwen2.5-coder:32b | 29 s | qwen3-coder:30b | **6 s** |
| `local-big` | llama3.3:70b | **440 s** | gpt-oss:20b | **5 s** |
| `cloud-cheap` | gemini-3.5-flash | 2 s | gemini-3.5-flash | 1 s |

**440 s to 5 s — not a faster model, a resident one.**

The old set needed 65.7 GB against a ~48 GB GPU ceiling, so something was always
evicted and reaching for `local-big` meant reloading 42 GB from disk. That
Ollama-era set totalled 37.5 GB. The live resident set is the figure at the
top of this file.

The lesson worth keeping: on a fixed-memory machine the **resident set** matters
more than any individual model's quality. A 70B that evicts your coding model is
slower in practice than a 20B that never leaves RAM, whatever the benchmarks say.
MoE architectures are what make the newer set fit — ~3B active parameters gives
near-30B reasoning at 7B speed.

Disk: 63 GB before, ~37 GB after.

## Cost reference

Verified 2026-08-01. LiteLLM auto-syncs its own cost map; this table is for human
decisions and does **not** update itself. Re-check before relying on it.

| Kimi K3 via | $/M in | $/M out | Note |
|---|---|---|---|
| Moonshot (direct) | 3.00 | 15.00 | source of truth |
| OpenRouter | 3.00 | 15.00 | ~92% cache hit reported → effective input ≈ 0.52 |
| Fireworks serverless | 3.30 | 16.50 | 10% dearer; buys throughput and LoRA |

- **Fireworks is the dearest of the three.** This stack originally defaulted to it
  because it was the provider that came to mind first, not because it won on
  price. That is exactly the failure mode this registry exists to catch.
- **Output price is the one that bites** — it compounds through agentic loops.

## Weight pinning (D4)

`scripts/pin-digests.sh` hashes each role's `weights` path (column 6 of
`config/roles.tsv`, under `~/.hearth/models`) into `pins/digests.tsv`:
file count, bytes, newest mtime, and a sha256 over every file. Git-tracked,
so drift shows in a diff.

```bash
scripts/pin-digests.sh                  # record, after a bench you trust (~40 s)
scripts/pin-digests.sh --check          # fast; preflight runs this
scripts/pin-digests.sh --check --deep   # re-hash everything
```

Recorded 2026-10-31. This detects, it does not enforce — oMLX loads
whatever is on disk. The embedding pin was removed with the role (ADR 0018).

## Changing a role

1. Put the candidate weights under `~/.hearth/models` at the source path in
   this file
2. Bench it against the incumbent: `scripts/concurrency-bench.sh` and
   `bench/tasks/` (rule 5). Same settings as the last baseline
3. Check the footprint fits under the ceiling (RAM minus 8: 56 GB on 64, 40 GB on 48) with `main-brain` already resident
4. Update this table and `config/roles.tsv` together (row at the tier's `min_ram`, ADR 0032), then `scripts/omlx.sh up`
   and `scripts/zed-sync.sh`
5. `scripts/tool-smoke.sh openai http://127.0.0.1:1234/v1 main-brain`
6. Write an ADR in `docs/decisions/` and a row in `docs/HISTORY.md`
7. Delete the old weights only once the replacement has proven itself

`scripts/bench.sh` runs `bench/tasks` against a resident role. It does not
load a candidate by itself.
