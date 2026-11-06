# Model registry

Role → model. This file and `config/roles.tsv` are the only places a concrete
model name is written by hand. Update both together, plus an ADR. Generated
copies: Zed `display_name` labels (`scripts/zed-sync.sh`) and the key plus
weights path in `pins/digests.tsv` (`scripts/pin-digests.sh`). (Before ADR 0016
the second file was `litellm/config.yaml`.)

**Hardware envelope:** the ceiling is installed RAM minus 8 GB (ADR 0031):
**56 GB** on the 64 GB host, **40 GB** on a 48 GB host. `iogpu.wired_limit_mb`
and the oMLX guard both follow it. macOS's default GPU cap (~75% of RAM)
applies until `scripts/iogpu-wired.sh` runs. `local-deep` loads beside
`local-main` only at a 56 GB ceiling; below that it evicts it. The resident set matters more than any single
model's size — see the measurement below.

## Live — oMLX (ADR 0026)

oMLX serves these from `~/.hearth/models`. Machine-read copy:
`config/roles.tsv`. The `weights` directory names are the source repos.

| Role | Model key | Source | Size | Load | Set | Why |
|---|---|---|---|---|---|---|
| `local-main` | `qwen3.6-35b-a3b-mlx` | `lmstudio-community/Qwen3.6-35B-A3B-MLX-4bit` @ `0c4a20a` | 20.4 GB | 128K × 3 parallel, no draft, **thinking on (set by `scripts/omlx.sh`)** | 2026-11-06 | MoE, ~3B active, 4-bit. Returned after the 2026-11-06 benches: faster decode, the better long-context answer, c3 30/30 with TTFT p50 60.7 s against the previous resident's 79.2 s. Short tasks emit about 2.2× the tokens. Peak 34.0 GB. ADR 0030. Native window 262,144 |
| `local-deep` | `qwen3.8-27b-mlx` | `lmstudio-community/Qwen3.8-27B-MLX-4bit` @ `6067b15` | 16.1 GB | 64K × 1, **on demand**: `ask-deep` loads it beside `local-main` and unloads it on the way out | 2026-11-01 | Dense 27B. Best `bench/tasks` 03 answer of the three benched; ~26 tok/s and 2.5–5.5× the tokens of the 26B-A4B, so 10–24× slower. For hard one-off questions, never agent loops. Thinks by default (its template). Beside the resident, both peaked at 49.9 GB on 2026-11-01, over the old ~48 GB cap, and the resident's requests timed out during a long prefill. The cap is now 56 GB, so the two may be loaded together on 64 GB (ADR 0028). On a 48 GB host (40 GB ceiling) `ask-deep` evicts `local-main` instead (ADR 0031). ADR 0020 |
| `cloud-cheap` | `gemini-3.6-flash` | Google, `ask-cloud` only | — | — | 2026-10-22 | 1M ctx, 65K output. ADR 0014 |

**Resident set:** concurrency-3 peak 34.0 GB at 128K × 3, ~30K-token prompts
(`bench/results/2026-11-06-2012-concurrency-c3-qwen3.6`, oMLX process
footprint). The previous resident the same day peaked at 31.0 GB
(`bench/results/2026-11-06-1956-concurrency-c3-local-main`). Loaded beside
`local-deep` was not re-measured; the last combined peak was 49.9 GB with
the smaller resident (ADR 0028).

**Thinking is set by `scripts/omlx.sh`.** `local-main` gets `enable_thinking`
and the qwen reasoning parser. Sampling follows the weights' generation
config: temperature 1.0, top-k 20, top-p 0.95, repetition penalty 1.0. Zed
also pins `temperature: 1.0` for `local-main` in `agent.model_parameters`.
The previous resident looped in thinking at a lower temperature (Zed agent
turns, 2026-11-01); that sampling does not follow the role.

`scripts/omlx.sh up` writes those settings again. `scripts/healthcheck.sh` fails if
`local-main` returns no `reasoning_content` or leaks thought markers into the
answer. Without thinking it answered a simple change sum wrongly three times.

`local-code` and `local-chat` were collapsed into `local-big` (now `local-main`, ADR 0021) on 2026-10-31
(D1). The Ollama weights were deleted the same day with the rest of the old
stack.

**Weight drift:** recorded and checked — see Weight pinning below (D4).

**Bench candidate (not a role):** `qwen3.6:27b-coding-mtp-q4_K_M` on Ollama
(~18 GB) — rejected for verbosity vs `qwen3-coder:30b` (ADR 0005 era bench).

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
| `gemma-4-26b-a4b-it-qat-mlx` (`lmstudio-community/gemma-4-26B-A4B-it-QAT-MLX-4bit` @ `aa5e2e5`) | `local-main` | 2026-11-06 | Resident from ADR 0024. Short tasks finished sooner and the weights are smaller. Lost the 2026-11-06 long-context answer and the c3 prefill (TTFT p50 79.2 s, peak 31.0 GB). Weights kept. ADR 0030 |
| `qwen3.6:35b-mlx` (Ollama) | `local-big` | 2026-10-31 | Ollama build of the same 35B-A3B, now `local-main` again. ADR 0016, 0030 |
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
3. Check the footprint fits under the ceiling (RAM minus 8: 56 GB on 64, 40 GB on 48) with `local-main` already resident
4. Update this table and `config/roles.tsv` together, then `scripts/omlx.sh up`
   and `scripts/zed-sync.sh`
5. `scripts/tool-smoke.sh openai http://127.0.0.1:1234/v1 local-main`
6. Write an ADR in `docs/decisions/` and a row in `docs/HISTORY.md`
7. Delete the old weights only once the replacement has proven itself

`scripts/bench.sh` runs `bench/tasks` against a resident role. It does not
load a candidate by itself.
