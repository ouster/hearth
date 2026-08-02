# Model registry

Role → model. This file and `litellm/config.yaml` are the only places a concrete
model name may appear. Update both together, plus an ADR.

**Hardware envelope:** 64 GB unified, less ~10 GB for macOS and applications,
leaves **~54 GB for weights**. The resident set matters more than any single
model's size — see the measurement below.

## Live

| Role | Model | Size | Set | Digest | Why |
|---|---|---|---|---|---|
| `local-chat` | `qwen3:8b` | 5.2 GB | 2026-08-02 | _pending_ | General knowledge, 40K ctx. Open WebUI default |
| `local-code` | `qwen3-coder:30b` | 19 GB | 2026-08-02 | _pending_ | 30B MoE, ~3B active, 256K ctx. Runs at ~7B speed |
| `local-big` | `gpt-oss:20b` | 13 GB | 2026-08-02 | _pending_ | Reasoning. Replaced llama3.3:70b — ADR 0004 |
| `local-embed` | `nomic-embed-text` | 0.3 GB | 2026-08-01 | _pending_ | Local RAG |
| `cloud-cheap` | `gemini-3.5-flash` | — | 2026-08-01 | n/a | 1M ctx, cheap. Bulk non-sensitive work |

**Resident total: 37.5 GB of ~54 GB.** All four local models stay loaded; no
switch evicts anything.

Digest pinning is not yet implemented — roles are still tag-backed, so an
`ollama pull` can change the weights underneath one. See below.

## Dormant

Commented out in `config.yaml`. A model whose `os.environ/` key is missing fails
the **entire** config load, not just that entry, so these stay off until their
key exists.

| Role | Model | Blocked on |
|---|---|---|
| `cloud-code` | `claude-sonnet-5` | Anthropic API key — **deliberately unset**. Claude Code runs on the subscription; a Console key bills separately. Only worth opening if aider, Cursor or the laptop need Claude |
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
| `llama3.3:70b` | `local-big` | 2026-08-02 | 42 GB, could not stay resident. 440 s to first reply. ADR 0004 |
| `qwen2.5-coder:32b` | `local-code` | 2026-08-02 | Superseded by the 30B MoE at the same size |
| `qwen2.5-coder:7b` | `local-fast` | 2026-08-02 | Role retired — the MoE made a separate fast coder redundant. ADR 0005 |

Note on the last one: Qwen3-Coder has **no variant below 30B**, so
`qwen2.5-coder:7b` remained the best sub-10 GB coding model available. It went
because the role became unnecessary, not because it was outdated. If a small
dense coder appears, the role can return.

## The measurement that drove all of this

Through the gateway, one short prompt each, from cold:

| Role | Before | Time | After | Time |
|---|---|---|---|---|
| `local-code` | qwen2.5-coder:32b | 29 s | qwen3-coder:30b | **6 s** |
| `local-big` | llama3.3:70b | **440 s** | gpt-oss:20b | **5 s** |
| `cloud-cheap` | gemini-3.5-flash | 2 s | gemini-3.5-flash | 1 s |

**440 s to 5 s — not a faster model, a resident one.**

The old set needed 65.7 GB against a ~54 GB budget, so something was always
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
than the one you benched. Roles should therefore pin digests, and the auto-updater
should stage new pulls under a `candidate-` prefix rather than overwriting.

**Not yet implemented.** Until it is, a routine pull can silently change a role.

## Changing a role

`scripts/swap-role.sh <role> <model>` does steps 1–5 and reverts on failure.

1. Pull the candidate
2. `scripts/bench.sh` against the incumbent
3. Confirm it fits alongside whatever must stay resident
4. Update this table and `litellm/config.yaml` together
5. Deploy, then `audit-fallbacks.sh` and `healthcheck.sh`
6. Write an ADR in `docs/decisions/`
7. Delete the old weights only once the replacement has proven itself
