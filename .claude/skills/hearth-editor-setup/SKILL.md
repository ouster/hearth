---
name: hearth-editor-setup
description: Connect an editor or agent to Hearth's coding-brain (default resident on 64 GB), then prove it with three checks. Covers VS Code (Custom Endpoint), Cline (Desktop, VS Code, JetBrains, CLI), OpenCode, JetBrains AI Assistant and Zed, plus the loop guard. Works on the host and on laptops. Use when the person says "set up VS Code / Cline / OpenCode / PyCharm / Zed for hearth", "add the local model to my editor", "test the loop guard" or "the agent keeps looping".
---

# Hearth editor setup

Source of truth: README → *Editors*, and `docs/IDES.md` for detail and
what is not yet verified. Read the section for the editor in question
before acting.

## Ground rules

- Every editor defaults to the **role** `coding-brain` at
  `http://127.0.0.1:1234/v1` (resident on 64 GB, ADR 0047). Never write a
  model name (rule 1). List `main-brain` and `deep-brain` only as optional
  picks; tell the person to run `scripts/demand-load.sh <role> up` on the
  host before selecting either, or the resident may answer silently.
- **No cloud provider on the host** in any editor (rule 3). On a laptop,
  never pick a vendor's own cloud provider for sensitive repos.
- **Keys:** the person types or pastes them into the editor's own key
  field. Never read key files, and never ask for a key in the chat.
- **Dual machine** (its own brain and a tunnel, ADR 0040): add two
  providers. `hearth` points at `http://127.0.0.1:1234/v1` (this machine) and
  `hearth-remote` at `http://127.0.0.1:1235/v1` (the bigger host). Both call
  `coding-brain` by default; the provider name says which machine answers.
  Sensitive work may use either, since both are the person's own hardware
  (rule 3).
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
   list every role. Default model id `coding-brain` (max input ~90000 for
   the 98K window). Optionally add `main-brain` (245760) for after
   demand-load. Then the person sets the key in **Chat: Manage
   Language Models** → `hearth`. VS Code stores it in its secret store and
   writes a `${input:…}` reference itself. A placeholder you type by hand
   fails with "API key required".
4. In Chat, pick `coding-brain` and the **Local** session target. Agent mode
   must be on (`chat.agent.enabled`).
5. `scripts/vscode-check.sh` must exit 0. Show any FAIL lines.

## Cline (Desktop, VS Code, PyCharm, CLI)

Follow README → *Cline* (past Sign in + field + models tables). Short form:

1. **Past Sign in:** Get started → **Use your own API key** (skip Sign in /
   Sign up) → OpenAI Compatible. Later: Settings → Provider → BYOK → Add
   Provider.
2. Provider `hearth`, Base URL as above, Model Source URL empty. Add all
   three models: `coding-brain` (98304, default), `main-brain` (262144),
   `deep-brain` (65536). Capabilities: streaming, tools, reasoning;
   prompt cache off. Person pastes the key. Cline does **not** load
   weights — host runs `demand-load.sh` before a swap role.
3. **Never** Sign in / Usage-Billing / Cline Pass. Telemetry off (General).
4. **Composio connectors off.** If a Slack or Composio auth link appears,
   tell the person not to click it.
5. Enable Hooks, then `scripts/install-loop-guard.sh` once (laptop-safe;
   writes `~/Documents/Cline/Hooks/PreToolUse`).

## OpenCode (trial, ADR 0043)

1. Confirm `opencode` is on PATH. If not, point the person at
   [opencode.ai](https://opencode.ai) install docs.
2. Ask them to run `scripts/omlx.sh sub-key add opencode-<machine>` on the
   host (they type the token). On a laptop, `ai-tunnel` first.
3. Help them write `~/.config/opencode/opencode.json` from the README
   *OpenCode* block: provider `hearth`, model `hearth/coding-brain`, list
   `coding-brain` (and optionally swap roles), base URL as above. They paste
   the sub-key; you never read or write the key value. `chmod 600` the file
   if it holds the key.
4. No cloud / OpenRouter provider on the host for sensitive work.
5. `scripts/install-loop-guard.sh` once, then restart OpenCode. Check 3
   (triple read) should throw via the plugin; log line format is
   `opencode deny`.

## JetBrains AI Assistant

Settings → Tools → AI Assistant → Providers & API keys → OpenAI Compatible.
Assign `coding-brain` by hand to every feature, and turn offline mode on for
sensitive repos. It has no hooks, so for guarded agent work, use the Cline
plugin. Demand-load before assigning `main-brain` or `deep-brain`.

## Zed

README → *Zed*. Keep `agent.tool_permissions.default: "confirm"`. On the
host, `scripts/zed-sync.sh` writes the labels (including `× slots`). Zed has
no hooks, so the loop guard does not cover it. Tell the person this, and
point to the mitigations listed there. Default model is `coding-brain`.

## Prove it: three checks per client, with the hearth folder open

| # | Ask the person to | Pass |
|---|---|---|
| 1 | Set the base URL to `http://127.0.0.1:1299/v1` and send a prompt; then set it back | It **fails** with a connection error. If it answers, it is using a cloud provider: stop |
| 2 | "Create `scratch-smoke.sh` containing `if [[ $x < 1 ]]; then echo hi; fi`, read it back, then delete it" | All three steps succeed, and the `<` survives |
| 3 | "Read `AGENTS.md` three times in a row with the read tool. Don't change anything" | The third call is refused, or in Cline the task stops |

After check 3, run `tail -3 ~/Library/Logs/hearth-loop-guard.log` yourself.
Expect a `vscode deny`, `cline deny`, or `opencode deny` line. The log
holds no tool arguments.

Optional: "Quote what your rules say about the same tool error twice.
Don't read any files." This shows whether `AGENTS.md` is loaded. If the
answer lists another project's rules, the workspace is the wrong folder.

## Record results (only when asked)

Add one line per client to `docs/HISTORY.md` (the ADR 0036 row) and to the
*Consequences* list in `docs/decisions/0036-vscode-cline-trial.md`: the
date, client and version, and which checks passed.
