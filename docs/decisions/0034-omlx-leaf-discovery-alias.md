# ADR 0034 — oMLX discovery leaf + role model_alias

**Date:** 2026-11-07
**Status:** accepted 2026-11-07 by the operator.

## Context

Hearth linked weights as `~/.omlx/models/<role>` (e.g. `local-main`). oMLX’s
discovery id is that directory name, so community benchmark uploads on
omlx.ai published `local-main` — meaningless to anyone else. Zed’s picker
label was also just the role.

Clients must keep calling roles (rule 1). Concrete weights paths stay in
`config/roles.tsv` and `docs/MODELS.md` only.

## Decision

- Symlink into oMLX as the org/leaf path from `roles.tsv` column 6
  (`~/.omlx/models/lmstudio-community/Qwen3.6-35B-A3B-MLX-4bit` →
  `~/.hearth/models/...`). Discovery id = the leaf; display/repo =
  `org/leaf`.
- Set oMLX `model_alias` to the role (`local-main`, `local-deep`). `/v1`
  advertises the alias; chat resolves it. Admin load/unload/bench use the
  leaf id.
- Remove flat role symlinks on `up` so they are not discovered beside the
  leaf.
- Zed `display_name` is `role — <leaf>` via `scripts/zed-sync.sh`.

## Consequences

- New community benches show the real model leaf (and org when derived).
- Old uploaded rows that say `local-main` stay historical.
- `scripts/demand-load.sh` and `configure_model` map role → leaf for admin
  APIs. Attach/`up` calls `/admin/api/reload` so new links are discovered
  without a full process takeover when possible.
