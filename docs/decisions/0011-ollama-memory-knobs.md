# 0011 — Ollama memory knobs + concrete names in Zed

**Date:** 2026-09-04

## Context

After capping `num_ctx` at 64K (ADR 0010), KV cache still dominated RAM when
several local models stayed hot. Meefik's Zed setup keeps one model loaded and
quantizes the KV cache. Separately, the Zed picker showed role ids
(`local-code`, `local-big`) which made weight-class comparisons harder while
evaluating candidates.

## Decision

1. Put these into the `ollama serve` launchd plist (`install-ollama-service.sh`):
   - `OLLAMA_FLASH_ATTENTION=1`
   - `OLLAMA_KV_CACHE_TYPE=q8_0`
   - `OLLAMA_MAX_LOADED_MODELS=1`
   - `OLLAMA_KEEP_ALIVE=-1`
   - `OLLAMA_NUM_PARALLEL=1`
2. Keep gateway **roles** as API `name`s. In Zed, set `display_name` to the
   concrete Ollama tag (allowed only in `config.yaml` / `MODELS.md` for
   routing docs; UI labels are not a second registry).
3. Do **not** swap `local-code` until `scripts/bench.sh` compares the incumbent
   `qwen3-coder:30b` against `qwen3.6:27b-coding-mtp-q4_K_M`.

## Consequences

- Switching chat ↔ code ↔ big **evicts** the previous resident model (~load
  cost). One hot model fits the ~48 GB GPU envelope more safely.
- Re-apply `install-ollama-service.sh --apply` (or edit the live plist and
  `launchctl kickstart -k`) after changing knobs; env is read at serve start.
- `zed-litellm` without `--replace` preserves `display_name`. `--replace` /
  `-f` wipes it — re-add after a full sync.
- Confirm `ollama ps` SIZE drops after a 64K load vs f16 KV; if Mac metal
  ignores `q8_0`, fall back is silent — measure, do not assume.
