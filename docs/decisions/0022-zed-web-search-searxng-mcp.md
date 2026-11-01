# ADR 0022 — Web search for the Zed agent through the local SearXNG

**Date:** 2026-11-01
**Status:** accepted 2026-11-01 by the operator.

## Context

SearXNG only served Open WebUI's search button; the Zed agent had no web
search except Zed's own hosted tools. About a dozen SearXNG MCP servers exist.
Vetted against `docs/MCP.md`'s rules (stdio, declared egress, exposed tools
limited, a profile named for the egress), the clear choice was
`ihor-sokoliuk/mcp-searxng` 2.9.0: active, MIT, in the MCP Registry, npm
package with SLSA provenance and no install scripts, stdio by default, and a
URL reader that refuses loopback and private addresses. Risks: one
maintainer, frequent releases, and no server-side tool allow-list.

## Decision

- Install it pinned (`npm install --ignore-scripts --save-exact`) into
  `~/.local/share/hearth/mcp-searxng`; never run it with `npx`.
- Register it in host Zed as a stdio context server pointed at
  `127.0.0.1:8888`, with tools enabled only in a new `web` profile: just
  `searxng_web_search`, plus read-only file tools. `web_url_read`,
  suggestions and instance info stay off.
- Monitor its lockfile with Snyk (`scripts/snyk-monitor.sh`).

## Consequences

- Query text from the `web` profile reaches public search engines (via
  SearXNG, so not tied to the host's IP or a profile). Never for client work.
- Upgrades are deliberate: re-vet, bump the pinned version, re-run
  `scripts/snyk-monitor.sh mcp-searxng`.
- It depends on Homebrew's Node (`/opt/homebrew/bin/node`, ≥ 22), installed as
  a dependency of the Snyk CLI. Removing that breaks the server.
- Tested 2026-11-01 over stdio: search returned results via the local
  SearXNG; `web_url_read` refused `127.0.0.1:1234` and `localhost:8888`; no
  listening port.
