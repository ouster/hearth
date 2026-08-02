# ADR 0004 — Retire llama3.3:70b as `local-big`

Date: 2026-08-02
Status: accepted — **role assignment superseded by ADR 0005**

## Context

`local-big` was `llama3.3:70b`, inherited from the pre-gateway setup. At 42 GB it
was the largest model on the machine and, on paper, the most capable local option.

Measured through the gateway on 2026-08-02, one short prompt each, from cold:

| Role | Model | Size | Time to first reply |
|---|---|---|---|
| `local-fast` | qwen2.5-coder:7b | 4.7 GB | 0 s |
| `local-code` | qwen2.5-coder:32b | 19 GB | 29 s |
| `local-big` | llama3.3:70b | 42 GB | **440 s** |
| `cloud-cheap` | gemini-3.5-flash | — | 2 s |

## The actual problem

Not generation speed. Capacity.

64 GB unified, less roughly 10 GB for macOS and applications, leaves about 54 GB
for weights. `local-code` (19 GB) + `local-big` (42 GB) is 61 GB. They cannot both
be resident, so every switch between them is a full evict-and-reload of 42 GB
from disk.

That makes the 70B not merely slow but structurally incompatible with keeping
anything else loaded. Seven and a half minutes is also ~200x slower than the
cloud round-trip it was meant to be a private alternative to, which defeats the
purpose of having a capable local model at all.

## Decision

`local-big` becomes `qwen3-coder:30b` — a 30B mixture-of-experts model activating
roughly 3B parameters per token. About 19 GB at Q4, 256K context.

Rationale:

- **It fits alongside everything else.** 4.7 + 19 + 19 = 42.7 GB resident, inside
  the ~54 GB budget. No eviction, so no cold-load penalty after the first load.
- **MoE changes the arithmetic.** ~3B active params means it generates at roughly
  7B speed while reasoning closer to a 30B dense model.
- **256K context** is a better definition of "big" for this role than raw
  parameter count — long-context work was what `local-big` was actually for.
- Frees 42 GB.

## Consequences

- `llama3.3:70b` stays **on disk** for now. It is out of the config, so nothing
  routes to it, but re-downloading 42 GB to undo a hasty decision would be
  tedious. Delete it with `ollama rm llama3.3:70b` once the replacement has
  earned its place over a week of real use.
- This was decided on a capacity measurement, not a quality bench. The 70B may
  well produce better answers on some tasks — that is not the point. A model that
  takes 440 s and evicts your coding model is unusable regardless of quality.
- `bench.sh` should still be run to compare quality, and may yet argue for
  `qwen3-coder:30b` taking over `local-code` from `qwen2.5-coder:32b` as well.
  That is a separate decision on separate evidence.

## Superseded in part

This ADR assigned `qwen3-coder:30b` to `local-big`. ADR 0005 later moved it to
`local-code` (replacing qwen2.5-coder:32b) and gave `local-big` to
`gpt-oss:20b` as the reasoning role. The reasoning here — that a 42 GB model
which cannot stay resident is unusable regardless of quality — stands unchanged;
only the destination role moved.

Live assignment is always `litellm/config.yaml` and `docs/MODELS.md`.

## Rollback

Point `local-big` back at `ollama_chat/llama3.3:70b` in `litellm/config.yaml`,
then `scripts/deploy.sh`. The weights are still there until explicitly removed.
