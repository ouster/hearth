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
| `local-fast` | quick edits, autocomplete, throwaway questions | live |
| `local-code` | default. Real coding, still private | live |
| `local-big` | long context, reasoning-heavy, still private | live |
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
| `roam` | everything live | laptop, when it needs real cloud models |

A request for a cloud role with the `private` key is rejected by the gateway.
There is no prompt you can write that gets around it. That is the point.

The dollar caps on these keys are fuses, not billing — you are the only user.
They stop a leaked key or a runaway overnight agent loop from running up your
provider account.

## The fallback rule

**Local roles never fall back to cloud roles.**

The inherited config had `local-ollama -> cloud-fallback (gemini)`, so any Ollama
timeout, cold load, or restart silently routed the prompt to Google. A fallback is
an invisible route change; on a privacy boundary that is a leak, not resilience.

Local roles fall back to smaller local roles. If every local role is down, the
request fails loudly. Failing is the correct behaviour here.

## Break-glass

If the gateway is down and you need local inference now, Ollama is reachable at
`127.0.0.1:11434` from this machine. That path has no logging, no spend tracking,
and no key scoping — use it to unblock yourself, then fix the gateway.
