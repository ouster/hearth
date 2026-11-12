# Routing rules

The decision table. When in doubt, local.

## What must stay local

Route to `*-brain` roles (oMLX, `:1234`), always:

- Any repo or path you have flagged as holding sensitive or private data
- Names, addresses, contact details, financial figures, ID documents
- Anything covered by applicable privacy obligations
- Credentials, keys, `.env` contents, database dumps
- Anything you would not paste into a public forum

## What can go to cloud

- Open-source repos and public code
- Synthetic or anonymised examples
- Language, framework, and API questions with no data attached
- Architecture and design discussion in the abstract
- This repo itself
- VS Code Copilot inline completions and next edit suggestions, in any repo
  not flagged sensitive (ADR 0041). Copilot also reads other open tabs, so a
  sensitive file opened in a window without the repo opt-out goes too: open
  sensitive work in its own repo's window.

## Roles

| Role | Use for | Reached by | State |
|---|---|---|---|
| `coding-brain` | default local agent / code on 64 GB (98K × 1) | oMLX `:1234` (resident) | live (ADR 0047) |
| `main-brain` | concurrent / long-context local work (256K × 3) | oMLX `:1234` after `demand-load.sh main-brain up` on 64 GB; resident on 48 GB | live |
| `deep-brain` | hard one-off local questions | oMLX `:1234` after `ask-deep` / demand-load | live, on demand |
| `cloud-cheap` | bulk non-sensitive work, big context | a laptop's `ask-cloud` → Gemini directly, with that laptop's own key | live, client-only (ADR 0038) |
| `local-embed` | — | — | removed 2026-11-01, nothing called it (ADR 0018) |
| `local-code`, `local-chat` | — | alias names only; mean `main-brain` (D1) | collapsed |
| `cloud-code`, `cloud-frontier`, `cloud-frontier-direct`, `cloud-frontier-fast` | — | — | dormant, no keys |

## Enforcement

There is no gateway and no key scope (ADR 0016). The boundary is structural
in a different way:

| Path | Can it leave the host? | Why |
|---|---|---|
| Anything to `127.0.0.1:1234` | **no** | oMLX holds only local models |
| Zed on this host | **no** model egress | no cloud language-model provider (D3). Edit prediction stays `"none"` or laptop `edit-brain`; paid Zed Zeta (`"provider": "zed"`) is cloud and trips `zed-sync --check` (ADR 0033). Tool egress: SearXNG in the `web` and `write-web` profiles. Write and Ask have `fetch` and `search_web` off |
| `ask`, `ask-*` on the host | **no** | point at `:1234` with the host token. There is no host `ask-cloud`: the host holds no cloud key (ADR 0038) |
| `ask-cloud` on a laptop | **yes** | the only command with a provider key, the laptop's own; it is explicit by name |
| Sandboxed agents | **no** | egress allowed to `127.0.0.1:1234` only |
| SearXNG, from Zed Web or Write + search | query: **yes** | the model stays on `:1234`. The query leaves from this machine's ISP address, with no browser cookie and no signed-in search account. See below |
| VS Code, Cline, OpenCode, Goose | chat/agent model: **no** if set up per `docs/IDES.md`. Completions: **yes, to GitHub** (VS Code) | Custom Endpoint / OpenAI Compatible at `:1234` only. Copilot inline completions (ghost text) and next edit suggestions are **allowed** and send the text around the cursor to GitHub (ADR 0041) — except in a repo flagged sensitive, which turns both off in its own `.vscode/settings.json` (`scripts/vscode-check.sh --show-sensitive`, checked by `--workspace DIR`). Copilot code search stays off. Cline's `web_search` / `web_fetch` and OpenCode's `websearch` stay off. Keyword search is this machine's SearXNG (ADR 0045) |

What is lost against the gateway: on a laptop, nothing refuses a cloud
request you make on purpose. Choosing `ask-cloud` on sensitive work is not
stopped — it is only made explicit. On the host it cannot happen at all:
there is no cloud key to use (ADR 0038).

**Never add a cloud model to oMLX**, and never give a remote backend an
`omlx` row in `config/roles.tsv`. That single rule is what makes `:1234`
safe for anything.

## Web search punctures the boundary

Zed, Cline, OpenCode, and Goose search through SearXNG on this machine
(`scripts/searxng.sh`, `scripts/searxng-mcp.mjs`, ADR 0022, 0029, 0045). The
model, the conversation and the files stay here. **The search query does not.**

SearXNG runs here and opens its own connections to Google, Bing and
DuckDuckGo, so those engines see this machine's ISP address. They do not
see a browser cookie or a signed-in account, and the query is not added to
one. That is the gain over a signed-in browser, over Cline's web search
(which posts the query to Cline), over OpenCode's `websearch` (Exa, Parallel,
Firecrawl, Tavily, or TinyFish) and over Zed's built-in `search_web`
(which posts it to Zed, then Exa). It is not anonymity. The search terms
still leave, from this house. A public SearXNG instance would hide the ISP
address and hand the query to whoever runs it, so the wrapper refuses any
URL except `http://127.0.0.1:8888`. The tunnel does not forward SearXNG
either: a laptop searches from the laptop. Open WebUI, the old chat page,
was removed (ADR 0044).

| Safe with web search on | Never with web search on |
|---|---|
| "How does framework X handle refresh tokens?" | "Search for <person name> <address>" |
| "What changed in the 2026 API spec?" | Anything quoting a name, address, or account figure |
| Framework and API questions | Anything you would not type into Google |

Web search is opt-in per conversation. Leave it off by default. An agent that
can read files can place personal information from those files into the next
query, and that query leaves. A thread that already holds names, addresses,
or documents should not have search on.

Zed follows the same rule on two profiles (ADR 0022, 0029). **Web** sends
`searxng_web_search` to public engines, has no file tools, and stays on
`main-brain`. **Write + search** has Write's tools and no pinned model, so
a thread on `main-brain` or `deep-brain` can search and can read files into
the query. Each tool call asks first (`confirm`). Write and Ask do not
include SearXNG, or Zed's built-in `fetch` and `search_web`. Cline, OpenCode,
and Goose ask before the same tool and have their own web search off
(`docs/IDES.md`). `docs/MCP.md` uses the former legal-research profile as a
setup example; it is not installed.

## No fallbacks

There is no router, so nothing can quietly reroute a request to a cloud
model. If `main-brain` is not loaded, a request for it can be answered by
whatever model is loaded, under the name you asked for. That is a wrong
local answer, not a leak. `ask-deep` and the
laptop clients refuse to call `deep-brain` unless it is actually loaded, for
this reason. The earlier rule ("local roles never fall back to cloud")
existed because the inherited gateway had `local → gemini` fallbacks; see
`docs/HISTORY.md`.

## Break-glass

There is no second local server (ADR 0028).
If oMLX is wedged: `scripts/omlx.sh down`, then `scripts/omlx.sh up`.
Before changing anything, capture `~/Library/Logs/hearth-omlx.log`, the
footprint of the listener, and the concurrency bench at the failing settings.
