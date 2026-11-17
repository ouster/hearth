# Handoff: agent skills (ADR 0050); proxy and swapd removed (ADR 0052)

Written 2026-11-15, updated 2026-11-16. Read `CLAUDE.md`, then
`docs/decisions/0050-agent-skills-and-slots.md` and
`docs/decisions/0052-drop-proxy-and-swapd.md`.

## Git

`main` is pushed to origin as of 2026-11-15, through the proxy rewrite and
the doc sweep that followed it.

## ADR 0050 — done enough

- Skills: `.claude/skills/hearth-review`, `hearth-implement`
- Bootstrap: Karpathy four in `rules/user-bootstrap.md` (installed via
  `scripts/install-global-rules.sh`)
- Fan-out ≤3 on resident `main-brain` only
- Extra always-on “Review / critique role” section in bootstrap was added
  by Cline; overlaps the skill. Trim later if it stays noisy

## ADR 0052 — proxy and swapd removed

`scripts/model-proxy.py` (`:1238`, ADR 0051, never accepted) and
`hearth-swapd` (`:1236` / `:1237`, ADR 0049) are gone, with `hearth-load`
and `HEARTH_SSH_ADMIN`. Editors use `:1234` (`hearth`) or the tunnel `:1235`
(`hearth-remote`). Swap roles load on the host that owns them.

Each other host still needs `scripts/install-autostart.sh --apply` and
`scripts/client-setup.sh --update-keys`; each laptop
`ai-tunnel-stop && ai-tunnel-install`.

## coding-brain in Cline

Role is fine for code; tool naming is weak. It invents `edit` when Cline’s
tool is `editor` (`AI_NoSuchToolError`), then often retries. Prefer
`main-brain` for agentic Cline; use `coding-brain` after
`scripts/demand-load.sh coding-brain up` on the host that owns it.

## Open outside this thread

| # | Problem |
|---|---|
| 1 | 48 GB `262144 × 3` unbenched on 48 GB hardware |
| 2 | Weight pins / digests drift across machines |
| 3 | Vision / VLM as a swap role — research only, not benched |
| 4 | `stash@{0}` pre-0048 garbled docs — drop when safe |

Workflow: plan → operator approves → build.
