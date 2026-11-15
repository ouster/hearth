# ADR 0051 — model display proxy on `:1238`

**Date:** 2026-11-15
**Status:** proposed. The operator approved the design points below on
2026-11-15; acceptance waits on the Cline picker check (see *Open*).
**Amends:** rule 1 (a third generated copy of model names). Uses ADR 0048
resident slots. Serving and routing are unchanged.

## Context

oMLX's `/v1/models` lists roles with no hint of what is behind them. Zed gets
labels from `scripts/zed-sync.sh`, which writes `display_name` into Zed's
settings. Cline and other OpenAI-compatible clients read the list from the
server and have nowhere to put a label.

A first proxy (commits `15f9e8e`, `ef7ce5a`, `5f315fb`) was reviewed on
2026-11-15 and failed on these points, each reproduced:

- It injected the host token for any caller without a key. A keyless chat
  completion through it returned 200; `:1234` returned 401.
- It buffered streams (a whole SSE reply arrived in one read) and served one
  request at a time, which turned `main-brain`'s three slots into one.
- It never reached `hearth_resolved_roles` and fell back to the last
  `roles.tsv` row per role, ignoring the RAM tier.
- Its installer wrote a root LaunchDaemon that ran a script from a
  user-writable checkout.

## Decision

- `scripts/model-proxy.py` listens on `127.0.0.1:1238` and forwards to this
  machine's oMLX on `127.0.0.1:1234`. Loopback only, standard library only.
- `GET /v1/models` gains `display_name` per role, with the rules and wording
  of `zed-sync.sh`: `role — leaf — ctx × slots`, plus the load hint on
  demand roles. Edit and embedding roles get none. Any answer that is not a
  200 JSON list passes through unchanged, status included.
- Every other request passes through and streams as bytes arrive. The server
  is threaded, so the resident's slots stay usable (ADR 0048, 0050).
- **It holds no key.** The client's `Authorization` header is forwarded as
  sent. It never reads `~/.config/hearth/env`. A keyless request gets oMLX's
  401. Preflight fails if a keyless `/v1/models` through the proxy returns 200.
- **Local oMLX only.** There is no remote mode. On a dual machine
  `hearth-remote` stays on the tunnel (`:1235`): labels come from this
  machine's `roles.tsv` and RAM tier and would be wrong for another host.
- Rows come from `hearth_resolved_roles`. If that cannot run the proxy exits
  2; there is no fallback. Labels are rebuilt when `roles.tsv` changes.
- It runs as the user agent `com.hearth.model-proxy`, installed by
  `scripts/install-autostart.sh --apply`. Never as root.
- Rule 1 now lists three generated copies: Zed's labels, `pins/digests.tsv`,
  and this proxy's runtime labels. All are built from `roles.tsv`.

## Consequences

- Optional. An editor can always use `:1234` directly and lose only the
  label. An editor pointed at `:1238` has no models while the proxy is down,
  so preflight fails when the plist exists and nothing listens.
- The label shows what `roles.tsv` says, not what is loaded (rule 6: drift is
  detected, not enforced).
- A sandboxed agent still reaches `:1234` only (ADR 0016); the proxy is not
  in the sandbox profile.
- The client side is HTTP/1.0: one request per connection, and a stream ends
  when the connection closes.

## Proof (2026-11-15, on spare port 1248, this machine's own tier)

| Check | Result |
|---|---|
| Keyless `/v1/models` and chat through the proxy | 401, same as `:1234` |
| Keyed `/v1/models` (positive control) | 200, `main-brain` labelled `… — 256K × 3` |
| Streamed completion | 17 reads over 1.9 s |
| `/v1/models` while a stream is open | 200 in 3 ms |
| oMLX port unreachable | 502 with a JSON error |
| Roles unresolvable | exit 2 |

## Open

- Whether Cline's model picker shows `display_name`, which is not part of the
  OpenAI schema. If it does not, remove the proxy rather than keep it.
