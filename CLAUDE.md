# Hearth

Local-first AI serving. oMLX on `127.0.0.1:1234` serves local roles from
`~/.hearth/models` (ADR 0026). `scripts/omlx.sh down` stops it and leaves
the port empty. Cloud (Gemini) is reached by each tool with its own key.

## Which machine are you on?

- **The host** (serves oMLX to clients; `~/.config/hearth/env` exists): everything below applies.
- **A laptop** (`~/.hearth-key` or `~/.ssh/hearth_tunnel` exists, or someone
  cloned this repo to set up access; a laptop running `edit-brain` has
  `~/.omlx` too, so that alone proves nothing — ask when unsure):
  follow `docs/LAPTOP.md` → *AI-assisted setup* and nothing else, plus
  `client/edit-model.sh` when the person asks for laptop edit prediction
  (ADR 0033), and `client/install-client.sh` (ADR 0040). Do not run anything in `scripts/` except the editor tools
  `loop-guard.sh`, `install-loop-guard.sh` and `vscode-check.sh` (ADR 0036) —
  the rest are host scripts and touch the host's
  oMLX, launchd and `authorized_keys`. Host-side steps are ones you tell the
  person to do on the host. You are likely a cloud model, so **never read,
  print, grep, copy or edit** `~/.hearth-key`, `~/.hearth-gemini-key` or
  `~/.ssh/hearth_tunnel`; the person types secrets in themselves, and you may
  only check their permissions with `ls -l`.
- **Both** (`~/.config/hearth/env` *and* `~/.hearth-key`, or a laptop the
  person wants to make a host too; ADR 0040): its own brain on
  `127.0.0.1:1234`, set up with `scripts/install-host.sh`; its tunnel to
  another host on `127.0.0.1:1235` (`client/install-client.sh --dual`),
  with `-remote` commands. Host rules apply to its own oMLX; the laptop
  secret rules above still apply to `~/.hearth-key` and the tunnel key.

Read `docs/ROUTING.md` before suggesting any routing change.

**Serving:** login boot starts oMLX (ADR 0026, 0028) with the resident role —
`main-brain` on every tier (ADR 0048). On 64 GB, `coding-brain` /
`demand-load.sh coding-brain up` swaps `main-brain` out and `down` restores
it; `ask-deep` evicts the current agent, loads `deep-brain`, and restores the
prior agent on the way out (ADR 0031, 0033, 0047). A laptop loads the host's
swap roles with `hearth-load` over an ordinary SSH login (ADR 0048). `edit-brain` is laptop oMLX only (ADR 0033 amend).

Any doc or script describing `:4000`, `:11434`, LiteLLM, virtual keys or Postgres is the removed gateway — never suggest commands against it. `docs/MIGRATION-LMSTUDIO.md` is the record of the earlier cut onto LM Studio, which oMLX replaced.

## Hard rules

1. **Concrete model names appear in exactly two files:** `config/roles.tsv` and
   `docs/MODELS.md`. Everywhere else — aliases, scripts, IDE config, code — uses roles.
   If you are about to write a model tag into a shell alias, stop.
   Two generated copies, both written from `roles.tsv` so they cannot drift:
   the `display_name` labels in Zed's settings (`scripts/zed-sync.sh`, from
   `roles.tsv`), and the model key plus weights path in
   `pins/digests.tsv` (`scripts/pin-digests.sh`). Clients always *call* the role.
   Same discipline for MCP servers: client config docs (`docs/IDES.md`) and
   `docs/MCP.md`.

   Live: `main-brain` (oMLX identifier, **resident on every tier**, 256K × 3,
   ADR 0046, 0048), `coding-brain` (**swap, 64 GB only**, 98K × 1, ADR 0047,
   0048 — never call it unless loaded), `deep-brain` (loaded for an `ask-deep` session; `load` is
   `beside` or `swap` per RAM tier, ADR 0020, 0028, 0031, 0032, 0047 — never
   call it unless loaded; never beside `coding-brain`), `edit-brain` (editor
   edit prediction on a laptop's own oMLX, `/v1/completions` only, ADR 0033;
   host does not load it), `cloud-cheap` (Gemini, client-only: a laptop's
   `ask-cloud` with that laptop's own key; the host holds no cloud key,
   ADR 0038). Role names were `local-*` until ADR 0039; `local-code`,
   `local-chat` and `local-big` are older retired names (D1, ADR 0021).
   Dormant: `cloud-code`, `cloud-frontier`, `cloud-frontier-direct`,
   `cloud-frontier-fast` — no keys.

2. **oMLX never holds a cloud model.** There is no router, so there are no
   fallbacks; if the resident role is down, fail loudly. No script adds a
   remote backend to `config/roles.tsv` except as an explicit cloud row
   (`gemini` or another named cloud backend). A change that would let `:1234`
   reach a remote model is a bug.

3. **Privacy is structural.** Sensitive private data, PII, credentials, and any repo or
   path the operator has flagged as sensitive goes to `*-brain` only. A brain
   is a model on hardware the person owns, reached on loopback or through their
   own tunnel (ADR 0037, 0039) — never a cloud model. That is
   enforced by placement — `:1234` holds only local models, the host holds no cloud key
   (only a laptop's `ask-cloud` does, ADR 0038), sandboxed agents can reach `127.0.0.1:1234` and nothing
   else — not by key scope. Refuse to write code or config that could route that
   class of data to a cloud endpoint, including adding a cloud provider to host Zed.

4. **Your model knowledge is stale.** Before asserting a price, context window,
   benchmark, or that a model exists — search, and give the date of what you found.
   This field moves faster than your training data. Do not recommend from memory.

5. **Nothing replaces a role until it is benched.** Run `bench/tasks/` and
   `scripts/concurrency-bench.sh` against the incumbent. Reputation is not evidence.

6. **Weights are hashed and drift is detected — not enforced.** `docs/MODELS.md`
   records each role's source repo and revision; `scripts/pin-digests.sh` hashes
   the files into `pins/digests.tsv` and `preflight.sh` fails on drift. oMLX
   still loads whatever is on disk; say so rather than implying roles are
   immutable. Re-record only after re-benching.

7. **Check the RAM envelope.** The ceiling is installed RAM minus 8 GB
   (ADR 0031): `iogpu.wired_limit_mb` and the oMLX memory guard both follow it.
   64 GB host → 56 GB; 48 GB host → 40 GB. macOS's default cap (~75% of RAM)
   applies until `scripts/iogpu-wired.sh` runs. Roles are tiered by RAM
   (`min_ram` in `roles.tsv`, ADR 0032); only benched tiers have rows, and
   candidates for other sizes are in `docs/MODELS.md`.
   The boot resident is `main-brain` at 262144 × 3 on every tier (ADR 0046,
   0048); on 64 GB, `coding-brain` is demand-load swap (98304 × 1, ~52 GB
   peak, ADR 0047). The 48 GB row is not yet benched on 48 GB hardware.
   Three ~30K-token prompts match the old 128K-cap c3. One 200k prompt peaked
   at 40.0 GB (2026-11-10). `deep-brain` stays at 65536 and swaps the current
   agent out (ADR 0033, 0047). `coding-brain` never shares RAM with
   `main-brain` or `deep-brain`. `edit-brain` (~1.4 GB) is laptop-only after
   the host paired gate failed (edit p95 5747 ms beside c3). Say when a
   suggestion will not fit, or will evict something that needs to stay
   loaded — on this machine the resident set matters more than any one
   model's quality.

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

11. **Never commit keys.** API keys, provider keys, and `.env` files stay
    out of git. Tokens live in `~/.config/hearth/env` (mode 600) and Zed's keychain.
    Never read or print that file's contents yourself — scripts source it;
    check it with `ls -l` only.

## Workflow

Plan → operator refines → operator approves → build. Do not start building because
a plan looks obviously right.

Be concise. No preamble, no restating the question, no long summary of what you did.
If the same tool error gets the same fix twice, stop, state the options, and ask.

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
scripts/             omlx, benches, sandbox, aliases
bench/tasks/         fixed prompts for model comparison
```
