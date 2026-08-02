# Routing rules

The decision table. When in doubt, local.

## What must stay local

Route to `local-*` roles, always:

- Anything under `~/dev/stepup-conveyancing` containing real matter data
- Anything under `~/dev/auslaw-mcp` containing real client or case data
- Client names, addresses, contact details, settlement figures, ID documents
- Anything covered by Australian Privacy Principles obligations
- Credentials, keys, `.env` contents, database dumps
- Anything you would not paste into a public forum

This is enforced by key scope, not by discipline — see below.

## What can go to cloud

- Open-source repos and public code
- Synthetic or anonymised examples
- Language, framework, and API questions with no data attached
- Architecture and design discussion in the abstract
- This repo itself

## Roles

| Role | Use for | State |
|---|---|---|
| `local-code` | default for code. Real work, still private | live |
| `local-big` | long context, reasoning-heavy, still private | live |
| `local-chat` | **general questions**, not code. Open WebUI default | live |
| `local-embed` | embeddings for local RAG | live |
| `cloud-cheap` | bulk non-sensitive work, big context | live |
| `cloud-code` | hard coding and agentic work | dormant — no Anthropic key by choice |
| `cloud-frontier` | very large open models via OpenRouter | dormant |
| `cloud-frontier-direct` | same, via Moonshot. Best K3 caching | dormant |
| `cloud-frontier-fast` | same, via Fireworks. Dearest | dormant |

## Enforcement

Privacy is structural. Four virtual keys:

| Key | Reaches | Used by |
|---|---|---|
| `private` | `local-*` only | conveyancing work, Open WebUI default |
| `general` | everything live | this machine — Cursor, aider, scripts |
| `lan` | `local-*` + `cloud-cheap` | other machines, everyday |
| `lan-cloud` | everything live | laptop, when it needs real cloud models |

A request for a cloud role with the `private` key is rejected by the gateway.
There is no prompt you can write that gets around it. That is the point.

The dollar caps on these keys are fuses, not billing — you are the only user.
They stop a leaked key or a runaway overnight agent loop from running up your
provider account.

## Web search punctures the boundary

Open WebUI can give local models web search via self-hosted SearXNG
(`scripts/searxng.sh`). The model, the conversation and your documents all stay
on this machine. **The search query does not.**

SearXNG stops Google, Bing and DuckDuckGo seeing your IP or building a profile —
it queries them on your behalf. That is a genuine improvement over searching
directly. It is not privacy. The search terms still leave.

So the same local/cloud line applies to search, one level down:

| Safe with web search on | Never with web search on |
|---|---|
| "How does the Torrens title system handle X?" | "Search for <client name> <address>" |
| "What changed in the 2026 conveyancing regulations?" | Anything quoting a matter, party, or settlement figure |
| Framework and API questions | Anything you would not type into Google |

Web search is opt-in per conversation, not a global setting. Leave it off by
default and turn it on for the specific question. A conversation that started
with a client document should never have it enabled — earlier context can be
pulled into a generated search query.

If you want the guarantee to be structural rather than remembered, run a second
Open WebUI without search configured and use that for client work.

## The fallback rule

**Local roles never fall back to cloud roles.**

The inherited config had `local-ollama -> cloud-fallback (gemini)`, so any Ollama
timeout, cold load, or restart silently routed the prompt to Google. A fallback is
an invisible route change; on a privacy boundary that is a leak, not resilience.

Local roles fall back to *other local roles*, never to cloud. Currently
`local-code` and `local-chat` both fall back to `local-big`, and `local-big` has
no fallback at all — if it is down, fail loudly rather than quietly answer with
a weaker model. `scripts/audit-fallbacks.sh` enforces the local-only rule.

## Break-glass

If the gateway is down and you need local inference now, Ollama is reachable at
`127.0.0.1:11434` from this machine. That path has no logging, no spend tracking,
and no key scoping — use it to unblock yourself, then fix the gateway.
