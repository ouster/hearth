# Global engineering rules

Portable rules that apply to every project, not just hearth. Installed by
`scripts/install-global-rules.sh` into Claude (`~/.claude/CLAUDE.md`), Cursor
(`~/.cursor/rules/hearth-global-rules.mdc`), Cline, OpenCode, and Zed. Edit
here, then re-run the script. Do not edit between markers or the dedicated
`hearth-*` files. Cursor Settings → User Rules are left alone.

Each rule here earned its place by causing a real bug.

## macOS ships bash 3.2

`/bin/bash` on macOS is 3.2.57 (2007). Code requiring bash 4 passes review,
passes on any Linux CI, and dies on the Mac. Avoid:

- `declare -A` / `local -A` — no associative arrays. Use parallel arrays, a TSV
  temp file, or hand aggregation to python.
- `mapfile` / `readarray`
- `${var^^}` / `${var,,}` — use `tr`
- Bare `"${arr[@]}"` on a possibly-empty array under `set -u` — throws
  "unbound variable". Guard it: `${arr[@]+"${arr[@]}"}`
- `pgrep -q` — BSD and GNU disagree. Use `pgrep -f x >/dev/null 2>&1`.
- `$(... | grep -c . || echo 0)` — `grep -c` prints `0` **and** exits 1 on no
  match, so the fallback appends a second value and every numeric test after it
  fails. Use `wc -l | tr -d ' '`.

If a script genuinely needs bash 4+, shebang `#!/usr/bin/env bash` **and** check
`((BASH_VERSINFO[0] >= 4))` at the top with a clear error.

Also: LF line endings only for `.sh`, `.plist` and config files. CRLF produces
"bad interpreter: ...^M" and silent launchd failures.

## Python embedded in shell scripts

- **`curl ... | python3 - args <<'PY'` is broken.** The heredoc and the pipe
  both claim stdin, so python reads its *program* from the heredoc and
  `sys.stdin` is already exhausted. Write the data to a temp file and pass the
  path in `sys.argv`.
- **Escaped quotes inside an f-string expression** raise "f-string expression
  part cannot include a backslash" on 3.11+. Use a heredoc so quoting isn't
  fighting the shell, or build the string outside the f-string.
- **macOS system python3 has no PyYAML** and cannot `pip install` without
  `--break-system-packages`. Detect a usable interpreter; don't assume one.

## Diagrams are Mermaid

No ASCII art, no committed SVG or PNG. GitHub renders Mermaid natively, it diffs
as text, and it cannot drift out of sync with the prose the way an exported
image does. If something genuinely cannot be expressed in Mermaid, use a
Markdown table.

## Checks and failure modes

- **A check that could not run must never look like a check that failed.**
  Distinct exit codes: `0` pass, `1` real problem, `2` could not run. A missing
  dependency reported as a security finding gets the whole suite ignored.
- **Verify against the environment that will actually run the code.** A variable
  exported in your interactive shell is not set for launchd, systemd, or a
  container. Check the service's environment, not yours.
- **Where config is both env vars and a settings UI, the stored value usually
  wins.** Env vars typically seed a *fresh* database and are ignored thereafter,
  so a persisted volume keeps whatever was written on first run. Reading the
  environment tells you what was *intended*, not what is *in effect* — check the
  running config, or start from a clean state.
- **A positive control is half of any negative test.** "The restricted key was
  refused" proves nothing on its own — a broken key refuses everything. It must
  also *succeed* at what it is allowed to do.
- **An API that accepts your request and does nothing** is worse than one that
  errors. After any destructive or mutating call, re-read the state and confirm.

## Config and secrets

- A config value whose env var is missing may take down the **entire** config,
  not just that entry. Keep unusable entries commented out.
- Placeholder values (`sk-...`, `CHANGEME`) are more dangerous than empty ones:
  an empty var gives a clear "not found", a placeholder gives a 401 against a
  healthy service. Detect and drop them.
- Never let a template invite secrets into the wrong file. If two env files
  exist, say plainly which process reads which.

## Working style

- Plan → refine → approve → build. Don't start building because a plan looks
  obviously right.
- Treat your own knowledge of fast-moving tooling as stale. Before asserting a
  price, a version, a limit, or that something exists — check, and date it.
- When a check finds nothing, prove it can find something. A scanner that never
  fires is indistinguishable from a broken one.
