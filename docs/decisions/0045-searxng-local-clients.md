# ADR 0045 — SearXNG stays on this machine

**Date:** 2026-11-10
**Status:** accepted 2026-11-10 by the operator. Amends ADR 0022 (laptops no longer use the host's SearXNG) and ADR 0040 (the tunnel no longer forwards it). Supersedes the ADR 0044 note that Cline has no keyword search.

## Context

Zed's Web and Write + search profiles already search through the pinned SearXNG MCP, with only `searxng_web_search` on and each call confirmed. Cline, OpenCode, and Goose can speak MCP. Their own web search does not: Cline's `web_search` and `web_fetch` post to Cline, and OpenCode's `websearch` posts to Exa, Parallel, Firecrawl, Tavily, or TinyFish.

The tunnel used to forward the host's SearXNG (`:8888`, or `:8889` on a dual machine). A search from a laptop then left from the host's ISP address, and any process on the laptop could send a query once the tunnel was up. A public SearXNG instance would hide that address and give the query to its operator.

`mcp-searxng` 2.9.0 registers four tools and has no allow-list. Cline's MCP settings cannot hide one tool, so a raw entry would expose `web_url_read`.

## Decision

- SearXNG runs on the machine that searches, on `127.0.0.1:8888`. The tunnel forwards oMLX only. New keys, and keys refreshed with `scripts/client-setup.sh --update-keys`, drop `permitopen` for `127.0.0.1:8888`. An old `HEARTH_SEARXNG_PORT` is ignored.
- Clients start `scripts/searxng-mcp.mjs`, not the package entry. The wrapper forces `SEARXNG_URL` to `http://127.0.0.1:8888` and advertises `searxng_web_search` only. A URL in the client config cannot point the query somewhere else.
- Cline's web search is off (`tools.web_search.enabled` false; browser and MCP are not auto-approved). OpenCode's `websearch` is false and `webfetch` is denied. Goose has no vendor web search; its extension allow-list is `searxng_web_search`. Each search asks first.
- Zed's profiles stay as they are (ADR 0022, 0029) and use the same wrapper, so a profile that enabled every tool would still not see `web_url_read`.

## Consequences

- A machine that wants search runs `scripts/searxng.sh up` itself. A laptop with no local SearXNG has no web search. The host's engines see the host's ISP address; a laptop's engines see the laptop's.
- On each host: `scripts/client-setup.sh --update-keys`, so old tunnel keys lose `:8888`.
- On each laptop: install the new client, then `ai-tunnel-stop && ai-tunnel-install` (macOS) or `ai-tunnel` (Linux). Until then an old agent still forwards SearXNG.
- The query text still leaves, from the machine that searched. Engines do not see a browser cookie or a signed-in account.
