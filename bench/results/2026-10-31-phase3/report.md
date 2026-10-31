# Phase 3 — host clients cut over

**Date:** 2026-10-31. **Plan:** `docs/MIGRATION-LMSTUDIO.md` phase 3.
**Server:** LM Studio app 0.4.28 on `127.0.0.1:1234` (D6 changed to the app
during this phase), `local-big` 64K × 3 parallel, `local-embed`.

| Gate item | Result | Evidence |
|---|---|---|
| Zed agent session, ≥ 20 tool calls, two threads at once, no stall | **pass** | operator: both threads completed in ~1 min, no stall |
| aider `ask` | **pass** (operator: local-big working) | alias builds `openai/local-big` at `:1234`, token per call |
| aider `ask-cloud` | **pass** (operator) | the earlier errors were a bare `aider ask-cloud` run; also found `GOOGLE_API_KEY` exported from `~/.zshenv.local` into every shell — moved to `~/.config/hearth/env` |
| sandbox-probe | **pass** | 11/11, incl. new deny check on old `:4000` |
| Open WebUI answers | **pass** (operator) | saved connection still pointed at `:4000` (database wins over env); repointed in Admin → Connections to `:1234` with the host token |

Also verified: Zed settings load cleanly on Zed 1.26.2 (a partial Write
profile override failed the whole load — fixed by a full profile); auslaw
enabled only in the Research profile; container → host `127.0.0.1:1234`
works with "serve on local network" off.

**Gate: passed 2026-10-31.**
