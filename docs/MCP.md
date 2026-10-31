# MCP registry

Server → tools → who may reach them. This file and `litellm/config.yaml` are
the only places a concrete MCP server may be named. Update both together, plus
an ADR — see `docs/decisions/0008`.

MCP tools are a **second egress path**. `scripts/healthcheck.sh` proves a
prompt cannot reach a cloud *model*; it says nothing about a tool that calls
the internet on its own account, and nothing about tool output re-entering the
prompt on a cloud role. That is why every server below declares where it goes.

## Registered

| Server | Transport | Egress | Tools | Clients |
|---|---|---|---|---|
| `auslaw` | stdio | `austlii.edu.au` | 7 of 10 | host Zed, `research` profile only (ADR 0016). Gateway `research` key until phase 5 |

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

## Rules these enforce

**Deny by default.** `require_key_mcp_access_defined: true` in
`general_settings`. Without it, a key with an empty list inherits its team's,
and a team with an empty list means "no restriction" — so registering one
server would grant it to every key including `private`.

**No key holds both a cloud role and a network-reaching tool.** Tool output
re-enters the prompt; on a cloud role it goes to the provider. Enforced by
`scripts/audit-mcp-scope.sh`, which reads the `x-hearth-egress` marker on each
server. **A server with no marker fails the audit** — an unread server is
exactly the one most likely to phone home.

## Checks

| Command | Proves |
|---|---|
| `scripts/audit-mcp-scope.sh` | no key holds a cloud role and a networked tool |
| `scripts/healthcheck.sh` | private sees zero tools, against a master-key control |
| `scripts/preflight.sh` | deny-by-default is on, stdio entry paths exist |

## Adding a server

1. Read its source and establish what it talks to. That is the whole job; the
   rest is typing.
2. Add it to `mcp_servers` in `config.yaml` with `x-hearth-egress` and an
   `allowed_tools` list. Name it to comply with SEP-986 — since v1.80.18
   LiteLLM namespaces tools by server name and rejects non-compliant new names.
3. Add a `MCP_*` variable and grant it in `scripts/create-keys.sh`. A grant
   needs a **team**: a key outside one may only be assigned servers flagged
   `allow_all_keys`, and that flag unions the server into *every* key.
4. Add a row to this file, and an ADR.
5. Verify with the three checks above.

### Traps

**stdio entry paths cannot be templated.** LiteLLM's `os.environ/` resolver
recurses into dicts but leaves plain strings inside a list alone, and `args` is
`List[str]`. An `os.environ/` entry there is passed to the interpreter
verbatim.

**A wrong path is silent.** The process exits immediately, the log says
`Connection closed`, and the tool list is empty — identical from the API to
correct scoping. Preflight checks the paths for this reason.

**stdio commands are allowlisted by basename:** `npx`, `uvx`, `python`,
`python3`, `node`, `docker`, `deno`. An absolute path works because LiteLLM
takes the basename; a shell script does not.

**Tools depend on Postgres.** MCP auth reads the same database as virtual keys.
A database outage takes tools down the same way it takes keys down.
