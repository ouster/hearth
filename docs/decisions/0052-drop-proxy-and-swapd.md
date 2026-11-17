# ADR 0052 — drop the model proxy and hearth-swapd

**Date:** 2026-11-16
**Status:** accepted 2026-11-16 by the operator.
**Supersedes:** ADR 0049 (hearth-swapd). **Withdraws:** ADR 0051 (model
proxy, never accepted). **Amends:** ADR 0048 (laptop swap path) and rule 1
(two generated copies again).

## Context

A dual machine had five loopback ports: `:1234` its own oMLX, `:1235` the
tunnel to another host's oMLX, `:1236` its own swapd, `:1237` the tunnel to
the other host's swapd, and `:1238` the label proxy. With sub-keys, the host
token and `HEARTH_SSH_ADMIN` on top, the operator could no longer say which
port, key and model a given command used.

Two of those layers are optional and two days old. The proxy only adds a
label to `/v1/models`, and whether Cline shows it was never proven (ADR 0051,
*Open*). swapd lets any key oMLX accepts unload `main-brain` on the host
(ADR 0049, *Consequences*).

## Decision

- Remove `scripts/model-proxy.py` and its launchd agent
  `com.hearth.model-proxy`. Nothing listens on `:1238`. Editors use `:1234`
  (or `:1235` for another host) and show the role name.
- Remove `scripts/hearth-swapd.py`, `scripts/hearth-swapd.sh` and the agent
  `com.hearth.swap`. Nothing listens on `:1236`.
- The tunnel forwards oMLX only. Tunnel keys lose
  `permitopen="127.0.0.1:1236"`; a dual machine has no `:1237`.
- Remove `hearth-load` and `HEARTH_SSH_ADMIN`. The laptop's `coding-brain`
  and `ask-deep` no longer load anything: they ask whether the host has the
  role in, then call it. **A swap role
  is loaded on the host that owns it**, with `scripts/demand-load.sh` or the
  host's own `ask-deep` / `coding-brain`. A laptop may call a swap role
  through the tunnel while the host has it in, as before.
- `scripts/install-autostart.sh --apply` boots out and deletes the two stale
  plists. `--check` and preflight fail while either is still installed.
- Rule 1 lists two generated copies: Zed's labels and `pins/digests.tsv`.

## Consequences

- Ports: `:1234` and, on a laptop or dual machine, the tunnel. Daemons on a
  host: oMLX and SearXNG.
- A laptop can no longer change what the host has loaded. Someone at the
  host (or with their own SSH login to it) runs `demand-load.sh`.
- A sub-key can no longer evict `main-brain` (`docs/THREAT-MODEL.md` §5).
- Cline and other clients that read the model list from the server show role
  names with no model or context label. Zed keeps its labels
  (`scripts/zed-sync.sh`).
- Each host must run `scripts/install-autostart.sh --apply` and
  `scripts/client-setup.sh --update-keys`; each laptop
  `ai-tunnel-stop && ai-tunnel-install`. Until a host does, its old swapd
  keeps running with nothing forwarding to it.
- Roles, `demand-load.sh`, keys and dual mode (ADR 0040) are unchanged.
