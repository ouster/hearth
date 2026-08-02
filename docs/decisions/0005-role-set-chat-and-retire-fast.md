# ADR 0005 — Add `local-chat`, retire `local-fast`

Date: 2026-08-02
Status: accepted

## Context

Two problems surfaced within minutes of the chat UI going up, both from the same
root cause: the role set was designed entirely around the coding workflow.

**No general model.** The first ordinary question asked through Open WebUI — a
fun fact about the Roman Empire — was routed to `local-fast`
(`qwen2.5-coder:7b`) and came back as a hallucinated tool call
(`{"name": "get_current_timestamp"}`) rather than an answer. A code-completion
model is the wrong instrument for general questions, and "asking questions on
local LLMs more privately" was half the original brief.

**A stale leftover.** `local-code` had moved to `qwen3-coder:30b` and the old
qwen2.5-coder:32b was deleted, but `local-fast` was still `qwen2.5-coder:7b`.
The role that was updated got attention; the one next to it did not.

## Decision

**Add `local-chat` → `qwen3:8b`.** 5.2 GB, 40K context, general knowledge rather
than code. Default model for Open WebUI and for title/tag generation.

**Retire `local-fast`.** `qwen3-coder:30b` is a mixture-of-experts model
activating roughly 3B parameters per token, so it already generates at about 7B
speed. A separate small coder was solving a latency problem the MoE removed.

Worth recording that this was *not* a staleness fix. Qwen3-Coder has no variant
below 30B — the architecture starts there, and there are no 7B or 14B dense
builds. `qwen2.5-coder:7b` remains the strongest sub-10 GB coding model
available. It was retired because it became redundant, not because it was
outdated, and if a small dense coder appears later the role can return.

## Resulting set

| Role | Model | Size |
|---|---|---|
| `local-chat` | qwen3:8b | 5.2 GB |
| `local-code` | qwen3-coder:30b | 19 GB |
| `local-big` | gpt-oss:20b | 13 GB |
| `local-embed` | nomic-embed-text | 0.3 GB |

37.5 GB of a ~54 GB budget. All resident, no eviction.

## Consequences

- Fallbacks are now `local-code → local-big` and `local-chat → local-big`.
  `local-big` has none by design: if it is down, fail loudly rather than quietly
  answer with a weaker model.
- `ask-fast` now means `local-chat`. It is the fastest local model, so the alias
  still reads true, but it is a general model rather than a coder.
- Virtual keys must be recreated — a key's model list is fixed at creation, so
  existing keys cannot see `local-chat`.
- `ollama rm qwen2.5-coder:7b` frees 4.7 GB once you are satisfied.

## The general lesson

Both faults came from optimising the half of the brief that was front of mind.
The stack was exercised with coding tasks throughout, and the first genuinely
different question found the gap immediately. Poke a new setup with the
questions you would actually ask, not the ones it was designed for.
