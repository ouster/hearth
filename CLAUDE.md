# ai-stack

Private-first AI gateway. Ollama + LiteLLM local, Claude / Gemini / Fireworks cloud.
Host: Mac Studio M4 Max, 64 GB.

Read `docs/ROUTING.md` before suggesting any routing change.

## Hard rules

1. **Concrete model names appear in exactly two files:** `litellm/config.yaml` and
   `docs/MODELS.md`. Everywhere else — aliases, scripts, IDE config, code — uses roles.
   If you are about to write `qwen3-coder:30b` into a shell alias, stop.

   Live: `local-chat`, `local-code`, `local-big`, `local-embed`, `cloud-cheap`.
   Dormant: `cloud-code`, `cloud-frontier`, `cloud-frontier-direct`,
   `cloud-frontier-fast` — commented out until their keys exist, because a missing
   `os.environ/` var fails the entire config load, not just that model.

2. **Local roles never fall back to cloud roles.** A fallback is an invisible route
   change; across a privacy boundary it is a leak. If every local role is down, fail
   loudly. Any change adding a cloud model to a `local-*` fallback list is a bug.

3. **Privacy is structural.** Client matter data, PII, credentials, and anything under
   `stepup-conveyancing` or `auslaw-mcp` containing real data goes to `local-*` only,
   enforced by the `private` virtual key's scope. Refuse to write code or config that
   could route that class of data to a cloud endpoint.

4. **Your model knowledge is stale.** Before asserting a price, context window,
   benchmark, or that a model exists — search, and give the date of what you found.
   This field moves faster than your training data. Do not recommend from memory.

5. **Nothing replaces a role until it is benched.** Run `bench/tasks/` against the
   incumbent. Reputation is not evidence.

6. **Roles pin to digests, not tags.** Ollama tags are mutable pointers. An unpinned
   role can silently change weights on any pull.

7. **Check the RAM envelope.** 64 GB total, ~54 GB for weights after macOS and
   apps. Current resident set is 37.5 GB. Say when a suggestion will not fit, or
   will evict something that needs to stay loaded — on this machine the resident
   set matters more than any one model's quality.

8. **Routing and model changes get an ADR** in `docs/decisions/` — context, decision,
   consequences, date. Short.

9. **Shell scripts:** portable bash running under zsh on macOS. LF line endings only.
   CRLF breaks shebangs and launchd.

10. **Never commit keys.** `master_key`, provider keys, and `.env` stay out of git.
    Config references `os.environ/NAME`.

## Workflow

Plan → Colin refines → Colin approves → build. Do not start building because a plan
looks obviously right.

Be concise. No preamble, no restating the question, no long summary of what you did.

## Layout

```
CLAUDE.md            this file
AGENTS.md            same rules, for Cursor and aider
docs/
  PLAN.md            build plan and status
  ARCHITECTURE.md    how the gateway is wired
  ROUTING.md         local vs cloud decision table
  MODELS.md          role → model registry
  RUNBOOK.md         start, stop, diagnose
  CLAUDE-PROJECT.md  the claude.ai Project spec
  decisions/         ADRs
litellm/config.yaml  the only file that names models
scripts/             recon, healthcheck, bench, update
bench/tasks/         fixed prompts for model comparison
```
