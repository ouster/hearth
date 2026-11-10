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
| `searxng` | stdio | this machine's SearXNG `127.0.0.1:8888` → public search engines | 1 of 4, via `scripts/searxng-mcp.mjs` | Zed `web` and `write-web`; Cline, OpenCode, Goose (ADR 0022, 0029, 0045) |

## Worked example: auslaw (not installed)

`auslaw` shows how to add a networked MCP without making it ambient. It
provides Australian and NZ case-law and legislation tools through AustLII.
It was live during migration phase 3, but neither its source nor its Zed
configuration is currently on this host. The historical source location was
`~/dev/auslaw-mcp`; this repo does not contain or install it.

**stdio, not HTTP.** Its HTTP mode calls `listen(port)` with no host, so it
binds every interface with no authentication, and defaults to `:3000`.
stdio spawns a child process with no listener at all.

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

The worked Zed profile below exposes only the seven AustLII tools.
`JADE_SESSION_COOKIE` is deliberately absent from the child process's
environment, so the credential to use the three jade.io tools is not present.

Why exclude them: jade.io access is a reverse-engineered GWT-RPC endpoint
driven by a session cookie lifted from a browser. That is a credential in a
config file and a fragile contract with a commercial provider. AustLII is free,
public, and has neither problem. `search_cases` stays because its jade half
returns an empty array without the cookie while its AustLII half still works.

### Zed setup

Prerequisite: obtain the source from its owner, review it again, install its
locked dependencies, build it, and confirm that an absolute
`.../auslaw-mcp/dist/index.js` exists. Do not copy the historical path: it
belonged to another home directory and no longer exists here.

1. Open **Settings → AI → MCP Servers → Add Server → Add Local Server**.
2. Enter:
   - Server Name: `auslaw`
   - Command: the absolute path to the reviewed Node executable
   - Arguments: the absolute path to `auslaw-mcp/dist/index.js`
   - Environment: `MCP_TRANSPORT=stdio`
   - Timeout: `60`
3. Do **not** add `JADE_SESSION_COOKIE`. Save, then require a green
   **Server is active** indicator. A wrong command or argument exits
   immediately and otherwise looks like an empty tool list.
4. Open `zed: open settings file`. The server entry should have this shape,
   with real absolute paths:

```json
{
  "context_servers": {
    "auslaw": {
      "command": "/absolute/path/to/node",
      "args": ["/absolute/path/to/auslaw-mcp/dist/index.js"],
      "env": {
        "MCP_TRANSPORT": "stdio"
      }
    }
  }
}
```

5. Add a profile under `agent.profiles` which has no built-in tools and
   exposes only the seven AustLII tools:

```json
{
  "agent": {
    "profiles": {
      "research": {
        "name": "Research",
        "tools": {},
        "enable_all_context_servers": false,
        "context_servers": {
          "auslaw": {
            "tools": {
              "search_cases": true,
              "search_legislation": true,
              "search_by_citation": true,
              "fetch_document_text": true,
              "generate_pinpoint": true,
              "validate_citation": true,
              "format_citation": true
            }
          }
        }
      }
    },
    "tool_permissions": {
      "default": "confirm"
    }
  }
}
```

6. Ensure the ordinary Write and Ask profiles set
   `enable_all_context_servers` to `false`; profile overrides replace rather
   than merge with Zed's built-ins. Reload Zed, select **Research**, and check
   that exactly those seven tools appear. Write and Ask must show none.

Switching to Research is the deliberate act of saying that the query may go
to AustLII. Keep the profile on `hearth/main-brain`; host Zed has no cloud
provider. The query can carry personal information the agent has just read.
Send it only when that is intended.

## searxng

Web search through this machine's own SearXNG (ADR 0022, 0045). The tunnel does not forward it, and the URL is never a public instance.
Package `mcp-searxng` 2.9.0 (`ihor-sokoliuk/mcp-searxng`, MIT, npm with SLSA
provenance, no install scripts), installed pinned with `npm install
--ignore-scripts --save-exact` into `~/.local/share/hearth/mcp-searxng`, run by
`/opt/homebrew/bin/node` (needs Node ≥ 22). Never `npx`: that would fetch
whatever is newest on every start. Its lockfile is monitored by Snyk
(`scripts/snyk-monitor.sh`, project `hearth/mcp-searxng`).

**stdio.** Clients run `scripts/searxng-mcp.mjs` with `/opt/homebrew/bin/node`,
not the package entry and not `npx`. The wrapper forces
`SEARXNG_URL=http://127.0.0.1:8888`, `SEARXNG_LITE_TOOLS=true` (short schemas
for a local model) and `SEARXNG_MAX_RESULTS=10`, and it drops `MCP_HTTP_PORT`.
A `SEARXNG_URL` in the client config is ignored.

### Tools, by where they go

| Tool | Reaches | Exposed |
|---|---|---|
| `searxng_web_search` | local SearXNG → Google, Bing and others: **the query text leaves** | yes |
| `searxng_search_suggestions` | local SearXNG → engines' autocomplete | **no** |
| `searxng_instance_info` | local SearXNG `/config` only | **no** (not needed) |
| `web_url_read` | **any public URL** | **no** |

The package has no allow-list. `scripts/searxng-mcp.mjs` is the allow-list:
it advertises `searxng_web_search` and refuses the other three. Zed profiles
still enable only that tool. `web_url_read` refuses localhost, RFC1918,
link-local and private IPv6, including names that resolve to them — checked
2026-11-01 against `127.0.0.1:1234` and `localhost:8888`, both refused. Kept
off anyway: an agent that can fetch any page is both an exfiltration channel
and a prompt-injection feed.

### Who may reach it

The machine that runs SearXNG (ADR 0045). Zed uses two profiles (ADR 0022,
0029). **Web** has an empty built-in tool map and `default_model`
`hearth/main-brain`, so a search result cannot read a file. **Write + search**
(`write-web`) has Write's tools and no pinned model, so a coding thread on
`main-brain` or `deep-brain` can search. The query text still leaves, and
that profile can put file contents into the query. `confirm` on each tool
call is the other gate. Write and Ask have neither. An agent on Write +
search can exfiltrate personal information by searching with text it read
from a file. See `docs/ROUTING.md`.

Cline, OpenCode, and Goose on that same machine start the wrapper
(`docs/IDES.md`). Cline cannot hide a tool in its MCP settings, which is why
the wrapper exists. OpenCode denies `webfetch` and sets `websearch` to false.
Goose lists `searxng_web_search` in `available_tools`. Each search asks first.
Do not point any of them at Gemini for a thread that can search.

SearXNG has no authentication. Any process on this machine can POST a query
to `127.0.0.1:8888`. A process on another machine cannot: the tunnel does not
forward the port, and new keys cannot `permitopen` it.

## Rules these enforce

**Off by default.** Zed's built-in Write profile enables every context server
(`enable_all_context_servers: true` in Zed 1.26); host settings redefine
Write with it `false`. SearXNG is on in `web` and `write-web` only.

**No cloud model alongside a networked tool.** Tool output re-enters the
prompt. Host Zed has no cloud provider (D3). Web stays on `hearth/main-brain`.
Write + search sets no model, so the thread stays on `main-brain` or
`deep-brain`. A laptop may have a Gemini provider for other work; neither
search profile is switched to it.

**Ask before each call.** `agent.tool_permissions.default` is `confirm`.

## Checks

There is no automated MCP scope audit since the gateway went (ADR 0016).
By hand, after any Zed upgrade or settings change:

| Check | Proves |
|---|---|
| Agent panel → Write profile shows no searxng tools | the default profile cannot search via SearXNG |
| Web profile shows `searxng_web_search` and not `web_url_read`, and no file tools | a search-only thread cannot read the repo, and the URL reader stays off |
| Write + search shows `searxng_web_search`, file and edit tools, and not `web_url_read` | a coding thread can search, and the URL reader stays off |
| Write and Ask show `fetch` and `search_web` off | the built-in web tools stay off |

If following the auslaw worked example, additionally check that Write and Ask
show no auslaw tools, Research shows exactly the seven listed tools, and
`grep -c JADE ~/.config/zed/settings.json` returns `0`.

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
