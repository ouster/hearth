# ADR 0048 — main-brain is the resident on every tier; coding-brain is a 64 GB swap role

**Date:** 2026-11-14
**Status:** accepted 2026-11-14 by the operator.
**Amends:** ADR 0047 (the default resident and the load of `coding-brain` and `main-brain` on 64 GB). ADR 0047's exclusivity rule stands. ADR 0040 (a dual machine can load the other host's swap roles).

## Context

ADR 0047 made `coding-brain` the 64 GB boot resident and `main-brain` a swap role there. A 48 GB host has no `coding-brain` row, so the default role name differed by machine: `coding-brain` on the 64 GB Mac, `main-brain` on the 48 GB laptop. Editors, the client script and the docs each had to know which machine they faced. The client script called `coding-brain` by name, and an unloaded name can be answered by whatever is loaded.

The operator's record after two days on it: `coding-brain` "proved too large for every client". It has one slot, a 98K window, and a ~52 GB peak under the 56 GB ceiling.

## Decision

- **`main-brain` is `resident` at `min_ram` 64 and 48.** Every editor, `ask`, and the client script default to `main-brain` on every machine.
- **`coding-brain` is `swap` at `min_ram` 64.** `scripts/demand-load.sh coding-brain up` (or the `coding-brain` command) unloads `main-brain` and `deep-brain`, loads it, and sets 1 slot. `down` restores `main-brain` and 3 slots. A 48 GB host has no row and refuses.
- **`deep-brain` is unchanged:** swap on both tiers. It restores the agent that was loaded before it.
- **`coding-brain` never shares RAM with `main-brain` or `deep-brain`** (ADR 0047, unchanged).
- **A laptop can ask the host to swap.** `hearth-load <role> up|down` runs `scripts/demand-load.sh` on the host over the operator's ordinary SSH login (`HEARTH_SSH_ADMIN`). The tunnel key stays forward-only and the laptop's token gains no admin right. `coding-brain-remote` and `deep-brain-remote` refuse unless the host reports that role loaded.
- No weights change. Both models were benched on 64 GB (ADR 0046, 0047), so rule 5 needs no new run.

## Consequences

- While `coding-brain` or `deep-brain` is swapped in on a host, a call to `main-brain` on that host has no model of its own. This includes a laptop on the tunnel. Swap back when the session ends.
- Boot and `healthcheck.sh` exercise `main-brain` on both tiers, including the thinking probe.
- `ask-main` stays as a name for `ask`. It no longer loads anything.
- The 48 GB tier's `262144 × 3` row is still unbenched on 48 GB hardware (`docs/MODELS.md`). This ADR does not change it.
