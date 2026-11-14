# ADR 0049 — sub-key swap over the tunnel

**Date:** 2026-11-14
**Status:** accepted 2026-11-14 by the operator.
**Amends:** ADR 0048 (laptop swap path). ADR 0047 exclusivity stands. ADR 0045
(tunnel still forwards loopback only; add `:1236`).

## Context

ADR 0048 lets a laptop load a host swap role with `hearth-load` over
`HEARTH_SSH_ADMIN` (an ordinary SSH login). The tunnel key is forward-only.
A laptop sub-key can call `/v1` and cannot log in as oMLX admin.

The operator wants swap over the tunnel, with the same convenience as
calling oMLX on `:1234` / `:1235`, without putting the host token on the
laptop.

## Decision

- Run **`hearth-swapd`** on the host at `127.0.0.1:1236`.
- Auth: `Authorization: Bearer` must get HTTP 200 from oMLX `GET /v1/models`.
  A laptop sub-key is enough. The host token never leaves the host.
- Allow only `coding-brain` or `deep-brain`, and only `up` or `down`.
- Run `scripts/demand-load.sh` with the host token (slots, exclusivity,
  prior agent).
- Expose `GET /v1/hearth/agent` so the client can see which agent is loaded.
- Tunnel: second forward to host `:1236`. Plain laptop uses local `:1236`.
  Dual uses local `:1237` so this machine can keep its own swapd on `:1236`.
  Host `authorized_keys` adds `permitopen="127.0.0.1:1236"`.
- `hearth-load` prefers the swapd HTTP path. `HEARTH_SSH_ADMIN` is fallback
  when swapd is down.

## Consequences

- A stolen sub-key can swap the host agent (unload `main-brain`). It still
  cannot use oMLX `/admin`. Every key oMLX accepts can do this, an editor
  sub-key included, not only a laptop key (`docs/THREAT-MODEL.md` §5).
- A tunnel installed before this ADR still serves oMLX. Only `hearth-load`
  needs the second forward, and says so when it is missing.
- `scripts/demand-load.sh <role> down` does nothing when that role is not
  loaded and another one is, so one session's exit cannot end another's.
- The host token is not in the daemon's environment. It reads
  `~/.config/hearth/env` when the agent check needs the admin API.
- swapd is optional: a failed start is a warning in `boot.sh`,
  `install-autostart.sh --check`, preflight and `healthcheck.sh`.
- Old tunnel keys and LaunchAgents need `scripts/client-setup.sh
  --update-keys` and `ai-tunnel-stop && ai-tunnel-install`.
- Boot and autostart keep swapd up with oMLX (`com.hearth.swap`).
