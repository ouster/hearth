# Model registry

Role → model. This file and `config/roles.tsv` are the only places a concrete
model name is written by hand. Update both together, plus an ADR. Generated
copies: Zed `display_name` labels (`scripts/zed-sync.sh`) and the key plus
weights path in `pins/digests.tsv` (`scripts/pin-digests.sh`). (Before ADR 0016
the second file was `litellm/config.yaml`.)

**Hardware envelope:** 64 GB unified. macOS caps GPU-accessible memory at ~75% above 36 GB,
so the real ceiling is **~48 GB**, not the full 64. The resident set matters more than any single
model's size — see the measurement below.

## Live — LM Studio (ADR 0016)

The LM Studio app 0.4.28 owns the server (D6). Machine-read copy:
`config/roles.tsv`.

| Role | Model key | Source | Size | Load | Set | Why |
|---|---|---|---|---|---|---|
| `local-big` | `qwen/qwen3.6-35b-a3b` | `lmstudio-community/Qwen3.6-35B-A3B-MLX-4bit` @ `0c4a20a` | 20.4 GB | 128K × 3 parallel, draft MTP | 2026-10-31 | Same base model as the Ollama-era agent; MLX 4-bit from lmstudio-community (quantisation may differ from the Ollama build). The only local chat/agent role (D1). Context raised from 64K the same day (ADR 0017): the model card asks for at least 128K so thinking holds. Native window is 262,144 |
| `local-embed` | `text-embedding-nomic-embed-text-v1.5@f16` | `nomic-ai/nomic-embed-text-v1.5-GGUF` f16 @ `0188c9b`, sha256 `f7af6f66…` | 0.3 GB | 2K | 2026-10-31 | f16 to match the Ollama-era embeddings |
| `cloud-cheap` | `gemini-3.6-flash` | Google, `ask-cloud` only | — | — | 2026-10-22 | 1M ctx, 65K output. ADR 0014 |

**Resident set:** 20.7 GB idle at 128K × 3 plus `local-embed`, measured
2026-10-31 right after reload (ADR 0017). The 64K concurrency-3 peak was
29.7 GB (`bench/results/2026-10-31-phase1`); that bench was not re-run at
128K. Both sit well under the ~48 GB ceiling, so the slot count stays 3.

`local-code` and `local-chat` were collapsed into `local-big` on 2026-10-31
(D1). The Ollama weights were deleted the same day with the rest of the old
stack. Known quality gap
against the Ollama build: 3 of 40 concurrency-bench turns picked `grep`
instead of the requested `read_file` (0 of 40 on Ollama); tracked, not
blocking.

**Weight drift:** recorded and checked — see Weight pinning below (D4).

**Bench candidate (not a role):** `qwen3.6:27b-coding-mtp-q4_K_M` on Ollama
(~18 GB) — rejected for verbosity vs `qwen3-coder:30b` (ADR 0005 era bench).

## Dormant

No keys. In the gateway era these were commented-out blocks in `config.yaml`;
after ADR 0016 a cloud role would be a `gemini` (or other explicit cloud
backend) row in `config/roles.tsv` plus an alias that passes its own key —
never a model loaded into LM Studio.

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
| `qwen3.6:35b-mlx` (Ollama) | `local-big` | 2026-10-31 | Same base model now served by LM Studio (lmstudio-community MLX 4-bit). ADR 0016 |
| `qwen3-coder:30b` | `local-code` | 2026-10-31 | Role collapsed into `local-big` (D1). ADR 0016 |
| `qwen3:8b` | `local-chat` | 2026-10-31 | Role collapsed into `local-big` (D1). ADR 0016 |
| `nomic-embed-text` (Ollama) | `local-embed` | 2026-10-31 | Same model, f16 GGUF, now on LM Studio |
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
`config/roles.tsv`, under `~/.lmstudio/models`) into `pins/digests.tsv`:
file count, bytes, newest mtime, and a sha256 over every file. Git-tracked,
so drift shows in a diff.

```bash
scripts/pin-digests.sh                  # record, after a bench you trust (~40 s)
scripts/pin-digests.sh --check          # fast; preflight runs this
scripts/pin-digests.sh --check --deep   # re-hash everything
```

Recorded 2026-10-31. The embedding file's hash matches Hugging Face's
published sha256 (`f7af6f66…`). This detects, it does not enforce — LM Studio
loads whatever is on disk.

## Changing a role

1. Download the candidate with an exact source: `lms get <hugging face URL> -y`
2. Bench it against the incumbent: `scripts/concurrency-bench.sh` and
   `bench/tasks/` (rule 5). Same settings as the last baseline
3. Check the footprint fits beside `local-embed` under the ~48 GB ceiling
4. Update this table and `config/roles.tsv` together, then `scripts/lms-load.sh`
   (which also refreshes Zed's labels via `scripts/zed-sync.sh`)
5. `scripts/tool-smoke.sh openai http://127.0.0.1:1234/v1 local-big`
6. Write an ADR in `docs/decisions/` and a row in `docs/HISTORY.md`
7. Delete the old weights only once the replacement has proven itself

`scripts/swap-role.sh <role> <model key> <weights path> [ctx] [slots]` does
steps 4–5 and reverts on failure; `scripts/bench.sh <model key>` loads a
candidate as `bench-candidate` (`--evict` if it will not fit beside
`local-big`); `scripts/pull-candidates.sh <url> …` sizes downloads against
disk and the GPU ceiling.
