# 0010 — Cap local Ollama context at 64K

Date: 2026-09-04
Status: accepted for the Ollama era. The live cap is ADR 0046 (262144 on oMLX). ADR 0017 was the 128K cap.

## Context

After wiring Zed to Hearth, `local-code` allocated a full **256K** KV cache.
`ollama ps` showed `qwen3-coder:30b` at **45 GB** with `CONTEXT 262144` —
about 18 GB weights plus ~27 GB cache. System memory hit ~60 GB. The
~36.5 GB “all four roles fit” budget assumed a modest context, not the
model’s native ceiling.

Cause: `model_info.max_input_tokens` and Zed’s `max_tokens` advertised the
native window (262144 / 131072). Ollama sized the cache to match.

## Decision

Cap **runtime** context for local chat roles at **65536** tokens:

- `litellm_params.num_ctx: 65536` on `local-code` and `local-big`
- `model_info.max_input_tokens: 65536` on those roles so `/model/info` and
  `zed-litellm` stop advertising the native ceiling
- `local-chat` stays at its native **40960** (already under 64K); set
  `num_ctx: 40960` so nothing opens a larger window by accident
- `cloud-cheap` unchanged (1M is the provider’s problem, not this Mac’s RAM)

Native ceilings remain real on the weights. This is an operational budget
for a 64 GB machine with a ~48 GB GPU-accessible cap, not a claim the
models are 64K models.

## Consequences

- One `local-code` session should land near weight size plus a 64K cache,
  not 45 GB. Other roles can stay resident again.
- Repo-scale prompts that truly need >64K go to `cloud-cheap` (non-sensitive)
  or get chunked. Do not raise `num_ctx` without re-measuring `ollama ps`.
- Re-sync Zed after deploy (`zed-litellm --replace`) so the picker matches.
