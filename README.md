# ai-stack

Private-first LLM gateway for a single developer. Ollama and LiteLLM locally,
Gemini/Claude/OpenRouter as cloud tiers, with the privacy boundary enforced by
key scope rather than by remembering to be careful.

Host: Mac Studio M4 Max, 64 GB, macOS 26.

## The idea

Clients address **roles**, never model names:

```
local-fast   local-code   local-big   local-embed   cloud-cheap
```

Concrete models live in exactly two files — `litellm/config.yaml` and
`docs/MODELS.md`. Swapping the model behind a role is one config change; no
alias, script, or IDE setting moves. That is the answer to a field where the
best local coding model changes every few months.

```
  Cursor ─┐
  aider ──┤                                 ┌─ Ollama  127.0.0.1:11434
  scripts─┼──► LiteLLM :4000 ───────────────┤
  laptop ─┤     roles · keys · spend        └─ Gemini / OpenRouter / Anthropic
          │              │
          ▼              ▼
      Postgres 127.0.0.1:5433 (Podman)
```

## Three guarantees

**Privacy is structural.** The `private` virtual key's model list contains no
cloud roles, so a cloud request with it is refused by the gateway. Ollama binds
to localhost, so nothing on the LAN can route around it. `healthcheck.sh` proves
both halves — the key must *succeed* on a local role and be *refused* on a live
cloud one, because a merely broken key refuses everything and looks identical.

**Local roles never fall back to cloud.** The inherited config had
`local-ollama → gemini`, so any Ollama timeout silently shipped the prompt to
Google. Across a privacy boundary a fallback is a leak, not resilience.
`audit-fallbacks.sh` fails the build if it reappears.

**Nothing is claimed without being measured.** Retiring `llama3.3:70b` came from
a timed probe (440 s, because 42 GB could not stay resident), not from an
opinion about model quality. See `docs/decisions/0004`.

## Usage

```bash
source scripts/aliases.zsh

ask                # local-code, private — the default
ask-fast           # local-fast
ask-big            # local-big
ask-cloud          # cloud-cheap, explicit reach

ai-health          # every role + the leak test
ai-audit           # fallback leak check
ai-restart
```

## Operations

| Script | Purpose |
|---|---|
| `preflight.sh` | Read-only. Exit 2 = check couldn't run, 1 = real problem |
| `deploy.sh` | Cut over, verify, auto-rollback. Never touches launchd |
| `healthcheck.sh` | Every live role + the two-part leak test |
| `audit-fallbacks.sh` | Fails if a local role can reach cloud |
| `swap-role.sh` | Repoint a role: pull, edit, verify, then delete old weights |
| `bench.sh` | Compare candidates on real tasks before promoting |
| `db.sh` | Postgres under Podman: `up`, `migrate`, `psql`, `destroy` |
| `lock-ollama.sh` | Bind Ollama to localhost, verify LAN is closed |
| `diagnose.sh` | What the gateway actually loaded, when it disagrees with you |
| `bisect-config.sh` | Find which config section breaks model loading |

Start with `docs/ARCHITECTURE.md`, then `docs/ROUTING.md` and `docs/RUNBOOK.md`.
`docs/decisions/` records why things are the way they are, including the
rejected alternatives.

## Secrets

Two environment files, deliberately:

- `~/.config/litellm/env` — the only one launchd reads. Provider keys,
  master key, `DATABASE_URL`. Template: `litellm/service-env.example`
- `litellm/.env` — scripts only. `POSTGRES_PASSWORD`, virtual keys. Gitignored

launchd reads neither the repo `.env` nor `~/.zshrc`. `preflight.sh` checks the
service environment specifically, because a variable set in your shell will look
fine and then fail at runtime.

## Status

Gateway live, four scoped keys, leak test passing, Ollama localhost-only.
Outstanding: digest pinning, a chat UI, and an approval-gated model auto-updater.
See `docs/PLAN.md`.
