# ADR 0014 — `cloud-cheap` is Gemini 3.6 Flash

**Date:** 2026-10-22
**Status:** accepted

## Context

`cloud-cheap` was `gemini-3.5-flash`, set 2026-08-01. Google's API changelog
on 2026-10-08 says that name is deprecated and requests are sent to
`gemini-3.6-flash`. The config string no longer named the model that runs.

`gemini-3.8-flash` (GA 2026-09-02) is the newer Flash. On 2026-10-22 the
existing `GOOGLE_API_KEY` got a 200 from `gemini-3.6-flash` in 1.7 s and
503 "high demand" from `gemini-3.8-flash`. Same key, so this is capacity,
not a missing credential.

Google's 3.6 model card (checked 2026-10-22, card updated July 2026) lists
1,048,576 input tokens, 65,536 output, tools, vision, caching, and thinking.

## Decision

Point `cloud-cheap` at `gemini/gemini-3.6-flash`. Context card stays 1M in /
64K out. Advertise reasoning, because the model thinks by default: a 64-token
cap came back empty with 61 thought tokens. This role is still cloud: the
`private` key cannot reach it.

## Consequences

- The config names the model Google was already serving for the old alias.
- Thinking can spend the output budget on short calls. Give it room.
- Local roles are unchanged and still do not fall back here.
- `gemini-3.8-flash` stays off this role until it answers reliably.

## Rollback

Set the model back to `gemini/gemini-3.5-flash` (deprecated alias) or
`gemini/gemini-3.8-flash` once Google stops returning 503, update
`docs/MODELS.md`, restart LiteLLM.
