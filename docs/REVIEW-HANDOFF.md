# Review handoff: the LM Studio migration

For an AI reviewer (Cursor, Zed, Claude Code) working in a clone of this repo.
Written 2026-10-31. **Review only: change nothing, run nothing that mutates
state.** Report findings; the operator decides what gets fixed.

## Scope

```bash
git log --oneline 8e9ecf2..HEAD     # ~20 commits, all 2026-10-31
git diff --stat 8e9ecf2 HEAD        # bench/results/ is most of the line count — skim it
```

The hearth stack moved from **LiteLLM + Ollama + Postgres** (a gateway on
`:4000`) to **the LM Studio app serving directly on `127.0.0.1:1234`**. The
old stack is deleted, the scripts are rewritten, host clients are cut over,
and laptops reach the host over an SSH tunnel only. Read these first, in this
order:

1. `CLAUDE.md` — the hard rules. Everything is reviewed against them.
2. `docs/decisions/0016-lmstudio-direct.md` — the decision.
3. `docs/MIGRATION-LMSTUDIO.md` — phases, status table, decisions D1–D8.
4. `docs/ARCHITECTURE.md`, `docs/ROUTING.md`, `docs/THREAT-MODEL.md`.

## What to review, highest risk first

| # | Area | Files | Questions |
|---|---|---|---|
| 1 | **Privacy by placement** | `config/roles.tsv`, `scripts/lms-load.sh`, `scripts/aliases.zsh`, `client/*`, `scripts/webui.sh`, `scripts/sandboxed.sh` | Can anything sent to `:1234` reach a cloud model? Does any path other than `ask-cloud` carry a cloud key? Can a sandboxed agent reach anything but `127.0.0.1:1234`? |
| 2 | **Secrets** | `scripts/lib.sh` (`ai_load_env`, `hearth_http`), `client/hearth-client.sh` / `.ps1`, `scripts/aliases.zsh`, `scripts/preflight.sh` | Is a token or key ever exported, put on a command line (visible in `ps`), logged, or written somewhere other than a mode-600 file? `hearth_http` passes it via `curl -K -` for this reason. The `.ps1` sets `$env:` vars for the child — is the cleanup sound? |
| 3 | **Laptop access (D8)** | `scripts/client-setup.sh`, `docs/LAPTOP.md`, the `CLAUDE.md` "Which machine" block | The `authorized_keys` line is `command="/usr/bin/false",restrict,port-forwarding,permitopen=...`. Is the key really tunnel-only? Does `--authorize` refuse and back up correctly? Are the AI-assisted setup instructions safe for a cloud assistant (never sees a secret)? |
| 4 | **Server exposure** | `scripts/boot.sh`, `scripts/healthcheck.sh` | LM Studio rewrites its saved settings on `lms server start`. Is `127.0.0.1` + no CORS enforced on every start path, and checked? Does each negative test (401, no LAN, no CORS, JIT off) have a positive control? |
| 5 | **Login autostart** | `scripts/install-autostart.sh`, `scripts/boot.sh` | launchd `RunAtLoad` + `AbandonProcessGroup` (without it, launchd killed the Podman VM). Failure modes if LM Studio is slow to start, or Podman is missing? |
| 6 | **Exit codes** | every script | `0` pass, `1` real problem, `2` could not run. Can a missing dependency ever report as `1`, or a failure as `0`? |
| 7 | **Portability** | `scripts/*.sh`, `client/hearth-client.sh` | macOS `/bin/bash` 3.2: no `declare -A`, `mapfile`, `${x^^}`; empty arrays guarded under `set -u`. `client/hearth-client.sh` must run in bash *and* zsh on macOS and Linux. Python in heredocs: no heredoc + pipe both on stdin. |
| 8 | **Model-name rule** | everything | Concrete model names only in `config/roles.tsv` and `docs/MODELS.md` (plus generated Zed labels and redacted bench results). `grep` for any that leaked. |
| 9 | **Weight pinning (D4)** | `scripts/pin-digests.sh`, `pins/digests.tsv` | Does `--check` really detect a changed file? Does any doc imply roles are *immutable* rather than drift-detected? |
| 10 | **Docs drift** | `README.md`, `docs/*.md` | Any instruction still pointing at `:4000`, `:11434`, LiteLLM, virtual keys, Postgres, Ollama or `llmster` *as current*? Superseded ADRs and docs marked **Historical** are expected to mention them. Do the docs match what the scripts actually do? |
| 11 | **Benches** | `bench/concurrency.py`, `scripts/concurrency-bench.sh`, `bench/results/2026-10-31-*` | Do the reports' conclusions follow from the numbers? Is the c3 TTFT comparison (LM Studio vs Ollama) like for like? |

## Known and accepted — don't report these as new

- No soak week before deleting the old stack (operator's call). Rollback is
  not possible; ADR 0016 says so.
- With JIT off, an unknown model name is answered by `local-big` instead of
  refused. `healthcheck.sh` warns about it.
- LM Studio auth and tokens are GUI-only; there is no CLI (lmstudio-ai/lms#489).
- Prefill is serialised even with `--parallel 3`; recorded in the phase 0/1 reports.
- Phase 4's laptop gate has not been run yet.
- Cursor cannot use hearth as a model provider (its backend makes the calls).

## Also changed, outside the repo (host only)

Described so you don't have to look. Ask the operator before opening any of
these, and never open the ones in the next section.

- `~/.config/zed/settings.json` — `hearth` provider at `127.0.0.1:1234`,
  every model slot `hearth/local-main`. The legal-research profile recorded
  during phase 3 is no longer installed; `docs/MCP.md` preserves it as a
  worked setup example.
- `~/.aider.conf.yml` — `openai/local-big` for model and weak model.
- `~/.zshrc` — sources `scripts/aliases.zsh`; Ollama exports removed.
- `~/Library/LaunchAgents/com.hearth.boot.plist` — written by `install-autostart.sh`.
- `~/.ssh/authorized_keys` — gets one restricted line per laptop.

## Off limits

You are probably a cloud model; whatever you read goes to your vendor.
**Never open, print, grep or copy:**

- `~/.config/hearth/env` — LM Studio token and Google key
- `~/.zshenv.local*` — a backup there still holds a key
- `~/hearth-backups/` — old database dumps
- `~/.lmstudio/.internal/` — server settings, token hashes
- `~/.hearth-key`, `~/.hearth-gemini-key`, `~/.ssh/` on any machine

## What you may run

Read-only, on the host only, all safe to repeat (exit codes as above):

```bash
scripts/preflight.sh
scripts/healthcheck.sh
scripts/install-autostart.sh --check
scripts/lms-load.sh --check
scripts/pin-digests.sh --check
scripts/zed-sync.sh --check
bash -n scripts/*.sh client/hearth-client.sh
```

**Don't run:** `boot.sh`, `lms-load.sh` (without `--check`),
`install-autostart.sh --apply/--remove`, `client-setup.sh --authorize/--install`,
`swap-role.sh`, `bench.sh`, `concurrency-bench.sh`, `pull-candidates.sh`,
`pin-digests.sh` (without `--check`), `zed-sync.sh` (without `--check`),
anything with `lms load/unload/server`, `podman`, `launchctl` or `sudo`.
On a laptop, run none of `scripts/`.

If you're Zed on `local-big` (128K context, ADR 0017), review one area from the table
per thread rather than the whole diff at once.

## How to report

One finding per item, most severe first:

- **Severity:** critical (privacy or secret leak) / high (wrong result,
  broken check) / medium / low (docs, style)
- **Where:** `path:line`
- **What:** one sentence
- **Failure scenario:** concrete inputs or state → what goes wrong
- **Confidence:** confirmed (you ran or traced it) / plausible

Say which areas you reviewed and which you didn't. "No findings" for an area
is a useful answer, but only with a line on what you checked.
