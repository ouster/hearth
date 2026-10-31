# Tool smoke — 2026-09-06-1229

Stage-1 MLX vs Ollama agent bench (`bench/tool-smoke.py`). Zed-like
read → tool result → write with `<` in file content.

Host: M4 Max, 64 GB. MLX via Rapid-MLX `:8000`; Ollama native `:11434`.

## Summary

| Backend | Model | Pass | Wall (s) | Turn 1 tools | Turn 2 tools | `<` preserved |
|---|---|---|---|---|---|---|
| Rapid-MLX | `qwen3.6-35b-4bit` | **yes** | **2.6** | `read_file` ×2 | `write_file` | yes |
| Ollama | `gpt-oss:20b` | **yes** | 18.2 | `list_directory` | `write_file` | yes |
| Ollama | `qwen3-coder:30b` | **yes** | 12.0 | `read_file` (+166 B text) | `write_file` (+272 B text) | yes |

## Notes

- **MLX Qwen3.6 is ~7× faster** than `gpt-oss:20b` on this harness (2.6 s vs 18.2 s).
- All three **pass** the minimal tool loop — but `qwen3-coder:30b` still
  fails in full Zed agent sessions (Ollama XML tool-parse errors on longer
  multi-tool chains). This smoke is a gate, not a full agent replay.
- `gpt-oss:20b` was the prior `local-big` on Ollama; replaced by MLX (ADR 0012).
- MLX + one Ollama role can both be resident — watch the ~48 GB envelope.

## Raw outputs

```
bench/results/2026-09-06-1229-tool-smoke/
  mlx_qwen3.6-35b-4bit.out
  ollama_gpt-oss_20b.out
  ollama_qwen3-coder_30b.out
```

## Decision

**Promoted:** `qwen3.6-35b-4bit` on Rapid-MLX → `local-big` (ADR 0012).

| Outcome | Action |
|---|---|
| MLX Qwen3.6 passes + faster | **done** — gateway routes `local-big` to `:8000` |
| Zed manual confirms | ongoing — use `hearth` / `local-big` agent default |
| Other MLX candidates | bench before any further role swap |

Nothing becomes a role until `scripts/swap-role.sh` + `docs/MODELS.md` + ADR.
