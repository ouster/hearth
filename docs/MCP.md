# MCP registry

Server → tools → which clients may reach them. This file and the client config
docs (`docs/IDES.md`) are the only places a concrete MCP server may be named.
Update both together, plus an ADR. Since ADR 0016 servers live in the client
(Zed `context_servers`), not the gateway (ADR 0008, superseded).

MCP tools are a **second egress path**. Keeping cloud models off `:1234`
stops a prompt reaching a cloud *model*; it says nothing about a tool that
calls the internet on its own account. That is why every server below declares
where it goes, and why a networked server is enabled only in a profile named
for that egress.

## Registered

| Server | Transport | Egress | Tools | Clients |
|---|---|---|---|---|
| `auslaw` | stdio | `austlii.edu.au` | 7 of 10 | host Zed, `research` profile only (ADR 0016). Gateway `research` key until phase 5 |
| `searxng` | stdio | local SearXNG `127.0.0.1:8888` → public search engines | 1 of 4 | host Zed, `web` profile only (ADR 0022) |

## auslaw

Australian and NZ case law and legislation. Source: `~/dev/auslaw-mcp`.

**stdio, not HTTP.** Its HTTP mode calls `listen(port)` with no host, so it
binds every interface with no authentication, and defaults to `:3000` — which
is Open WebUI. stdio spawns a child process with no listener at all.

### Tools, by where they go

| Tool | Reaches | Exposed |
|---|---|---|
| `format_citation` | nothing — pure AGLC4 string formatting | yes |
| `search_legislation` | AustLII | yes |
| `search_by_citation` | AustLII | yes |
| `fetch_document_text` | AustLII | yes |
| `generate_pinpoint` | AustLII | yes |
| `validate_citation` | AustLII | yes |
| `search_cases` | AustLII (+ jade.io, disabled) | yes |
| `resolve_jade_article` | jade.io | **no** |
| `jade_citation_lookup` | jade.io | **no** |
| `search_citing_cases` | jade.io | **no** |

The jade.io tools are excluded at the **server** level via `allowed_tools`, so
they are not exposed to any key regardless of its grant, and
`JADE_SESSION_COOKIE` is deliberately absent from the server's environment.
Permission says no, and the credential to do it anyway is not present.

Why exclude them: jade.io access is a reverse-engineered GWT-RPC endpoint
driven by a session cookie lifted from a browser. That is a credential in a
config file and a fragile contract with a commercial provider. AustLII is free,
public, and has neither problem. `search_cases` stays because its jade half
returns an empty array without the cookie while its AustLII half still works.

### Who may reach it

**After ADR 0016 (host Zed, 2026-10-31):** a `context_servers` stdio entry in
`~/.config/zed/settings.json`, tools enabled only in the `research` agent
profile. The built-in Write profile's `enable_all_context_servers` is
overridden to `false`, and each tool call asks first. There is no cloud
provider in host Zed (D3), so tool output only ever re-enters a local model.
See `docs/IDES.md`.

**Gateway era (until phase 5):** `research` only — local models plus these
tools, and no cloud role.

`private` deliberately gets nothing. Its promise is that nothing leaves this
machine, and every useful auslaw tool sends a query to AustLII. Switching to
`research` is the act of saying "this query is going to AustLII" rather than
that being an ambient property of the everyday key.

## searxng

Web search for the Zed agent through the host's own SearXNG (ADR 0022).
Package `mcp-searxng` 2.9.0 (`ihor-sokoliuk/mcp-searxng`, MIT, npm with SLSA
provenance, no install scripts), installed pinned with `npm install
--ignore-scripts --save-exact` into `~/.local/share/hearth/mcp-searxng`, run by
`/opt/homebrew/bin/node` (needs Node ≥ 22). Never `npx`: that would fetch
whatever is newest on every start. Its lockfile is monitored by Snyk
(`scripts/snyk-monitor.sh`, project `hearth/mcp-searxng`).

**stdio.** It only listens if `MCP_HTTP_PORT` is set, which Zed's entry does
not. Env: `SEARXNG_URL=http://127.0.0.1:8888`, `SEARXNG_LITE_TOOLS=true`
(short schemas for a local model), `SEARXNG_MAX_RESULTS=10`.

### Tools, by where they go

| Tool | Reaches | Exposed |
|---|---|---|
| `searxng_web_search` | local SearXNG → Google, Bing and others: **the query text leaves** | yes |
| `searxng_search_suggestions` | local SearXNG → engines' autocomplete | **no** |
| `searxng_instance_info` | local SearXNG `/config` only | **no** (not needed) |
| `web_url_read` | **any public URL** | **no** |

Unlike auslaw, the server has no allow-list: the exclusions are Zed profile
settings, not server-side. `web_url_read` refuses localhost, RFC1918,
link-local and private IPv6, including names that resolve to them — checked
2026-11-01 against `127.0.0.1:1234` and `localhost:8888`, both refused. Kept
off anyway: an agent that can fetch any page is both an exfiltration channel
and a prompt-injection feed.

### Who may reach it

Host Zed, `web` profile only. That profile has read-only file tools (no edit,
no terminal), so text from search results has nothing to act with. Not for
client work: rule 3, and `docs/ROUTING.md` (web search punctures the boundary).

## Rules these enforce

**Off by default.** Zed's built-in Write profile enables every context server
(`enable_all_context_servers: true` in Zed 1.26); host settings redefine
Write with it `false`. A server's tools are switched on only in a profile
named for its egress (`research` for auslaw).

**No cloud model alongside a networked tool.** Tool output re-enters the
prompt. Host Zed has no cloud provider (D3), so tool output only ever reaches
a local model.

**Ask before each call.** `agent.tool_permissions.default` is `confirm`.

## Checks

There is no automated MCP scope audit since the gateway went (ADR 0016).
By hand, after any Zed upgrade or settings change:

| Check | Proves |
|---|---|
| Agent panel → Write profile shows no auslaw tools | the default profile cannot reach AustLII |
| Research profile shows exactly the 7 allowed tools | the jade.io tools stay off |
| `grep -c JADE ~/.config/zed/settings.json` is 0 | the cookie is not configured |

## Adding a server

1. Read its source and establish what it talks to. That is the whole job; the
   rest is typing.
2. Add it to Zed `context_servers` (stdio preferred — no listener).
3. Enable its tools only in a profile named for its egress; never in Write.
4. Add a row to this file, a note in `docs/IDES.md`, and an ADR.

### Traps

**A wrong path is silent.** A stdio server whose command or script path is
wrong exits immediately and shows no tools — identical in the UI to a
correctly scoped profile. After adding one, confirm its tools appear in the
profile that should have them.

**Zed profile overrides replace, they do not merge.** Overriding a built-in
profile needs `name` and the full tool list, or the whole settings file fails
to load (`missing field name`).
