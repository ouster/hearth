# ADR 0012 — `local-big` on Rapid-MLX

**Date:** 2026-09-06  
**Status:** accepted

## Context

Zed agent loops need reliable multi-turn tool calls. `qwen3-coder:30b` on Ollama
fails with XML tool-parse errors in longer chains. `gpt-oss:20b` on Ollama
worked but measured **18.2 s** on the tool-smoke harness vs **2.6 s** for
`qwen3.6-35b-4bit` on Rapid-MLX (see `bench/results/2026-09-06-1229-tool-smoke/`).

Rapid-MLX serves an OpenAI-compatible API on `127.0.0.1:8000` with
`qwen3_coder_xml` tool parsing — the failure mode we were hitting on Ollama Qwen.

## Decision

- Route **`local-big`** through Rapid-MLX (`openai/qwen3.6-35b-4bit` at
  `http://127.0.0.1:8000/v1`), not Ollama.
- Add **`scripts/install-rapid-mlx-service.sh`** — launchd `KeepAlive` on
  localhost `:8000`, default alias `qwen3.6-35b-4bit`.
- Zed agent default stays **`local-big`** via the `hearth` gateway — no second
  provider required.
- Retire **`gpt-oss:20b`** from `local-big`. Weights may stay on disk for
  break-glass / bench; role no longer points at them.

`local-code`, `local-chat`, `local-embed` remain on Ollama.

## Consequences

- **Two inference backends.** Ollama for three roles; Rapid-MLX for `local-big`.
  Both can be resident (~20 GB MLX + ~18 GB Ollama code) — watch the ~48 GB GPU
  envelope. Prefer one hot heavy model when possible.
- **MLX weights are not Ollama-digest-pinned.** `pin-digests.sh` skips non-Ollama
  roles. Re-bench after Rapid-MLX or HF weight updates.
- **`RAPID_MLX_API_KEY`** must be in `~/.config/litellm/env` (any string —
  Rapid-MLX does not authenticate locally; LiteLLM requires a value).
- **Break-glass:** `curl http://127.0.0.1:8000/v1/...` directly, or
  `ollama run gpt-oss:20b` for the old path — neither goes through key scope.
- **Fallback unchanged:** `local-code` / `local-chat` → `local-big` (now MLX).
  Still local-only.

## Rollback

In `litellm/config.yaml`, point `local-big` back at
`ollama_chat/gpt-oss:20b` with `api_base: http://127.0.0.1:11434`, remove the
Rapid-MLX service or stop using it, update `docs/MODELS.md`, restart LiteLLM.
