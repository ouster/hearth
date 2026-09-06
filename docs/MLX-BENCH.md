# MLX stage-1 bench (Ollama vs Rapid-MLX)

Compare **agent tool loops** — not raw tok/s. Zed needs read → tool result →
write with messy file content. Code bench (`scripts/bench.sh`) does not catch
the Qwen XML failure mode.

**Date drafted:** 2026-09-06. Model sizes from mlx-community / Rapid-MLX docs
that day — re-check before pull.

## Envelope (this Mac)

| Constraint | Value |
|---|---|
| Unified RAM | 64 GB |
| GPU-accessible | ~48 GB |
| Hot models | 1 (ADR 0011) |

| MLX alias (Rapid-MLX) | Weights (approx) | Fit? |
|---|---|---|
| `gpt-oss-20b` | ~13 GB | Yes — incumbent agent on Ollama |
| `qwen3.6-35b-4bit` | ~20 GB | Yes — **start here** for Qwen3.6 |
| `qwen3.6-35b-8bit` | ~38 GB | Tight — weights alone eat most of 48 GB; use 64K `num_ctx` max |
| `gemma-4-12b-4bit` | ~8 GB | Yes — fast, vision-capable |
| `gemma-4-26b-4bit` | ~16 GB | Yes |

`qwen3.6-35b-8bit` on HF: `mlx-community/Qwen3.6-35B-A3B-8bit` (~38 GB per
Unsloth card, Sep 2026). Prefer **4bit** unless 8bit tool smoke clearly wins.

**Ignore [mlxserver.com](https://mlxserver.com)** — 2024 library, custom `/generate`
API, not OpenAI-compatible. Use **`mlx_lm.server`** (Apple) or **Rapid-MLX**
(agent tool parsers + prompt cache).

## Install Rapid-MLX

```bash
scripts/mlx-bench.sh --install-rapid
# or: pipx install rapid-mlx
```

**Gemma 4 and Qwen3.6-35B** MLX weights need the vision stack:

```bash
pipx inject rapid-mlx 'mlx-vlm==0.6.17'
# or reinstall: pipx install 'rapid-mlx[vision]'
```

Text-only **`gpt-oss-20b`** does not need `[vision]`.

## Stage 1 — tool smoke (automated)

**Ollama baseline** (no MLX):

```bash
scripts/mlx-bench.sh --smoke
# or per model:
scripts/tool-smoke.sh ollama gpt-oss:20b
scripts/tool-smoke.sh ollama qwen3-coder:30b
```

**MLX** — start server in one terminal, smoke in another:

```bash
# pick one:
scripts/mlx-bench.sh --serve gpt-oss-20b
scripts/mlx-bench.sh --serve qwen3.6-35b-4bit
scripts/mlx-bench.sh --serve qwen3.6-35b-8bit    # only if 4bit wins nothing
scripts/mlx-bench.sh --serve gemma-4-12b-4bit
scripts/mlx-bench.sh --serve gemma-4-26b-4bit

# second terminal:
scripts/tool-smoke.sh openai http://127.0.0.1:8000/v1 gpt-oss-20b
scripts/tool-smoke.sh openai http://127.0.0.1:8000/v1 qwen3.6-35b-4bit
scripts/tool-smoke.sh openai http://127.0.0.1:8000/v1 gemma-4-12b-4bit
```

Pass = **turn 2 emits `write_file` or `edit_file`** with `<` in content.

## Stage 2 — Zed manual (5 min each)

Add a second provider (keep `hearth`):

```json
"mlx": {
  "api_url": "http://127.0.0.1:8000/v1",
  "available_models": [
    { "name": "gpt-oss-20b", "display_name": "gpt-oss-20b (MLX)", "max_tokens": 65536 },
    { "name": "qwen3.6-35b-4bit", "display_name": "qwen3.6-35b-4bit (MLX)", "max_tokens": 65536 },
    { "name": "gemma-4-12b-4bit", "display_name": "gemma-4-12b-4bit (MLX)", "max_tokens": 131072 }
  ]
}
```

Agent profile **build**: ask for a small real edit in this repo (e.g. add a
comment to a script). Compare to `hearth` / `local-big`.

## Stage 3 — code bench (optional)

Only after tool smoke passes:

```bash
# Ollama GGUF tags (already pulled):
scripts/bench.sh gpt-oss:20b

# MLX: no Ollama tag — bench is Ollama-direct today. Quality read on tool-smoke
# + Zed session is enough for agent role decisions.
```

## Decision rules

| Outcome | Action |
|---|---|
| MLX `gpt-oss` ≈ Ollama `gpt-oss` in Zed | Simplification candidate — Zed → MLX direct |
| `qwen3.6-35b-4bit` beats `gpt-oss` on tools + acceptable speed | Bench harder; ADR before role swap |
| `gemma-4-*` wins on speed, tools OK | Consider for `local-chat` or light agent |
| Any candidate fails tool smoke | Do not promote — regardless of benchmarks |

Nothing becomes a role until `scripts/swap-role.sh` + `docs/MODELS.md` + ADR.

## Official MLX alternative (no Rapid-MLX)

Apple’s path — fewer tool parsers, good for sanity check:

```bash
pip install mlx-lm
mlx_lm.server --model mlx-community/Qwen3.6-35B-A3B-4bit --port 8080
# Zed → http://127.0.0.1:8080/v1
```

Qwen3.6 may need `mlx-vlm` for vision weights; Rapid-MLX hides that difference.
