# 0008 — MCP tools go through the gateway, scoped by key, deny by default

Date: 2026-08-02
Status: accepted

## Context

LiteLLM 1.85.1 — already running here — includes an MCP gateway. It is an MCP
client to upstream servers and an MCP server to clients, over streamable HTTP,
SSE or stdio, with permissions by key, team and organisation. The endpoints
were live and unused before this change.

The question was whether to use it for `auslaw-mcp`, an Australian legal
research server in `~/dev/auslaw-mcp` that the threat model already flags as an
unaudited feed.

Two findings decided the shape of the answer.

**1. Tools are a second egress path, and the existing leak test cannot see it.**

`scripts/healthcheck.sh` proves a prompt cannot reach a cloud *model*. It says
nothing about tools, and tools leak in both directions:

- A tool can reach the network itself. Nine of auslaw-mcp's ten tools call
  AustLII or jade.io, so a search term leaves this machine whether or not a
  cloud model is involved.
- A tool RESULT re-enters the prompt. On a cloud role the definitions and
  everything they return go to the provider along with it.

Only `format_citation` touches nothing — it is pure AGLC4 string formatting.
There is no configuration in which a key gets useful legal research and nothing
leaves the host.

**2. LiteLLM's MCP defaults are fail-open, the inverse of its model defaults.**

- A key with an empty or absent `mcp_servers` list inherits its team's list.
- A team with an empty list means "no restriction", regardless of any flag.
- So registering one server under stock settings grants it to every key,
  including `private`.

That is incompatible with rule 3. The boundary has to hold because of how it is
configured, not because someone remembered.

## Decision

**MCP access is deny by default, and a tool that reaches the network may not
share a key with a cloud role.**

Four parts.

**Deny by default.** `require_key_mcp_access_defined: true` in
`general_settings` turns the team list into a ceiling rather than a default, so
a key reaches only what it was explicitly granted. LiteLLM documents this as
the recommended posture and intends to make it the default. Every key in
`create-keys.sh` now carries an explicit `object_permission.mcp_servers`.

**A new invariant, enforced by script.** `scripts/audit-mcp-scope.sh` fails if
any server marked as leaving the host is reachable by a key that can also reach
a cloud role. Egress is declared per server via `x-hearth-egress` in
`config.yaml`, because nothing in the MCP protocol tells a gateway whether a
tool phones home — only someone who read its source knows. Unmarked fails.
Wired into `preflight.sh`. `healthcheck.sh` gained an MCP section with a
master-key control, so "nobody sees any tools" cannot pass as scoping when it
is really a broken gateway.

**auslaw-mcp registered over stdio, AustLII only.** Its HTTP mode calls
`listen(port)` with no host — binding every interface with no authentication —
and defaults to `:3000`, which is Open WebUI. stdio has no listener. The three
jade.io tools are excluded at the server level via `allowed_tools`, so they are
not exposed to any key, and `JADE_SESSION_COOKIE` is deliberately absent from
the server's environment: permission says no, and the credential to do it
anyway is not there. `search_cases` is included because its jade half returns
an empty array without the cookie and its AustLII half still works.

**A new `research` key rather than widening `private`.** It holds local models
and `auslaw`, and no cloud role. `private` gets nothing. Switching to
`research` is the deliberate act of saying "this query is going to AustLII",
rather than that being an ambient property of the everyday key.

## Consequences

**A key needs a team to hold an MCP grant.** A key outside a team may only be
assigned servers flagged `allow_all_keys`, and that flag is not a scoping
mechanism — the server manager unions those servers into every key's allowed
set. `create-keys.sh` therefore creates a `research` team whose sole purpose is
to carry the grant. First team in this stack.

**Enforcement is at execution, not just discovery.** Verified: the private key
calling `auslaw-format_citation` directly gets `access_denied`, not a filtered
list it can bypass.

**Deny is an empty list, not the documented sentinel.** 1.85.1 validates every
entry against registered servers before interpreting sentinels, so
`no-mcp-servers` is rejected outright with none registered. An empty list plus
the flag plus no team is equivalent here. Revisit if these keys ever join a
team, because only the sentinel overrides team inheritance.

**Access groups are avoided.** BerriAI/litellm#27657, open as of 2026-08-02:
assigning a group to a team never creates the underlying permission row, so
discovery and enforcement both fall through. Direct per-key lists avoid that
path.

**One machine-specific path is now in the tracked config.** LiteLLM's
`os.environ/` resolver recurses into dicts but leaves plain strings inside a
list alone, and `args` is `List[str]` — so the entry path cannot be templated.
A wrong path is silent: the process exits, the log says "Connection closed",
and the tool list is empty, which looks identical to correct scoping. Preflight
checks the path exists. `command` is env-resolved via `HEARTH_MCP_NODE` because
the nvm path carries a node version that changes on upgrade.

**Tools now depend on Postgres.** MCP auth reads the same database as virtual
keys, so a database outage takes tools down the same way it takes keys down.

**This does not address prompt injection.** Scoping makes auslaw-mcp auditable
and revocable. It does not make its output trustworthy: AustLII content still
enters the model's context, and ADR 0007's containment is what limits what an
agent can do with it. Two different controls; both needed.

**Still unaudited.** Registering auslaw-mcp behind the gateway does not
discharge the threat model's finding. It narrows the blast radius to one key
and seven tools.
