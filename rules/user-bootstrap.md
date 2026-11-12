# User agent bootstrap

Portable habits for every project. Installed by
`scripts/install-global-rules.sh` into Claude, Cursor (`~/.cursor/rules/`),
Cline, OpenCode, and Zed. Edit here, then re-run the script. Do not edit
installed copies between markers or the dedicated `hearth-*.md` / `.mdc`
files.

Project hard rules stay in that repo's `AGENTS.md` / `CLAUDE.md`. Do not
restate them here.

## Always

- State assumptions. Ask when the answer changes the design. Push back on
  overbuild.
- Write the minimum that solves the ask. No speculative features or
  abstractions.
- Change only what the task needs. Leave unrelated code and comments alone.
- Define done. Check it before you claim done.
- Same correction twice → fix in code or lint first; else a skill; else one
  rule line. Do not pile soft rules.

## Plans

- Extremely concise. Sacrifice grammar.
- End with unresolved questions (if any).
- Plan → I approve → execute → verify → commit (only if I ask).

## Repos

- If the repo has `AGENTS.md` or `CLAUDE.md`, read it and follow it. Do not
  restate it here.
- Do not invent skills until a failure repeats.
