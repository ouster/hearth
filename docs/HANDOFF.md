# Handoff: model-proxy (ADR 0051) and agent skills (ADR 0050)

Written 2026-11-15. Read `CLAUDE.md`, then
`docs/decisions/0050-agent-skills-and-slots.md` and
`docs/decisions/0051-model-proxy.md`.

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

## ADR 0051 / model-proxy — rewritten, proposed

Loopback proxy on `:1238` adds `display_name` to `/v1/models`. Rewritten
2026-11-15 after review; the ADR has the failures and the proof table.

- No key: the client's `Authorization` passes through. Keyless → 401.
- Threaded, streams per read, 502 when oMLX is down, exit 2 if roles cannot
  be resolved. Local oMLX only; no remote mode.
- The root-daemon installer (`companion-proxy.sh`) is deleted. The user
  agent `com.hearth.model-proxy` is installed by
  `scripts/install-autostart.sh --apply`.
- Preflight: fails if the plist exists and `:1238` is silent, or if a
  keyless `/v1/models` through it returns 200.

### Still to do

1. **Cline picker:** check by hand that it shows `display_name`. If not,
   remove the proxy. Then the operator accepts or rejects ADR 0051.
2. On acceptance, add `:1238` to the README, the `docs/ARCHITECTURE.md`
   diagram and the `hearth-editor-setup` skill.

Installed on this machine 2026-11-15 (`scripts/install-autostart.sh --apply`);
preflight shows it listening on `:1238` and adding no key.

### Dual URL (hearth vs hearth-remote)

| Provider | Correct |
|---|---|
| `hearth` | `:1238` (labels) or `:1234` (direct) |
| `hearth-remote` | tunnel `:1235` only — never the local proxy |

## coding-brain in Cline

Role is fine for code; tool naming is weak. It invents `edit` when Cline’s
tool is `editor` (`AI_NoSuchToolError`), then often retries. Prefer
`main-brain` for agentic Cline; use `coding-brain` after
`hearth-load coding-brain up` when you want that swap. Load runs on the
**client** (tunnel → swapd), not on a shell on the host.

## Earlier (0048 / 0049) — still the swap path

Laptop/dual: `hearth-load coding-brain up` / `down`; dual aider name is
`coding-brain-remote`. Host fallback: `scripts/demand-load.sh`. See
previous handoff content in git history if swapd prove steps are needed.

## Open outside this thread

| # | Problem |
|---|---|
| 1 | 48 GB `262144 × 3` unbenched on 48 GB hardware |
| 2 | Weight pins / digests drift across machines |
| 3 | Vision / VLM as a swap role — research only, not benched |
| 4 | `stash@{0}` pre-0048 garbled docs — drop when safe |

Workflow: plan → operator approves → build.
