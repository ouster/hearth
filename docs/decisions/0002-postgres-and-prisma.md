# ADR 0002 — Postgres + Prisma for virtual keys

Date: 2026-08-02
Status: accepted

## Context

The privacy boundary is meant to be structural: the `private` key must be unable
to reach a cloud model, rather than merely discouraged from doing so. In LiteLLM
that means virtual keys, and virtual keys require a database.

The database requirement brings Prisma with it — an ORM, migration tool and code
generator, using a Rust query engine under a Python client. It is by a wide margin
the heaviest dependency in this stack, and it broke the first deploy: adding
`database_url` to the config introduced a dependency the working install never had,
and LiteLLM failed at startup with `ModuleNotFoundError: No module named 'prisma'`.

That prompted the obvious question — can this be simpler?

## Options considered

**A. Postgres + Prisma (chosen).** Four virtual keys, each scoped to a model list,
each with its own spend cap, individually revocable.

**B. Two LiteLLM instances, no database.** Port 4000 with the full config, port 4001
with a local-only config. Privacy becomes a property of which config a port loaded —
arguably easier to audit than a database row, since "the 4001 config contains no
cloud models" is a one-line check.

**C. SQLite instead of Postgres.** Rejected outright: Prisma is the ORM regardless
of backend, so this removes nothing. It also races on budget decrements under
concurrent requests, and budget enforcement is half the point.

## Decision

Option A.

Option B is genuinely simpler and was close. It removes Postgres, Podman, Prisma
and migrations, and it would deliver the same structural privacy guarantee.

It was rejected because without a database there is exactly one key per instance —
the master key. `private` versus `general` survives as a port split, but `lan` and
`lan-cloud` collapse into it. That means no spend cap on the laptop and no way to revoke
one client without rotating every client on that port. Laptop access with a small,
containable blast radius was a stated requirement, so the coarser model is a real
downgrade rather than a cosmetic one.

## Consequences

- Prisma must be installed and its client generated in LiteLLM's venv.
  `scripts/setup-prisma.sh` does both; `scripts/preflight.sh` verifies it whenever
  the config has `database_url` or `store_model_in_db` set, so this failure cannot
  recur silently.
- The Podman VM must be running before the gateway starts. After a reboot,
  `scripts/db.sh up` handles it, but a gateway that boots first will come up with
  no database and virtual keys will fail until it is run.
- Startup is slower — LiteLLM runs migrations against the schema on first boot.
- `store_model_in_db` becomes available, letting the future auto-updater promote a
  model via the admin API rather than editing yaml and restarting. This was **not**
  a reason for the decision; approval-gated promotion works fine as a yaml edit.

## Escape hatch

If Prisma becomes a maintenance burden, Option B remains viable and is the
documented fallback. Switching means: split `config.yaml` into a full and a
local-only variant, add a second launchd agent on 4001, set a distinct master key
per instance, drop `database_url` and `store_model_in_db`, and accept per-port
rather than per-client keys. `scripts/audit-fallbacks.sh` would then run against
both configs.
