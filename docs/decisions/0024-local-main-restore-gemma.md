# ADR 0024 — local-main returns to the 26B-A4B

**Date:** 2026-11-01
**Status:** accepted 2026-11-01 by the operator.
**Supersedes:** ADR 0023

## Context

ADR 0019 put the 26B-A4B on the resident role. ADR 0023 took it off the same
day because Zed agent turns kept looping after sampling matched that model's
generation config.

The server log for that thread shows the loop was the context window. At
10:04, still on the previous resident, the prompt was 146,214 tokens and
LM Studio dropped 84,783 from the middle. The loaded context is 131,072. The
same conversation was at 212 messages while the 26B-A4B was loaded, and at
219 after ADR 0023. The turn still returns a normal reply, so the agent
repeats work it can no longer see. `scripts/context-watch.sh` notifies when
that trim happens. It does not stop the turn.

The 26B-A4B remains the bench winner (ADR 0019): better on `bench/tasks` 03,
40/40 tool calls, c3 peak 25.2 GB against 29.7 GB. Prefill is about 15%
slower.

## Decision

`local-main` is the 26B-A4B again: 128K × 3, no draft. `scripts/swap-role.sh`
loaded it and tool-smoke passed. No new bench. This restores the model ADR
0019 chose, after the reason for leaving it turned out to be the thread.

## Consequences

- The other resident's weights stay on disk.
- Thinking and sampling are still per-model app settings, recorded in
  `docs/MODELS.md`. They do not follow the role. A settings reset loses them
  until healthcheck catches it.
- The resident peak is 25.2 GB again
  (`bench/results/2026-11-01-gemma-concurrency`). Still under the ~48 GB
  ceiling alone, and still not beside `local-deep`.
- Reload Zed and start a new thread. An open thread that already overflowed
  will trim again, and the notification will say so.
