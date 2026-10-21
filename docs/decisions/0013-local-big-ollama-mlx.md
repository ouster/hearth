# ADR 0013 — `local-big` back on Ollama

**Date:** 2026-10-22
**Status:** accepted
**Supersedes:** ADR 0012

## Context

ADR 0012 put `local-big` on Rapid-MLX because Ollama's Qwen tool parser
failed Zed agent loops, and because `qwen3.6-35b-4bit` there was faster than
`gpt-oss:20b`. That second server costs a resident ~20 GB beside Ollama.

Ollama 0.40.4 on this Mac includes the MLX runner. `ollama pull qwen3.6:35b-mlx`
and `scripts/tool-smoke.sh` on 2026-10-22:

| Path | Result | Wall clock |
|---|---|---|
| Rapid-MLX `qwen3.6-35b-4bit` (already resident) | pass, `<` in the write | 5.1 s |
| Ollama `qwen3.6:35b-mlx` (cold, runner `mlx`, 23 GB) | pass, `<` in the write | 17.3 s |

The 17 s includes the weight load. `ollama ps` reported runner `mlx`.

## Decision

- Route **`local-big`** through Ollama (`ollama_chat/qwen3.6:35b-mlx` at
  `http://127.0.0.1:11434`) with `num_ctx: 65536` (ADR 0010).
- Remove the Rapid-MLX launchd service. `scripts/mlx-bench.sh` can still
  start Rapid-MLX by hand for an experiment. It is not part of boot.
- One Ollama model stays GPU-resident (ADR 0011). `local-big` evicts
  `local-code` and the reverse.

## Consequences

- One inference server for every local role. No `:8000`, no
  `RAPID_MLX_API_KEY`.
- The tag is an Ollama pointer. `pin-digests.sh` records the digest; it does
  not pin the bytes. Re-bench after a pull.
- Weights are ~23 GB. A 64K context on top still has to fit the ~48 GB GPU
  ceiling with whatever else is resident. Do not raise `num_ctx`.

## Rollback

Point `local-big` back at Rapid-MLX as in ADR 0012, restore
`scripts/install-rapid-mlx-service.sh` from that commit, put
`RAPID_MLX_API_KEY` in `~/.config/litellm/env`, restart LiteLLM.
