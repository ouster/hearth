# ADR 0051: Model Display Proxy

**Status:** Draft  
**Date:** 2026-11-15  
**Author:** hearth  

## Context

oMLX's `/v1/models` endpoint returns minimal metadata:

```json
{"id": "main-brain", "object": "model", "owned_by": "omlx", "max_model_len": 262144}
```

IDEs like Zed and Cline need more context to help users understand which underlying model is loaded. Zed works around this with `zed-sync.sh` which writes hand-crafted `display_name` fields to the editor settings. Cline has no such mechanism.

## Decision

Add a reverse proxy on port 1238 that:

1. **Enriches `/v1/models`** with `display_name` matching `zed-sync.sh` format:
   - `role — leaf — ctx × slots` (e.g., `main-brain — qwen3.6-35b-a3b-mlx — 256K × 3`)
   - Adds load instructions for swap/edit models

2. **Forwards all other endpoints** transparently to oMLX on port 1234, preserving SSE streaming via chunked transfer encoding

3. **Reads roles via `hearth_resolved_roles`** from `scripts/lib.sh` so labels always match the model actually loaded on this host

4. **Supports two modes:**
   - `--local`: Forward to local oMLX (`:1234`)
   - `--remote`: Forward to SSH tunnel (`--tunnel-port`, default `:1235`)

## Implementation

- `scripts/model-proxy.py`: Python proxy (stdlib only)
- `scripts/companion-proxy.sh`: Launchd plist for daemon mode
- `docs/IDES.md`: Add Cline setup instructions pointing to `:1238`

## Consequences

### Positive

- IDE model pickers now show meaningful labels instead of opaque role names
- Cline, aider, and other OpenAI-compatible clients benefit automatically
- Zed's `display_name` labels match the proxy output (same source of truth)

### Negative

- Additional hop (`:1234` → `:1238`) adds ~1ms latency (negligible for one-time model fetch, streaming passes through unchanged)
- Users must remember to point `hearth-remote` at the SSH tunnel port (`:1235`), not `:1238`

### Unresolved

- **Auth injection risk**: Local mode reads `OMLX_HOST_TOKEN` from `~/.config/hearth/env` and may inject it if the client omits `Authorization`. Host daemon is acceptable; laptop clients should provide their own keys.

## Alternatives Considered

1. **Patch oMLX** to expose display metadata — requires oMLX change
2. **Zed-only sync** — doesn't help Cline/aider
3. **No enrichment** — users see opaque role names with no indication of underlying model

## Migration Plan

1. ✅ Fix crash (cloud rows with `ctx="-"`)  
2. ✅ Fix label format (`ctx × slots`)  
3. ✅ Fix streaming (chunked encoding)  
4. ✅ Fix dual URL (`hearth-remote` → `:1235`, `hearth` → `:1238`)  
5. ⏳ ADR + plist in repo  
6. ⏳ Add Cline docs  
7. ⏳ Auth policy decision