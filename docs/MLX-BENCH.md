# MLX stage-1 bench (Ollama vs Rapid-MLX)

Compare **agent tool loops** — not raw tok/s. Zed needs read → tool result →
write with messy file content. Code bench (`scripts/bench.sh`) does not catch
the Qwen XML failure mode.

**Date drafted:** 2026-09-06. **Promoted 2026-09-06:** `qwen3.6-35b-4bit` on
Rapid-MLX is now `local-big` (ADR 0012).

## Envelope (this Mac)

| Constraint | Value |
|---|---|
| Unified RAM | 64 GB |
| GPU-accessible | ~48 GB |
| Hot models | 1 Ollama + 1 MLX typical for agent work |

| MLX alias (Rapid-MLX) | Weights (approx) | Role |
|---|---|---|
| `qwen3.6-35b-4bit` | ~20 GB | **`local-big`** (live) |
| `gpt-oss-20b` | ~13 GB | bench / break-glass |
| `gemma-4-12b-4bit` | ~8 GB | candidate — not promoted |

## Install Rapid-MLX

```bash
scripts/mlx-bench.sh --install-rapid
scripts/install-rapid-mlx-service.sh --apply   # launchd, :8000
```

Add `RAPID_MLX_API_KEY=mlx` to `~/.config/litellm/env` and restart LiteLLM.

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

Use the **`hearth`** provider — agent default `local-big`. No separate `mlx`
provider needed; the gateway routes `local-big` to Rapid-MLX.

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
| Passes + Zed manual OK | ADR + `docs/MODELS.md` + config (done for Qwen3.6 — ADR 0012) |

Nothing else becomes a role until `scripts/swap-role.sh` + ADR.
