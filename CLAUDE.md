# Hearth

Local-first AI serving. The LM Studio app on `127.0.0.1:1234` serves local
roles (never also run headless `llmster`); cloud (Gemini) is reached by each tool with its own key.

Read `docs/ROUTING.md` before suggesting any routing change.

**In flight:** migration to LM Studio direct — `docs/MIGRATION-LMSTUDIO.md`
(ADR 0016, accepted 2026-10-31). Host clients are cut over; LAN (phase 4) and
the script rewrite (phase 5) are pending. Work one phase at a time, only when
the operator says to start it, and stop at every DECISION. Anything in `litellm/`
or a doc describing `:4000`, `:11434`, virtual keys or Postgres is the retired
gateway — never suggest commands against it.

## Hard rules

1. **Concrete model names appear in exactly two files:** `config/roles.tsv` and
   `docs/MODELS.md`. Everywhere else — aliases, scripts, IDE config, code — uses roles.
   If you are about to write a model tag into a shell alias, stop.
   Same discipline for MCP servers: client config docs (`docs/IDES.md`) and
   `docs/MCP.md`.

   Live: `local-big`, `local-embed` (LM Studio identifiers), `cloud-cheap`
   (Gemini, `ask-cloud` only). `local-code` / `local-chat` are alias names that
   mean `local-big` (D1). Dormant: `cloud-code`, `cloud-frontier*` — no keys.

2. **LM Studio never holds a cloud model.** There is no router, so there are no
   fallbacks; if `local-big` is down, fail loudly. No script adds a remote backend
   to `config/roles.tsv` except as an explicit cloud row (`gemini` or another named
   cloud backend). A change that would let `:1234` reach a remote model is a bug.

3. **Privacy is structural.** Sensitive private data, PII, credentials, and any repo or
   path the operator has flagged as sensitive goes to `local-*` only. That is
   enforced by placement — `:1234` holds only local models, only `ask-cloud`
   carries a cloud key, sandboxed agents can reach `127.0.0.1:1234` and nothing
   else — not by key scope. Refuse to write code or config that could route that
   class of data to a cloud endpoint, including adding a cloud provider to host Zed.

4. **Your model knowledge is stale.** Before asserting a price, context window,
   benchmark, or that a model exists — search, and give the date of what you found.
   This field moves faster than your training data. Do not recommend from memory.

5. **Nothing replaces a role until it is benched.** Run `bench/tasks/` and
   `scripts/concurrency-bench.sh` against the incumbent. Reputation is not evidence.

6. **Weights are recorded, not pinned.** `docs/MODELS.md` records each role's
   source repo and revision. Drift detection for LM Studio (hash the model
   directory, D4) is not built yet, and the Ollama-era `pins/digests.tsv` no
   longer describes what serves. Say so rather than implying roles are immutable.

7. **Check the RAM envelope.** 64 GB total, but macOS caps GPU-accessible memory at ~48 GB
   (75% above 36 GB) — that is the real ceiling. Current resident set is ~29.7 GB peak (local-big 64K × 3 slots + local-embed, measured 2026-10-31). Say when a suggestion will not fit, or
   will evict something that needs to stay loaded — on this machine the resident
   set matters more than any one model's quality.

8. **Routing and model changes get an ADR** in `docs/decisions/` — context, decision,
   consequences, date. Short.

9. **Shell scripts:** portable bash running under zsh on macOS. LF line endings only.
   CRLF breaks shebangs and launchd. **macOS `/bin/bash` is 3.2** — no `declare -A`,
   no `mapfile`, no `${x^^}`, and guard empty-array expansion as
   `${arr[@]+"${arr[@]}"}` under `set -u`. Preflight scans for all of these.

10. **All diagrams are Mermaid.** No ASCII art, no committed SVG or PNG. GitHub
    renders Mermaid natively, it diffs as text, and it cannot drift out of sync
    with the prose the way an exported image does. If a diagram cannot be
    expressed in Mermaid, use a Markdown table instead.

11. **Never commit keys.** LM Studio tokens, provider keys, and `.env` files stay
    out of git. Tokens live in `~/.config/hearth/env` (mode 600) and Zed's keychain.

## Workflow

Plan → operator refines → operator approves → build. Do not start building because
a plan looks obviously right.

Be concise. No preamble, no restating the question, no long summary of what you did.

## Layout

```
CLAUDE.md            this file
AGENTS.md            same rules, for Zed and aider
docs/
  PLAN.md            build plan and status
  ARCHITECTURE.md    how serving is wired
  ROUTING.md         local vs cloud decision table
  MODELS.md          role → model registry
  HISTORY.md         what we tried, and why it stayed or went
  MCP.md             MCP server → tools → which clients
  RUNBOOK.md         start, stop, diagnose
  CLAUDE-PROJECT.md  the claude.ai Project spec
  decisions/         ADRs
config/roles.tsv     role → model key, context, slots (names models)
litellm/             retired gateway config, removed in phase 5
scripts/             lms-load, benches, sandbox, aliases
bench/tasks/         fixed prompts for model comparison
```
