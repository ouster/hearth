# ADR 0044 — Drop Open WebUI, keep SearXNG

**Date:** 2026-11-10
**Status:** accepted 2026-11-10 by the operator. Amends ADR 0040 (the tunnel no longer forwards WebUI). Amended the same day by ADR 0045: the tunnel no longer forwards SearXNG either.

## Context

Editors already talk to `main-brain`. Open WebUI was a second chat page: a Podman container on `:3000`, a tunnel forward (`:3001` when dual), and no login. SearXNG is the keyword search Zed uses without a Cline, Zed, or GitHub account.

Cline's `web_search` and `web_fetch` are disabled on an OpenAI-compatible provider. With the Cline provider they post the query to Cline. VS Code's Copilot code search goes to GitHub and stays off (ADR 0041). Neither replaces SearXNG.

A self-hosted SearXNG does not hide this machine's IP. It queries the engines from here, so they see this ISP address. They do not see a browser cookie or a signed-in account. The query text still leaves. A public instance would hide the ISP address and give the query to its operator.

## Decision

- Remove Open WebUI. `scripts/webui.sh` only stops or destroys a leftover container. `scripts/boot.sh` stops a leftover and does not start one.
- The tunnel forwards oMLX and SearXNG only. New keys, and keys refreshed with `scripts/client-setup.sh --update-keys`, drop `permitopen` for `127.0.0.1:3000`.
- Keep SearXNG for Zed's Web and Write + search profiles.
- Say what the engines actually see, in `scripts/searxng.sh` and `docs/ROUTING.md`.

## Consequences

- Chat is the editors. `scripts/webui.sh destroy` on the host deletes the old volume and the chats in it.
- On the host: `scripts/webui.sh down` (the next `scripts/boot.sh` stops it too), then `scripts/client-setup.sh --update-keys`.
- On each laptop: install the new client, then `ai-tunnel-stop && ai-tunnel-install`. Until then the old agent still forwards `:3000`.
- Cline and VS Code still have no keyword search. Pointing the SearXNG MCP at them is a later ADR: a networked tool stays off except in a profile named for the egress.
- Snyk no longer monitors the WebUI image. `hearth/searxng` and `hearth/mcp-searxng` stay.
