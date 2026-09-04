# 0009 — Fill LiteLLM model_info cards for discovery clients

Date: 2026-09-04
Status: accepted

## Context

`zed-litellm` syncs roles into Zed from the gateway's `/model/info`. On the
live stack that endpoint returned null for `max_input_tokens` and every
`supports_*` flag on the chat roles, so the sync fell back to 128000 context
and guessed capabilities. Hand-tuning Zed settings worked once and would
drift on the next `--replace`.

Ollama already knows the real windows (`ollama show`). LiteLLM only reports
them when `model_info` is filled in config.

## Decision

Put discovery metadata on each live role in `litellm/config.yaml`:

| Role | `max_input_tokens` | reasoning | tools | vision |
|---|---|---|---|---|
| `local-code` | 65536 (was 262144; ADR 0010) | no | yes | no |
| `local-chat` | 40960 | no | yes | no |
| `local-big` | 65536 (was 131072; ADR 0010) | yes | yes | no |
| `local-embed` | 2048 | no | no | no |
| `cloud-cheap` | 1048576 | no | yes | yes |

**Superseded in part by ADR 0010.** Advertising the native window made Ollama
allocate a 256K KV cache (~45 GB). Runtime `num_ctx` and the discovery cards
for `local-code` / `local-big` are now 64K.

`local-chat` is a hybrid model with thinking forced off (`think: false`,
ADR 0006). Advertise `supports_reasoning: false` so clients do not turn
thinking UI back on for that role.

`max_output_tokens` is a deliberate 65536 cap for chat roles, not a copy of
the input window. zed-litellm treats `out == in` as unreliable and would
otherwise ignore it.

Extend `scripts/preflight.sh`'s `model_info` allowlist with
`supports_reasoning`, `supports_parallel_function_calling`, and
`supports_tool_choice` — real fields on `litellm.types.utils.ModelInfo`.
Invalid keys still fail preflight; the old `tier: local` silent-drop lesson
stands.

## Consequences

- `/model/info` becomes the source of truth for context windows and capability
  flags. Re-running `zed-litellm --replace` regenerates honest Zed entries.
- Cards must be updated when a role's underlying model changes (same edit
  wave as `docs/MODELS.md` and the digest pin).
- Metadata only. It does not change routing, fallbacks, or what a completion
  call does.
