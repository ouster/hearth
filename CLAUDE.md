# Hearth

Local-first AI serving. oMLX on `127.0.0.1:1234` serves local roles from
`~/.hearth/models` (ADR 0026). `scripts/omlx-try.sh down` puts the LM Studio
app back on that port. Never also run headless `llmster`. Cloud (Gemini) is
reached by each tool with its own key.

## Which machine are you on?

- **The host** (runs LM Studio; `~/.lmstudio/bin/lms` exists): everything
  below applies.
- **A laptop** (no LM Studio; someone cloned this repo to set up access):
  follow `docs/LAPTOP.md` → *AI-assisted setup* and nothing else. Do not run
  anything in `scripts/` — those are host scripts and touch the host's LM
  Studio, launchd and `authorized_keys`. Host-side steps are ones you tell the
  person to do on the host. You are likely a cloud model, so **never read,
  print, grep, copy or edit** `~/.hearth-key`, `~/.hearth-gemini-key` or
  `~/.ssh/hearth_tunnel`; the person types secrets in themselves, and you may
  only check their permissions with `ls -l`.

Read `docs/ROUTING.md` before suggesting any routing change.

**Serving:** login boot starts oMLX (ADR 0026). `scripts/omlx-try.sh down` is the rollback to LM Studio. `ask-deep` swaps `local-deep` in for `local-main` inside oMLX and puts `local-main` back on the way out (ADR 0027).

**In flight:** migration to LM Studio direct — `docs/MIGRATION-LMSTUDIO.md`
(ADR 0016, accepted 2026-10-31). Host clients are cut over, the old stack is
deleted and the scripts are rewritten; LAN (phase 4) is pending. Work one phase at a time, only when
the operator says to start it, and stop at every DECISION. Any doc or
script describing `:4000`, `:11434`, LiteLLM, virtual keys or Postgres is the
removed gateway — never suggest commands against it.

## Hard rules

1. **Concrete model names appear in exactly two files:** `config/roles.tsv` and
   `docs/MODELS.md`. Everywhere else — aliases, scripts, IDE config, code — uses roles.
   If you are about to write a model tag into a shell alias, stop.
   Two generated copies, both written from `roles.tsv` so they cannot drift:
   the `display_name` labels in Zed's settings (`scripts/zed-sync.sh`, from
   `roles.tsv` + `lms ls`), and the model key plus weights path in
   `pins/digests.tsv` (`scripts/pin-digests.sh`). Clients always *call* the role.
   Same discipline for MCP servers: client config docs (`docs/IDES.md`) and
   `docs/MCP.md`.

   Live: `local-main` (oMLX identifier, resident), `local-deep` (swapped in
   instead of `local-main` for an `ask-deep` session, ADR 0020 — never call it
   unless loaded, never load it beside `local-main`), `cloud-cheap`
   (Gemini, `ask-cloud` only). `local-code` / `local-chat` are alias names that
   mean `local-main` (D1). Dormant: `cloud-code`, `cloud-frontier*` — no keys.

2. **LM Studio never holds a cloud model.** There is no router, so there are no
   fallbacks; if `local-main` is down, fail loudly. No script adds a remote backend
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

6. **Weights are hashed and drift is detected — not enforced.** `docs/MODELS.md`
   records each role's source repo and revision; `scripts/pin-digests.sh` hashes
   the files into `pins/digests.tsv` and `preflight.sh` fails on drift. LM Studio
   still loads whatever is on disk; say so rather than implying roles are
   immutable. Re-record only after re-benching.

7. **Check the RAM envelope.** 64 GB total. macOS's default GPU cap is ~48 GB
   (75% above 36 GB). This host sets `iogpu.wired_limit_mb` to 57344, so the
   ceiling is 56 GB (RAM minus 8), and the oMLX memory guard matches it (ADR 0027).
   `local-main` (ADR 0024) peaks at 25.2 GB at 128K × 3 with three concurrent ~30K-token prompts (measured 2026-11-01, footprint includes the app). `local-deep` is swapped in instead of `local-main`, never beside it. Say when a suggestion will not fit, or
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
    Never read or print that file's contents yourself — scripts source it;
    check it with `ls -l` only.

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
scripts/             lms-load, benches, sandbox, aliases
bench/tasks/         fixed prompts for model comparison
```
