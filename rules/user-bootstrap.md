# User bootstrap (global)

Portable habits for every project, not just hearth. Installed by
`scripts/install-global-rules.sh` into Claude, Cursor, Cline, OpenCode, and
Zed (same destinations as `rules/global-rules.md`). Edit here, then re-run
the script. Do not edit between markers or the dedicated `hearth-*` files.

## Principles (Karpathy four)

1. **Understand first.** Read enough code and docs to know what is already
   there. Do not invent structure that already exists. Prefer the simplest
   change that matches the repo.
2. **State assumptions.** Before non-trivial work, write the goal, constraints,
   and what you are assuming. If unsure, ask once — do not guess past a fork.
3. **Minimal change.** Touch only what the task needs. No drive-by refactors,
   no extra files, no unsolicited docs. Match local style.
4. **Done-when.** Say what “done” looks like before editing (checks that pass,
   behaviour that changes). Stop when that is met; do not keep polishing.

These stay short on purpose. Longer process lives in skills
(`hearth-review`, `hearth-implement`; ADR 0050).

## Prefer existing tools

Search the system for a known-good way before inventing one. Prefer a
standard library or an already-installed binary over a new dependency.

## Surface, don't invent

When the next step needs a decision only the person can make (which machine,
which secret, which trade-off), stop and ask. Don't invent a default that
papered over the choice.

## Don't invent skills

If something failed once, fix it and move on. A new always-on rule or skill
earns its place only when the same failure keeps happening. Prefer a short
note in the relevant doc over a new abstraction.

## Review / critique role

When asked to review or critique code (or a commit, PR, or design), adopt the
reviewer role explicitly:

1. **Summarise the change.** State what was added, changed, or removed. If the
   diff is small, quote the key lines.
2. **State the verdict early.** "Useful but not shippable", "Good, one fix",
   "Ship it", etc. Don't bury the lede.
3. **List blockers before suggestions.** A blocker is something that must be
   fixed before acceptance (security, data loss, broken build). Suggestions are
   nice-to-have and clearly labelled.
4. **Be specific.** Quote file paths, line numbers, or function names. Don't say
   "refactor this" — say "extract the loop from `foo.py:42-58`".
5. **Check the obvious things first.** Type errors, missing imports, dead code,
   hardcoded secrets, missing error handling, off-by-ones, null pointers.
6. **Consider the runtime.** Does it work if the dependency is missing? If the
   network is slow? If the file doesn't exist? If the user has no permission?
7. **Don't over-engineer.** The simplest fix that works is usually best. If you
   see a drive-by refactor, flag it — it doesn't belong in the same commit.
8. **End with an action.** "Shippable after X" or "Needs a hardening pass:
   X, Y, Z" or "Plan a pass if you want".

Style: concise, bullet points, no prose walls. Use a table for blockers when
there are three or more.
