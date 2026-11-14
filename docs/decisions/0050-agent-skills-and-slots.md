# ADR 0050 — Agent skills on main-brain; critique uses a second slot

**Date:** 2026-11-15
**Status:** accepted 2026-11-15 by the operator.
**Amends:** nothing. Uses ADR 0048 resident slots.

## Context

Editors and agents need shared eng discipline (assumptions, minimal change,
done-when) and a small write / critique loop. External packs (Karpathy
guidelines, aihero skills, pstack fan-out) show the shape. Hearth must keep
work on `*-brain`, use roles not model names, and fit the resident set.

`main-brain` is resident at 256K × 3 on every tier (ADR 0048). That is enough
for a small fan-out. `coding-brain` is one slot and evicts main. `deep-brain`
also evicts.

## Decision

- **Principles** live in `rules/user-bootstrap.md` (Karpathy four). Installed
  by `scripts/install-global-rules.sh`. Always on. Short.
- **Skills** are on demand: `hearth-review` (critique, no edits) and
  `hearth-implement` (plan-approved changes). Under `.claude/skills/`.
- **Fan-out** (implement + review in parallel) runs only while `main-brain`
  is resident. Use at most three concurrent local calls. Never beside
  `coding-brain` or `deep-brain`.
- **No new role** for a reviewer. Same resident role, different skill.
  A second model needs a bench first (rule 5).
- Do not invent more skills until the same failure repeats
  (`rules/user-bootstrap.md`).

## Consequences

- Critique of sensitive work stays on a brain (rule 3).
- Swap roles remain single-slot sessions; skills must say so.
- Editors that cannot load skills still get principles via
  `install-global-rules.sh`.
