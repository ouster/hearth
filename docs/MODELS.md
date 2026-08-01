# Model registry

Role → model. This file and `litellm/config.yaml` are the only places a concrete
model name may appear. Update both together, plus an ADR.

Hardware envelope: 64 GB unified, **~48 GB budget for weights**.

## Current

| Role | Model | Size | Set | Pinned digest | Why |
|---|---|---|---|---|---|
| `local-fast` | `qwen2.5-coder:7b` | 4.7 GB | 2026-08-01 | _pending Phase 4_ | inherited, fine for its job |
| `local-code` | `qwen2.5-coder:32b` | 19 GB | 2026-08-01 | _pending Phase 4_ | inherited default. Near GPT-4o on Aider pass-rate |
| `local-big` | `llama3.3:70b` | 42 GB | 2026-08-01 | _pending Phase 4_ | **flagged for replacement** |
| `local-embed` | `nomic-embed-text` | 274 MB | 2026-08-01 | _pending Phase 4_ | inherited |
| `cloud-cheap` | `gemini-3.5-flash` | — | 2026-08-01 | n/a | **LIVE**. Verified current. 1M ctx |

## Dormant

Commented out in `config.yaml`. A model whose `os.environ/` key is missing fails the
**entire** config load, so these stay off until their key exists.

| Role | Model | Blocked on | Note |
|---|---|---|---|
| `cloud-code` | `claude-sonnet-5` | Anthropic API key — **deliberately unset** | Claude Code runs on the subscription and doesn't need this. A console API key bills separately from the subscription, so this only earns its place if aider/Cursor/laptop need Claude. |
| `cloud-frontier` | `kimi-k3` via OpenRouter | OpenRouter key | Primary frontier route when enabled. One key, day-zero new models |
| `cloud-frontier-direct` | `kimi-k3` via Moonshot | Moonshot key | Same price, best K3 caching |
| `cloud-frontier-fast` | `kimi-k3` via Fireworks | Fireworks key | Dearest; throughput/LoRA only |

Enabling one: uncomment its block in `config.yaml`, add the key to
`~/.config/litellm/env`, add the role to `CLOUD_ALL` in `scripts/create-keys.sh`,
re-run that script, then `scripts/audit-fallbacks.sh` and `scripts/healthcheck.sh`.

## Open flag: `local-big`

`llama3.3:70b` costs 42 GB of a 48 GB budget. Consequences:

- It cannot coexist with `local-code` (19 GB). Switching roles evicts and cold-reloads.
- It is a dense 2024-era model being asked to compete with 2026 MoEs.

Candidate replacement class: ~30B MoE with ~3B active params (Qwen3-Coder-30B-A3B and
similar). Roughly 19 GB, 256K context, generates at ~7B speed while reasoning closer to
a 30B dense model. If it benches at parity, retiring the 70B frees 23 GB **and** removes
the eviction thrash.

Do not swap on reputation. Bench it (Phase 4), then decide.

## Cost reference

Checked 2026-08-01. LiteLLM auto-syncs its cost map, so the gateway's numbers stay
current on their own; these are here for human decisions.

| Kimi K3 via | $/M in | $/M out | Note |
|---|---|---|---|
| Moonshot (direct) | 3.00 | 15.00 | source of truth |
| OpenRouter | 3.00 | 15.00 | ~92% cache hit reported → effective input ≈ 0.52 |
| Fireworks serverless | 3.30 | 16.50 | 10% dearer; buys throughput and LoRA |

Two things worth remembering:

- **Fireworks is the most expensive of the three.** This stack originally defaulted to
  it because it was the provider that came to mind first, not because it won on price.
  That is exactly the failure mode this registry exists to catch.
- **Output price is the one that bites.** It is the expensive half of any agentic loop,
  where token counts compound. Reach for `cloud-code` before K3 unless you specifically
  need the 1M context or open weights.

Prices verified 2026-08-01. Re-check before any decision that depends on them — the
gateway's own cost map auto-syncs, but this table does not.

## Digest pinning

Ollama tags are mutable pointers, not versions. `ollama pull qwen2.5-coder:32b`
fetches whatever that tag points at today, which may be a different quantisation
than the one benched. Roles are therefore pinned to digests, and the auto-updater
stages new pulls under a `candidate-` prefix rather than overwriting.

## Changing a role

1. Stage-pull the candidate as `candidate-<name>`
2. `scripts/bench.sh` against the incumbent
3. Confirm it fits the 48 GB budget alongside whatever must coexist
4. Write an ADR in `docs/decisions/`
5. Update this table and `litellm/config.yaml` together
6. Reload gateway, run `scripts/healthcheck.sh`
7. Previous digest is the rollback
