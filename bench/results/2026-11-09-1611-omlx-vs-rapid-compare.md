# oMLX vs Rapid-MLX — same OptiQ `main-brain` weights

**Date:** 2026-11-09  
**Weights:** `~/.hearth/models/mlx-community/Qwen3.6-35B-A3B-OptiQ-4bit`  
**Rapid:** 1.0.2 in `~/.hearth/venvs/rapid-mlx`, `127.0.0.1:8000`, no API key  
**oMLX:** restored on `:1234` after the Rapid half  

Rapid auto-config: `tool_call_parser=qwen3_coder_xml`, `reasoning_parser=qwen3`,
prefix cache on, KV dtype bf16, `supports_spec_decode=False` for this BYOM path.
Memory warning at load (est. 34 GB working set on 64 GB). Peak footprint during
Rapid c3: **30.0 GB**. oMLX footprint matcher returned 0.0 GB this run (matcher
miss) — use prior OptiQ c3 peaks (~34 GB) for memory context.

## Results

| Metric | oMLX `:1234` | Rapid `:8000` |
|---|---|---|
| Tool-smoke | PASS (~10.8 s wall) | PASS (~3.2 s wall) |
| c3 valid tools | 30 / 30 | 30 / 30 |
| c3 TTFT p50 / p95 | 59.8 s / 60.1 s | **45.3 s / 64.8 s** |
| c3 total p50 / p95 | 60.5 s / 61.0 s | **54.1 s / 65.1 s** |
| c3 wall | 608 s | 650 s |
| Cache probe cold TTFT | 19.050 s (prompt 29136) | 20.401 s (prompt 29138) |
| Cache probe warm TTFT | **0.312 s** | **0.269 s** |

Raw: `2026-11-09-1611-concurrency-c3-omlx-vs-rapid-omlx/`,
`2026-11-09-1623-concurrency-c3-omlx-vs-rapid-rapid/`.

## Read

- Both clear the tool gate on the same weights.
- Rapid’s **median** c3 TTFT is lower (~45 s vs ~60 s); p95 is a bit worse
  (~65 s vs ~60 s) — more spread under concurrency.
- Prefix cache on a repeated ~29k prompt is excellent on both (~0.3 s warm).
- Experiment only. No `roles.tsv` change (rule 5). Serving stays oMLX until a
  deliberate ADR and re-bench of the full Hearth path (sub-keys, aliases, boot).
