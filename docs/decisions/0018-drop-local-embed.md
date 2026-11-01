# ADR 0018 — Drop local-embed

**Date:** 2026-11-01
**Status:** accepted 2026-11-01 by the operator.

## Context

`local-embed` was the f16 GGUF of the Ollama-era embedding model, kept resident
beside `local-big` (ADR 0016). Nothing in the clients, Zed, or MCP calls it.
`scripts/healthcheck.sh` was the only request, and it only checked that
`/embeddings` returned a vector. There is no local corpus.

## Decision

Remove the role from `config/roles.tsv` and unload it. The weight file stays
on disk. Do not load a different embedding model in its place.

## Consequences

- One local model remains: `local-big`.
- A future RAG index is a new role, benched before it is loaded.
- The 20.7 GB idle figure from 2026-10-31 included this model (0.3 GB of weights).
