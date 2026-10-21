# MLX stage-1 bench (Ollama vs Rapid-MLX)

Compare **agent tool loops** — not raw tok/s. Zed needs read → tool result →
write with messy file content. Code bench (`scripts/bench.sh`) does not catch
the Qwen XML failure mode.

**Date drafted:** 2026-09-06. **2026-10-22:** `local-big` moved back to Ollama's
MLX runner after the same tool-smoke passed there (ADR 0013). This file is for
a side experiment. It is not how the role is served.

## Envelope (this Mac)

| Constraint | Value |
|---|---|
| Unified RAM | 64 GB |
| GPU-accessible | ~48 GB |
| Hot models | 1 Ollama model (ADR 0011). A Rapid-MLX process beside it spends the GPU budget |

| MLX alias (Rapid-MLX) | Weights (approx) | Role |
|---|---|---|
| `qwen3.6-35b-4bit` | ~20 GB | bench only — role is the Ollama tag in `docs/MODELS.md` |
| `gpt-oss-20b` | ~13 GB | bench / break-glass |
| `gemma-4-12b-4bit` | ~8 GB | candidate — not promoted |

## Install Rapid-MLX

```bash
scripts/mlx-bench.sh --install-rapid
scripts/mlx-bench.sh --serve qwen3.6-35b-4bit   # foreground, :8000, not launchd
```

Stop it when the experiment is done so it does not sit beside Ollama.

**Gemma 4** MLX weights need the vision stack:

```bash
pipx inject rapid-mlx 'mlx-vlm==0.6.17'
```

## Tool smoke (automated)

Latest results: `bench/results/2026-09-06-1229-tool-smoke/`

```bash
scripts/tool-smoke.sh openai http://127.0.0.1:8000/v1 qwen3.6-35b-4bit
scripts/tool-smoke.sh ollama gpt-oss:20b
scripts/tool-smoke.sh ollama qwen3-coder:30b
```

Pass = **turn 2 emits `write_file` or `edit_file`** with `<` in content.

## Zed

Use the **`hearth`** provider — agent default `local-big`, which is Ollama
(ADR 0013).

For raw MLX A/B (bypass gateway):

```json
"mlx": {
  "api_url": "http://127.0.0.1:8000/v1",
  "available_models": [
    { "name": "qwen3.6-35b-4bit", "display_name": "qwen3.6-35b-4bit (MLX direct)", "max_tokens": 65536 }
  ]
}
```

## Decision rules

| Outcome | Action |
|---|---|
| Candidate fails tool smoke | Do not promote |
| Passes + Zed manual OK | ADR + `docs/MODELS.md` + config. Qwen3.6 is already `local-big` via Ollama (ADR 0013) |

Nothing else becomes a role until `scripts/swap-role.sh` + ADR.
