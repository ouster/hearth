---
name: hearth-implement
description: >-
  Plan-approved Hearth changes: ADR when needed, roles not model names,
  minimal diff, prove with the named checks. Use when the person says
  "implement", "do it", "build that", or approves a plan. Pair with
  hearth-review on a second main-brain slot when a critique pass is wanted
  (ADR 0050).
---

# Hearth implement

Turn an approved plan into a small, correct change. Principles in
`rules/user-bootstrap.md` apply. Workflow: plan → refine → **approve** →
build (CLAUDE.md). Do not start building because the plan looks right.

## Before any edit

1. Confirm approval (or that this turn’s “do it” / “implement” is the OK).
2. Restate done-when in one or two lines.
3. If routing, roles, or serving behaviour changes → draft or update an ADR
   in `docs/decisions/` first (rule 8).
4. If fan-out with `hearth-review`: only while `main-brain` is resident;
   ≤3 concurrent local calls. Never beside `coding-brain` / `deep-brain`.

## While building

- Touch only what the task needs. Match local style.
- Roles everywhere except `config/roles.tsv` and `docs/MODELS.md`.
- Never route sensitive data to cloud. Never put model tags in aliases.
- Shell: bash 3.2-safe, LF only.
- Do not read or print `~/.config/hearth/env`, `~/.hearth-key`, or tunnel keys;
  `ls -l` for permissions only.

## After

- Run the checks named in done-when (preflight, healthcheck, a script, a
  ping — whatever the plan said).
- Update `docs/HISTORY.md` when behaviour or an ADR landed.
- Commit only when the person asks.

## If stuck

Same tool error twice with the same fix → stop, list options, ask.
