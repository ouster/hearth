# ADR 0043 — OpenCode on trial beside Zed, aider, VS Code and Cline

**Date:** 2026-11-09
**Status:** trial. Accepted by the operator 2026-11-09. Nothing is replaced
until the trial gates pass. T3 Code remote control stays deferred
(`docs/MOBILE.md`).

## Context

OpenCode is an agent harness (CLI / TUI / desktop) that talks to
OpenAI-compatible servers. oMLX already ships an OpenCode config writer.
Hearth needs the same discipline as other editors: call the role
`main-brain` at `127.0.0.1:1234`, a revocable sub-key, no cloud provider on
the host (rule 3), and a loop brake where hooks exist.

OpenCode has no Cline-style `PreToolUse` file. It loads JavaScript plugins
from `.opencode/plugins/` and `~/.config/opencode/plugins/`. A
`tool.execute.before` hook that throws refuses the call. T3 Code can drive
OpenCode later, but T3's FAQ (read 2026-11-09) rejects local models, so that
path is out of scope for this trial.

## Decision

1. **OpenCode goes on trial** for local agent work. Provider id `hearth`,
   model `main-brain`, base URL `http://127.0.0.1:1234/v1`, sub-key
   `opencode-<machine>`. Dual machines may add `hearth-remote` on `:1235`
   (ADR 0040).
2. **Config** lives in `~/.config/opencode/opencode.json` (mode 600 if it
   holds a key). Only `main-brain` is listed under the provider — no model
   catalogue that would offer `deep-brain`. Prefer the `provider` /
   `@ai-sdk/openai-compatible` shape oMLX writes today; if OpenCode 2.x
   renames fields, update `docs/IDES.md` rather than inventing a second
   stack.
3. **Loop guard:** `scripts/loop-guard.sh --format opencode` plus a small
   plugin that shells out to it and throws on deny. Wired in this repo under
   `.opencode/plugins/hearth-loop-guard/` and installed globally by
   `scripts/install-loop-guard.sh`. Fails open if the guard binary is
   missing (ADR 0007).
4. **Off on the host:** any OpenCode cloud / OpenRouter / subscription
   provider for sensitive work. Telemetry off when the setting exists.
5. **T3 Code** is not part of this trial. Revisit later (possibly a fork)
   if a phone control plane for local models is still wanted.

## Consequences

- **Gates before recommending OpenCode over Cline or Zed:** a real agent
  task completes against oMLX's token check (write → read → delete keeping
  `<`); a dead base URL fails with no cloud fallback; the third identical
  tool call is refused and logged. Record results in `docs/HISTORY.md`.
- Client gates are **open** until those runs are done on this host.
- Zed, aider, VS Code and Cline stay. OpenCode does not replace them.
- The plugin must tolerate OpenCode 1.x and 2.x load shapes (named export,
  `server()`, and `setup` / `ctx.tool.hook`) the way other third-party
  guards do; re-check after an OpenCode upgrade.
