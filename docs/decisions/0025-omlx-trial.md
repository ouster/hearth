# ADR 0025 — Try oMLX on the resident role

**Date:** 2026-11-04
**Status:** trial. Not a replacement for LM Studio until a bench says so.

## Context

Repeat prefill is the slow part of an agent turn. A single ~30K prompt on
the resident role has a time-to-first-token p95 of 25 seconds (measured
2026-11-01). oMLX keeps prefix KV in RAM and spills cold blocks to SSD, and
restores a matching prefix on a later request. The LM Studio token does not
move to another server. oMLX can use that same bearer value, so host clients
do not need a new key for the trial. Laptop tokens are separate. The host
stores only a hash of each one, so they are not copied. `sub-key add`
registers a token the operator pastes. That key can call the model and
cannot log in as admin.

The default oMLX memory ceiling is system RAM minus 8 GB, about 56 GB on
this machine, past the ~48 GB GPU cap.

## Decision

Run the trial with `scripts/omlx-try.sh`. It serves the resident role on
`127.0.0.1:1234` from the weights already on disk, requires the host token,
caps context at the role's window, sets the memory guard to 48 GB, and caps
the SSD cache at 20 GB. CORS is off. oMLX's own MCP is off. LM Studio is
stopped first so both servers are not resident. `down` loads the role in
LM Studio again. Login boot still starts LM Studio.

## Consequences

- Measured 2026-11-04, same 30,260-token prompt twice: first turn 23.4 s to
  the first token, second turn 3.0 s. The log restored 30,257 cached tokens.
  A prompt that changes at the front does not hit; the concurrency bench
  does that, and both of its turns took about 25 s. Footprint after the
  run was 24 GB. The SSD cache had grown to 12 GB.
- SSD cache files are the prompts. The directory stays on this machine.
- The trim notifier watches an LM Studio log line, so it is quiet during
  the trial.
- Nothing here changes `config/roles.tsv`. A passing bench is not yet a
  decision to boot oMLX.
