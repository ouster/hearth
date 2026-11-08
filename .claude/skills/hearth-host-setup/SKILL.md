---
name: hearth-host-setup
description: Set up, repair or re-check the Hearth HOST, the Mac that runs oMLX on 127.0.0.1:1234. Covers weights, the host token, oMLX up, autostart, the GPU wired limit, digest pins, the final preflight and healthcheck, and registering a laptop or editor key. Use when the person says "set up the host", "first-time setup", "fix the host", "register a laptop" or "add a sub-key". Never on a laptop; use hearth-laptop-setup there.
---

# Hearth host setup

You are helping the operator set up the machine that serves `main-brain`.
The docs are the source of truth. This skill gives the order, the stops,
and the checks. Read the doc section named at each step before acting.

## 0. Confirm this is the host, before anything else

| Signal | Means |
|---|---|
| `~/.hearth-key` or `~/.ssh/hearth_tunnel` exists | a laptop. **Ask** whether it should also be a host (ADR 0040). If yes: `client/install-client.sh --dual` first, then continue here. If no: use `hearth-laptop-setup` |
| `~/.config/hearth/env` exists | host, already partly set up |
| neither, and `~/.omlx` exists | unclear: a laptop running `edit-brain` also has `~/.omlx`. **Ask** |
| neither | fresh machine: **ask** whether it is the host |

Check these with `ls -l` only. Never open the files.

## Rules that apply throughout

- **Plan, then wait.** List the steps you will run and get the operator's
  OK before changing anything (CLAUDE.md, *Workflow*).
- **Never read, print or grep** `~/.config/hearth/env`, `~/.omlx/settings.json`
  token fields, `~/.hearth-key` or any key file. Scripts source them. You may
  run `ls -l` on them. The operator types every token in their own terminal.
- **No model names** in anything you write, except `config/roles.tsv` and
  `docs/MODELS.md` (rule 1). Call roles.
- Never suggest commands against `:4000`, `:11434`, LiteLLM or Postgres.
  That gateway was removed.
- If the same step fails twice with the same fix, stop, list the options,
  and ask.

## 1. First-time setup (README *Quick start*, `docs/RUNBOOK.md` *First-time setup*)

Start with `scripts/install-host.sh --check`. It runs the steps below in
order and says which need the operator. Then run it without `--check`; it
starts oMLX only when nothing above needs them. The detail per step:

1. **oMLX installed.** Use the DMG app or the headless venv (README *Install
   oMLX*, sequences A–C). Ask which one; do not choose for them.
2. **Weights** go at `~/.hearth/models/<path from roles.tsv>`, with sources
   in `docs/MODELS.md`. Check RAM first: rows have a `min_ram` tier (ADR
   0032), and the ceiling is installed RAM minus 8 GB (rule 7). Say if a role
   will not fit.
3. **Host token.** The operator runs the RUNBOOK step 2 command in their
   own terminal. Afterwards, check `ls -l ~/.config/hearth/env` shows
   `-rw-------` and a non-zero size.
4. `scripts/omlx.sh up`, then `scripts/omlx.sh status`.
5. `scripts/iogpu-wired.sh`. It needs sudo, so the operator runs it.
6. `scripts/install-autostart.sh --apply`, then `--check`.
7. Shell aliases: `echo "source $PWD/scripts/aliases.zsh" >> ~/.zshrc`,
   if it is not there already.
8. Pins: `scripts/pin-digests.sh --check`. Re-record pins only after a
   re-bench (rule 6), and never just to make a check pass.

## 2. Prove it

Run both and show the operator the summary lines:

```bash
scripts/preflight.sh      # 0 pass, 1 real problem, 2 could not run
scripts/healthcheck.sh    # token 200, no/wrong token 401, roles answer
```

Report every FAIL with the fix the script names. Do not fix the
*Secrets* or *Weight drift* sections on your own initiative: they involve
tokens or re-benching. Ask first.

## 3. Register a laptop (`docs/LAPTOP.md` *Setup*)

1. Ask for the laptop's short name: letters, digits, `-`, `_`, for example
   `m5-air`. `scripts/omlx.sh sub-key list` shows whether it exists.
2. `scripts/client-setup.sh <short-name>` prints every step with this host
   filled in (`--windows` for PowerShell). Show it to the operator.
3. New machine: the operator runs `scripts/omlx.sh sub-key add laptop-<short-name>`
   and types the token. The prompt does not echo. The same token goes into
   the laptop's `~/.hearth-key`, which the laptop user types themselves.
4. When the laptop's `hearth_tunnel.pub` arrives:
   `scripts/client-setup.sh <short-name> --authorize hearth_tunnel.pub`.

## 4. A key for one editor (optional)

Use one per editor when the operator wants to revoke it on its own:
`scripts/omlx.sh sub-key add <editor>-<machine>`, for example
`vscode-m5-air`, `cline-m5-air` or `jetbrains-m5-air`. Reusing the laptop
key also works; you only lose per-editor revocation. Revoke a key with
`scripts/omlx.sh sub-key revoke <name>`.

## Done when

`preflight.sh` and `healthcheck.sh` exit 0, or every remaining FAIL has
been named to the operator with its fix. For editors, hand over to
`hearth-editor-setup`.
