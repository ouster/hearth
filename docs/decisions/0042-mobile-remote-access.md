# ADR 0042 — Mobile remote access over a mesh overlay

**Date:** 2026-11-09
**Status:** accepted 2026-11-09 by the operator (design; no proxy or app yet).

## Context

Laptops reach the host through an SSH tunnel to loopback oMLX and a
per-machine bearer token (`docs/LAPTOP.md`, ADR 0037). Phones need the same
privacy bar: changing home ISP addresses, CGNAT, and no public bind of
`:1234`. Cline has no native iOS/Android client (verified 2026-11-09); their
phone recipe is Tailscale plus browser Kanban. Building a full coding agent
into a Hearth mobile app is a large product, while chat with `main-brain`
is a thin OpenAI-compatible client once the path exists.

## Decision

- **Discovery:** Tailscale (or later Headscale / self-hosted NetBird) on
  host and phone. MagicDNS names the host. No port-forward, no DDNS as the
  primary path.
- **Serving:** oMLX stays on `127.0.0.1:1234`. Reach it through a proxy
  bound only to the Tailscale interface, or through an SSH local-forward
  on the phone. Do not enable Serve on Local Network.
- **API auth:** per-phone oMLX sub-key (`phone-<name>`), same revoke model
  as laptops. Token in the platform keystore.
- **MVP product:** chat with `main-brain`. Agent control from a phone uses
  Cline Kanban over the same overlay, bound to the Tailscale IP (or
  localhost + forward), not `0.0.0.0` on every interface. **T3 Code is
  deferred** (FAQ rejects local models, 2026-11-09); OpenCode is the desk
  harness trial (ADR 0043), not the phone plan.
- **Reject for the brain:** Facebook / consumer SSO as the gate to `:1234`,
  and a public Cloudflare Access hostname as the MVP front door. Tailscale
  IdP (Apple/Google) is network membership only. Passkeys may unlock the
  app later; they do not replace the bearer token.

Detail and non-goals: `docs/MOBILE.md`.

## Consequences

- A third-party coordinator (Tailscale) sees which devices are on the
  tailnet, not prompt bodies, while oMLX stays private.
- Near-term work is a host-side proxy (or documented SSH forward) and
  pairing docs; a custom Hearth app is optional.
- Laptop tunnels and editor setup are unchanged.
