# ADR 0038 — cloud-cheap is client-only; the host holds no cloud key

**Date:** 2026-11-08
**Status:** accepted by the operator 2026-11-08.

## Context

`cloud-cheap` (Gemini) was reachable from two places. One was the host's
`ask-cloud` in `scripts/aliases.zsh`, using `GOOGLE_API_KEY` from
`~/.config/hearth/env`. The other was each laptop's `ask-cloud` in
`client/hearth-client.sh`, using that laptop's own key. Cloud work is
always started from a client. The host's key only meant that something
running on the host could reach a cloud model: an agent, a script, or a
mistaken `ask-cloud` in a sensitive repo.

## Decision

- **The host holds no cloud key.** The host `ask-cloud` is removed from
  `scripts/aliases.zsh`, along with the duplicate `ask-*` names left over
  from before D1 (`ask-fast`, `-local`, `-chat`, `-big`, `-architect`). The
  laptop client drops the same duplicates. What remains: `ask`, `ask-arch`,
  `ask-deep`, and on laptops `ask-cloud`. `ai_load_env` no longer reads `GOOGLE_API_KEY`.
  `preflight.sh` fails if `~/.config/hearth/env` still has a
  `GOOGLE_API_KEY` or `GEMINI_API_KEY` line. It checks the name only and
  never reads the value.
- **The `cloud-cheap` row stays in `config/roles.tsv`, labelled
  client-only.** It is still the one place the Gemini id is written (rule
  1). `scripts/client-setup.sh` reads it to print each laptop's
  `HEARTH_CLOUD_MODEL`, and laptops read it from their own clone.
- Rule 3 is now simpler on the host. Nothing started there can reach a
  cloud model, whether by mistake or on purpose.

## Consequences

- **Operator, on the host:** delete the `GOOGLE_API_KEY=` line from
  `~/.config/hearth/env` by hand. Revoke the key at Google if nothing else
  uses it. Until then, preflight fails.
- Cloud work needs a laptop with its own `~/.hearth-gemini-key`
  (`docs/LAPTOP.md`).
- On a laptop, `ask-cloud` on sensitive work is still not stopped, only
  explicit (`docs/ROUTING.md`).
- The dormant cloud rows and the `gemini` backend check in preflight are
  unchanged.
