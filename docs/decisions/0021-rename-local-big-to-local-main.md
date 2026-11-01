# ADR 0021 — Rename local-big to local-main

**Date:** 2026-11-01
**Status:** accepted 2026-11-01 by the operator.

## Context

`local-big` named the role by size. Since ADR 0019 it holds a 26B model,
smaller than `local-deep`'s 27B (ADR 0020), so the name no longer says what
the role is. `local-code` was considered and rejected: it is a retired role
name with a different history (ADR 0004, 0005, D1), and this role also
serves chat, not only code.

## Decision

The resident role is `local-main`: the always-loaded default, next to the
on-demand `local-deep`. Same model, context and slots; only the LM Studio
identifier and every client that names it change.

## Consequences

- Live files, scripts, clients, Zed settings, `~/.aider.conf.yml` and the
  `~/.zshrc` comment say `local-main`. ADRs, `docs/HISTORY.md`, bench results
  and the dated plan/review docs keep `local-big`: they record what it was
  called then.
- Open WebUI keeps its default model in its own database: set it to
  `local-main` in Admin Panel → Settings (or `scripts/webui.sh up`, then the
  same panel).
- Laptops need the updated client (`scripts/client-setup.sh <name> --install
  user@laptop`) and their Zed settings edited. Until then they ask for
  `local-big`, which JIT-off LM Studio answers with the loaded model anyway —
  the quirk `healthcheck.sh` warns about, not something to rely on.
- Alias names `ask-big`, `local-code` and `local-chat` stay as muscle-memory
  names for `local-main`.
