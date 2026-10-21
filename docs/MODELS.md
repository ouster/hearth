# Model registry

Role → model. This file and `litellm/config.yaml` are the only places a concrete
model name may appear. Update both together, plus an ADR.

**Hardware envelope:** 64 GB unified. macOS caps GPU-accessible memory at ~75% above 36 GB,
so the real ceiling is **~48 GB**, not the full 64. The resident set matters more than any single
model's size — see the measurement below.

## Live

| Role | Model | Size | Set | Digest | Why |
|---|---|---|---|---|---|
| `local-chat` | `qwen3:8b` | 5.2 GB | 2026-08-02 | `500a1f067a9f` | General knowledge, **40K** ctx (native). **thinking off** — ADR 0006 |
| `local-code` | `qwen3-coder:30b` | 18 GB | 2026-08-02 | `06c1097efce0` | 30B MoE, ~3B active. Native 256K; **runtime 64K** — ADR 0010 |
| `local-big` | `qwen3.6-35b-4bit` | ~20 GB | 2026-09-06 | n/a (MLX) | Agent / reasoning via **Rapid-MLX** `:8000`. ADR 0012 |
| `local-embed` | `nomic-embed-text` | 0.3 GB | 2026-08-01 | `0a109f422b47` | Local RAG |
| `cloud-cheap` | `gemini-3.5-flash` | — | 2026-08-01 | n/a | 1M ctx, cheap. Bulk non-sensitive work |

**Ollama disk:** ~23.5 GB across chat, code, embed (`ollama list`).
**MLX disk:** ~20 GB for `qwen3.6-35b-4bit` (Rapid-MLX cache). Only one Ollama
model stays GPU-resident (`OLLAMA_MAX_LOADED_MODELS=1`, ADR 0011); Rapid-MLX
holds `local-big` separately on `:8000`.

Context windows and capability flags also live in each role's `model_info`
block in `litellm/config.yaml`, so `/model/info` (and tools like
`zed-litellm`) stay honest — ADR 0009. **Runtime context is capped at 64K**
for `local-code` / `local-big` (Ollama `num_ctx` or MLX client limits) so KV
does not blow the ~48 GB envelope — ADR 0010.

**Bench candidate (not a role):** `qwen3.6:27b-coding-mtp-q4_K_M` on Ollama
(~18 GB) — rejected for verbosity vs `qwen3-coder:30b` (ADR 0005 era bench).

**Retired from `local-big`:** `gpt-oss:20b` on Ollama — replaced by MLX
`qwen3.6-35b-4bit` after tool-smoke (ADR 0012). Weights may remain on disk.

Digests are **recorded and drift-checked** in `pins/digests.tsv`, not enforced —
see below. Re-record with `scripts/pin-digests.sh` after any role change you trust.

## Dormant

Commented out in `config.yaml`. A model whose `os.environ/` key is missing fails
the **entire** config load, not just that entry, so these stay off until their
key exists.

| Role | Model | Blocked on |
|---|---|---|
| `cloud-code` | `claude-sonnet-5` | Anthropic API key — **deliberately unset**. A Console key bills separately from any Claude subscription. Only worth opening if aider, Zed or a laptop should reach Claude through the gateway |
| `cloud-frontier` | `kimi-k3` via OpenRouter | OpenRouter key. Primary frontier route |
| `cloud-frontier-direct` | `kimi-k3` via Moonshot | Moonshot key. Same price, best K3 caching |
| `cloud-frontier-fast` | `kimi-k3` via Fireworks | Fireworks key. Dearest; throughput or LoRA only |

To enable one: uncomment its block in `config.yaml`, add the key to
`~/.config/litellm/env`, add the role to `CLOUD_ALL` in `scripts/create-keys.sh`,
re-run that script, then `audit-fallbacks.sh` and `healthcheck.sh`.

There is **no local Kimi K3**. The smallest community quant is ~540 GB at 1.56
bits, and Ollama cannot load it — support is an open llama.cpp pull request.
Frontier is cloud-only by necessity, which is what these roles are for.

## Retired

| Model | Was | Removed | Why |
|---|---|---|---|
| `gpt-oss:20b` | `local-big` | 2026-09-06 | Superseded by MLX `qwen3.6-35b-4bit` — faster tool smoke, same pass. ADR 0012 |
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
evicted and reaching for `local-big` meant reloading 42 GB from disk. The current
set totals 37.5 GB and stays put.

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

## Digest pinning

Ollama tags are mutable pointers, not versions. `ollama pull qwen3-coder:30b`
fetches whatever that tag points at today, which may be a different quantisation
than the one you benched, and nothing warns you.

Ollama offers **no way to bind a tag to a digest in the model name**, so pinning
here is record-and-detect rather than enforce:

```bash
scripts/pin-digests.sh           # record, after a bench you trust
scripts/pin-digests.sh --check   # compare live against recorded
```

`pins/digests.tsv` is git-tracked, so drift shows up in a diff.
`scripts/preflight.sh` runs the check and fails on a mismatch. That is weaker
than true pinning; the honest framing is that you will be told, not stopped.

## Changing a role

`scripts/swap-role.sh <role> <model>` does steps 1–5 and reverts on failure.

1. Pull the candidate
2. `scripts/bench.sh` against the incumbent
3. Confirm it fits alongside whatever must stay resident
4. Update this table and `litellm/config.yaml` together
5. Deploy, then `audit-fallbacks.sh` and `healthcheck.sh`
6. Write an ADR in `docs/decisions/`
7. Delete the old weights only once the replacement has proven itself
