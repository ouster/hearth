# ADR 0039 — Roles are brains: main-brain, deep-brain, edit-brain

**Date:** 2026-11-08
**Status:** accepted by the operator 2026-11-08.
**Supersedes:** the role names of ADR 0021 (`local-main`) and ADR 0033 (`local-edit`).

## Context

The `local-*` prefix meant "on hardware you own, never a cloud model". Once
one machine can be both a host and a client of a bigger host, "local" reads
as "this machine". That is a property of the endpoint, not the role. ADR
0037 already calls a person's model on their own hardware a *brain*.

## Decision

- `local-main` → **`main-brain`**, `local-deep` → **`deep-brain`**,
  `local-edit` → **`edit-brain`**. `cloud-*` names are unchanged.
- Rule 3 reads "sensitive data goes to `*-brain` only". A brain is a model
  on hardware the person owns, reached on loopback or through their own
  tunnel (ADR 0037).
- Preflight: an oMLX row must be `*-brain`, and a `*-brain` row cannot sit
  on a cloud backend. Preflight also fails if `local-main`, `local-deep`
  or `local-edit` appears in a live file. History (ADRs, HISTORY.md, bench
  results, research notes, the LM Studio migration record) keeps the old
  names.
- New shell commands **`main-brain`** and **`deep-brain`**, on the host and
  on laptops (bash, zsh, PowerShell). They sit alongside `ask`, `ask-arch`
  and `ask-deep`, which keep working.
- Which machine answers is named by the endpoint, not the role: for
  example `hearth` for this machine and `hearth-<host>` for a remote host
  through the tunnel.

## Consequences

- **Host:** after pulling, run `scripts/omlx.sh up`, which re-advertises
  the new names (`model_alias`) and unpins leftover `local-*` discovery ids
  so `/v1/models` does not keep listing them. Then run `scripts/zed-sync.sh`
  and `scripts/pin-digests.sh` (the role column of `pins/digests.tsv` was
  renamed in place; the hashes are unchanged).
- **Clients:** change the model id to `main-brain` in Zed (`name` in the
  `hearth` provider), VS Code (`chatLanguageModels.json`, and
  `chat.planAgent.defaultModel`), Cline (the provider's model) and
  JetBrains. Copy `client/hearth-client.sh` over `~/.hearth-client.sh`
  again. On a laptop with `edit-brain`, run `client/edit-model.sh
  laptop-up` again so its oMLX serves the new name.
- During the switch, oMLX answers an unknown model name with whatever is
  loaded (`docs/ARCHITECTURE.md`). So a client still sending
  `local-main`, or one sending `main-brain` before the host has run `up`,
  keeps working without saying so. Healthcheck warns about this. Update
  each client so the name it sends is the one that serves it.
