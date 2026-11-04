# ADR 0026 — oMLX serves the resident role

**Date:** 2026-11-04
**Status:** accepted

## Context

ADR 0025 ran oMLX as a trial on `:1234` while login boot still started LM
Studio, and the weights stayed a symlink into `~/.lmstudio/models`. A repeat
of the same ~30k prompt reached a first token in 26.1 s, then 4.6 s, restoring
30,241 cached tokens (`bench/results/2026-11-04-2150-omlx-cache`). Cold
prefill matches the LM Studio measurement of 2026-11-01. Decode stays in the
same band, about 50–110 tok/s. `bench/tasks` has not been re-run on oMLX.

## Decision

Login boot runs `scripts/omlx-try.sh up`. The resident weights are a copy
under `~/.hearth/models`, and that copy is what oMLX loads. The LM Studio
copy stays on disk. `scripts/omlx-try.sh down` stops oMLX and loads the role
in LM Studio again. The host token keeps its name. `local-deep` moved onto
oMLX in ADR 0027.

## Consequences

- A reboot no longer replaces oMLX with LM Studio.
- Uninstalling LM Studio no longer deletes the weights oMLX serves. It
  removes the rollback.
- The trim notifier still watches an LM Studio log line, so it stays quiet.
- Zed's display names still come from `lms ls` when that sync is run.
