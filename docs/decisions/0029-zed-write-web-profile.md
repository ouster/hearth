# ADR 0029 — Zed profile for coding with search

**Date:** 2026-11-05
**Status:** accepted

## Context

ADR 0022 put `searxng_web_search` only on the Web profile, which has no file
tools, so a search result cannot read a file. Coding threads need search in
the same turn as read and edit. The default profile is Write, and that is
where ordinary work happens.

## Decision

- Add a Zed profile `write-web`, shown as **Write + search**.
- It has Write's built-in tools. `fetch` and `search_web` stay off.
- Its only SearXNG tool is `searxng_web_search`. `web_url_read`, suggestions
  and instance info stay off.
- It sets no `default_model`, so the thread stays on `local-main` or
  `local-deep`.
- Write and Ask stay without SearXNG. Web stays without file tools and
  stays on `local-main`.
- `agent.tool_permissions.default` stays `confirm`.
- This repo is general-purpose. The hazard is an agent exfiltrating personal
  information: it can read a file and place a name, address, or document
  text into the search query, and that query leaves.

## Consequences

- Switching to Write + search is the act of letting the query leave. The
  model can build that query from files it can read.
- The default Write profile still cannot search.
- A laptop must not point this profile at Gemini. Tool output re-enters the
  prompt.
