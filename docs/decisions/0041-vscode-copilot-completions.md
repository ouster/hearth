# ADR 0041 — Allow VS Code Copilot completions, except in sensitive repos

**Date:** 2026-11-08
**Status:** accepted 2026-11-08 by the operator. Amends ADR 0036.

## Context

ADR 0036 put VS Code on trial with chat and agent on `main-brain` through a
Custom Endpoint, and kept Copilot inline completions, next edit suggestions
(NES) and code search off, because they go to GitHub even with your own
chat model. `scripts/vscode-check.sh` failed when they were on.

The operator wants ghost text and NES in VS Code. Host oMLX does not serve
edit prediction (ADR 0033), and VS Code has no supported way to point Copilot
completions at a local endpoint.

## Decision

- Copilot inline completions and NES are **allowed** in VS Code. They send
  the text around the cursor, and snippets from other open tabs, to GitHub.
  They need a GitHub sign-in and a Copilot plan; chat still does not.
- A repo flagged sensitive (rule 3) turns both off in its own
  `.vscode/settings.json` (`scripts/vscode-check.sh --show-sensitive`).
  Workspace settings override user settings. On a personal plan this is the
  only per-repo switch: Copilot content exclusion is a Business/Enterprise
  feature.
- `scripts/vscode-check.sh` reports completions and NES as on or off instead
  of failing. `--workspace DIR` fails unless DIR has the opt-out.
- Unchanged: chat, agent and utility models stay on `main-brain` at a
  loopback endpoint; Copilot code search stays off; telemetry off. Zed's
  edit prediction rule (ADR 0033) is unchanged.

## Consequences

- Code from non-sensitive repos reaches GitHub as you type in VS Code.
- The safeguard for sensitive repos is a file in each one, and it only
  covers the window that repo is opened in. Sensitive files opened in another
  repo's window are sent; open sensitive work in its own window.
- Nothing lists the sensitive repos; the opt-out file is the marker, and
  `--workspace` checks one repo at a time.
