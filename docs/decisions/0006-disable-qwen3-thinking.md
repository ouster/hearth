# ADR 0006 — Disable qwen3 thinking on `local-chat`

Date: 2026-08-02
Status: accepted

## Context

The first real bench exposed something the tok/s column had hidden:
`local-chat` was the **slowest** role on the machine despite running the
smallest model.

| Model | tokens over 4 tasks | wall clock |
|---|---|---|
| `qwen3-coder:30b` | 1,218 | 11.2 s |
| `gpt-oss:20b` | 4,466 (3.7x) | 47.6 s |
| `qwen3:8b` | **13,840 (11.4x)** | **181.4 s** |

One task took `qwen3:8b` **100 seconds and 7,548 tokens** against 1.6 s and
192 tokens for `qwen3-coder` — forty times the output for the same question.

Throughput was near-identical across all three (65–120 tok/s), because this
machine is memory-bandwidth bound. **Wall clock is set by how many tokens a
model emits, not how fast it emits them.** `qwen3:8b` is a hybrid reasoning
model, and it was thinking at length about everything, including trivial chat.

That is defensible for `local-big`. It is wrong for the role that answers
questions in a browser.

## Options measured

Three ways to suppress thinking, measured rather than assumed:

| | Approach | Result |
|---|---|---|
| A | Ollama `think: false` parameter | **2236 → 333 tokens**, thinking off |
| B | `/no_think` in the user message | 2236 → 2261 tokens — **ignored** |
| C | Modelfile with `/no_think` as system prompt | could not build; and B suggests it would be ignored too |

Then A again **through the gateway**, because `drop_params: true` could have
stripped an unrecognised parameter before it reached Ollama:

- Before: **2,370 tokens, 29.7 s**
- After: **386 tokens, 5.1 s**

LiteLLM forwards `think` despite `drop_params: true`.

## Decision

Set `think: false` in `local-chat`'s `litellm_params`. Per-role, so
`local-big` keeps its reasoning.

`qwen3:8b` supports both modes natively — this uses the model as designed
rather than working around it, and the switch can be reverted for a question
that deserves the thinking.

## Consequences

- `local-chat` goes from the slowest role to the fastest: ~5 s instead of 25–100 s.
- Answer quality on genuinely hard reasoning will drop. That work belongs on
  `local-big` (`ask-big`), which still thinks.
- One more per-role parameter to remember when swapping the model behind
  `local-chat`. `swap-role.sh` preserves `litellm_params`, but a swap to a
  non-hybrid model would leave a `think` key that does nothing.

## Two lessons worth keeping

**tok/s was the wrong metric and hid the problem.** `bench.sh` now leads with
tokens emitted and shows a multiplier against the least verbose model.

**Content inspection lied; the token count did not.** The verification script
looked for a `<think>` block in the response and reported "direct" even on the
thinking baseline — LiteLLM strips that block out of `content`. Had the check
relied on it, the result would have read as a pass before the change was made.
Measure the thing that cannot be reformatted away.

## Rollback

Remove the `think: false` line from `local-chat` in `litellm/config.yaml` and
run `scripts/deploy.sh`.
