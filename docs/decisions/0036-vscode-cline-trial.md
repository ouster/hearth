# ADR 0036 — VS Code and Cline on trial beside Zed, with a shared loop guard

**Date:** 2026-11-08
**Status:** trial. Accepted by the operator 2026-11-08. Zed and aider stay; nothing is replaced until the trial gates pass.

## Context

The operator wants agentic work in VS Code, where the flow can be
customised and looping prevented, and wants Cline (VS Code, JetBrains and
CLI) tried too.

Zed's loops (ADR 0023, 0024) came from threads growing past the 131K
window. The old server trimmed the middle of the prompt without saying so,
and the agent repeated work it could no longer see. oMLX refuses an
oversized prompt instead (`docs/IDES.md`, Zed compaction). That failure is
now loud. What is left is a model repeating the same tool call. A
different editor does not fix that. A guard on tool calls might.

Vendor docs, read 2026-11-08 (not tested on this host):

- **VS Code** (docs pages dated 2026-11-04). The Custom Endpoint provider
  (`customendpoint`, Chat Completions) reaches an OpenAI-compatible server.
  The Local harness uses it without a GitHub account from 1.122. Agent
  hooks have been a preview since 1.109: a `PreToolUse` hook can deny a
  call, and a hook can end the run with `continue: false`. The setting
  `chat.agent.maxRequests` caps requests per prompt (default 25). Inline
  completions, next edit suggestions, semantic search and embeddings still
  go to GitHub's service. VS Code's own docs say hooks are not enforcement.
- **Cline**. It has an OpenAI Compatible provider. A `PreToolUse` hook in
  `.clinerules/hooks/` or `~/Documents/Cline/Hooks/` can return
  `{"cancel": true}`. It reads `AGENTS.md`. Telemetry is on by default and
  documented as excluding code and prompts unless the Cline provider is
  used. The same extension ships for JetBrains (Marketplace 28247) and as
  a CLI. The docs show no max-requests setting and no built-in loop
  detection.

The host had VS Code 1.107, which is too old for both features.

## Decision

1. **VS Code and Cline go on trial for local agent work.** Both use
   `local-main` at `127.0.0.1:1234`, called by role, each with its own
   oMLX sub-key. Neither gets a cloud provider on the host (rule 3, D3).
2. **Off on the host:** Copilot inline completions, next edit
   suggestions, Copilot code search, VS Code telemetry, Cline telemetry,
   Cline's own provider, Cline's Composio connectors, and Cline auto-approve
   for web fetch.
   `scripts/vscode-check.sh` checks the VS Code settings, and preflight
   warns if any of these is on.
3. **One loop guard, `scripts/loop-guard.sh`, for every hook-capable
   client.** It denies a tool call that repeats the same call
   `HEARTH_LOOP_REPEAT` times in a row (default 3), and ends the task after
   `HEARTH_LOOP_BUDGET` tool calls (default 80). It keeps state per session
   and resets after 30 idle minutes. This repo wires it in
   `.github/hooks/` and `.clinerules/hooks/`.
   `scripts/install-loop-guard.sh` installs it globally for other repos.
   It fails open: a guard that errors allows the call. It is a brake, not
   a control (ADR 0007 still holds).
4. `chat.agent.maxRequests` is set to 40 in VS Code, as a second limit
   that does not depend on hooks.

## Consequences

- **Gates before VS Code or Cline is recommended over Zed:**
  `scripts/tool-smoke.sh` still passes, and a real agent task in each
  client completes against oMLX's token check. Also, a deliberately
  repeated call is denied by the guard in each client. Record the results
  in `docs/HISTORY.md`.
- **2026-11-08:** `bench/tool-smoke.py` passed against `local-main` through
  a laptop's `ai-tunnel` (two reads, then a write that kept `<`). The first
  gate is met. The client gates are still open.
- **2026-11-08, Cline Desktop and PyCharm:** both used the `hearth`
  provider, and both completed write → read → delete with `<` intact. The
  global hook stopped the third identical `read_files` in both, logged
  under two separate session ids. Composio connectors (`COMPOSIO_BETA`,
  pushed to signed-in Cline accounts) are a new egress path. They are
  added to the off list. No-fallback: with the base URL on a dead port, Cline
  failed with ConnectionRefused rather than answering from elsewhere. Still
  open: the rules test in a hearth workspace (the first run was in a Zed
  checkout).
- **2026-11-08, VS Code 1.144.1:** with a Custom Endpoint on `local-main` and
  the Local target, the workspace hook (`.github/hooks/`) refused the third
  identical `read_file` (`vscode deny` in the log). The key is set through
  Manage Language Models, which keeps it in VS Code's secret store and
  writes a `${input:…}` reference into the file.
- **Not verified:** whether VS Code's Custom Endpoint passes oMLX's token
  check, whether Cline's JetBrains plugin runs workspace hooks, and the
  exact stdin field names on this version. The guard accepts every
  documented shape and allows the call when it cannot read one.
- Hooks are preview features in both clients. Re-run the guard check after
  an upgrade.
- Zed has no tool hooks, so the guard does not cover it. Zed keeps its
  compaction at 110K and its `confirm` tool permissions.
- `AGENTS.md` already carries the rule "same tool error, same fix, twice →
  stop and ask". Both clients read it. It guides the model and does not
  enforce anything.
