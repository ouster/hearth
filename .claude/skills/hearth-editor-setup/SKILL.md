---
name: hearth-editor-setup
description: Connect an editor or agent to Hearth's local-main, then prove it with three checks. Covers VS Code (Custom Endpoint), Cline (Desktop, VS Code, JetBrains, CLI), JetBrains AI Assistant and Zed, plus the loop guard. Works on the host and on laptops. Use when the person says "set up VS Code / Cline / PyCharm / Zed for hearth", "add the local model to my editor", "test the loop guard" or "the agent keeps looping".
---

# Hearth editor setup

Source of truth: README → *Editors*, and `docs/IDES.md` for detail and
what is not yet verified. Read the section for the editor in question
before acting.

## Ground rules

- Every editor calls the **role** `local-main` at `http://127.0.0.1:1234/v1`.
  Never write a model name (rule 1). Never offer `local-deep` unless the host
  has it loaded.
- **No cloud provider on the host** in any editor (rule 3). On a laptop,
  never pick a vendor's own cloud provider for sensitive repos.
- **Keys:** the person types or pastes them into the editor's own key
  field. Never read key files, and never ask for a key in the chat.
- On a laptop, the tunnel must be up first. `ai-ping` should say `up`; if it
  does not, use `hearth-laptop-setup`.
- Ask which key to use: the laptop key, or a per-editor sub-key
  (`<editor>-<machine>`, created on the host). The trade-off is per-editor
  revocation.

## VS Code (1.122 or later)

Files are in `~/Library/Application Support/Code/User/`.

1. `code --version`. If it is older than 1.122, ask the person to update.
2. `settings.json` is JSONC. Merge in the block from
   `scripts/vscode-check.sh --show`, keeping existing keys. Back it up to
   `settings.json.bak` first. Get the person's OK before writing.
3. `chatLanguageModels.json`: write the `hearth` provider in the README's
   format **without `apiKey`**. Do not set a provider-level `url`: it would
   list `local-deep`. Then the person sets the key in **Chat: Manage
   Language Models** → `hearth`. VS Code stores it in its secret store and
   writes a `${input:…}` reference itself. A placeholder you type by hand
   fails with "API key required".
4. In Chat, pick `local-main` and the **Local** session target. Agent mode
   must be on (`chat.agent.enabled`).
5. `scripts/vscode-check.sh` must exit 0. Show any FAIL lines.

## Cline (Desktop, VS Code, PyCharm, CLI)

1. Provider → BYOK → Add Provider (OpenAI Compatible). ID `hearth`. Base URL
   as above. **Model Source URL empty.** Model `local-main`. Capabilities:
   streaming, tools, reasoning. Prompt cache off. Context 131072.
2. **Never** select Cline Usage-Billing or ClinePass. Telemetry off
   (General).
3. **Composio connectors off.** If the agent offers a Slack or Composio auth
   link, tell the person not to click it (README → *Cline*).
4. Enable Hooks, then `scripts/install-loop-guard.sh` once. This is
   laptop-safe; it writes `~/Documents/Cline/Hooks/PreToolUse`.

## JetBrains AI Assistant

Settings → Tools → AI Assistant → Providers & API keys → OpenAI Compatible.
Assign `local-main` by hand to every feature, and turn offline mode on for
sensitive repos. It has no hooks, so for guarded agent work, use the Cline
plugin.

## Zed

README → *Zed*. Keep `agent.tool_permissions.default: "confirm"`. On the
host, `scripts/zed-sync.sh` writes the labels. Zed has no hooks, so the loop
guard does not cover it. Tell the person this, and point to the mitigations
listed there.

## Prove it: three checks per client, with the hearth folder open

| # | Ask the person to | Pass |
|---|---|---|
| 1 | Set the base URL to `http://127.0.0.1:1299/v1` and send a prompt; then set it back | It **fails** with a connection error. If it answers, it is using a cloud provider: stop |
| 2 | "Create `scratch-smoke.sh` containing `if [[ $x < 1 ]]; then echo hi; fi`, read it back, then delete it" | All three steps succeed, and the `<` survives |
| 3 | "Read `AGENTS.md` three times in a row with the read tool. Don't change anything" | The third call is refused, or in Cline the task stops |

After check 3, run `tail -3 ~/Library/Logs/hearth-loop-guard.log` yourself.
Expect a `vscode deny` or `cline deny` line. The log holds no tool
arguments.

Optional: "Quote what your rules say about the same tool error twice.
Don't read any files." This shows whether `AGENTS.md` is loaded. If the
answer lists another project's rules, the workspace is the wrong folder.

## Record results (only when asked)

Add one line per client to `docs/HISTORY.md` (the ADR 0036 row) and to the
*Consequences* list in `docs/decisions/0036-vscode-cline-trial.md`: the
date, client and version, and which checks passed.
