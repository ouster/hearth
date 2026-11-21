# Nemotron 3.5 Bolt 74B-A9B MLX 4-bit — deep / coding challenger

Date: 2026-11-21. Not a role change. Weights:
`nativ-community/NVIDIA-Nemotron-3.5-Bolt-74B-A9B-4bit` (~40 GB *(repo)*,
loaded 39.88 GB). OpenMDW-1.1. VLM (`nemotron_h_omni`); oMLX loads it as
engine `vlm` with per-model `trust_remote_code`. Peak mem under 56 GB on
this 64 GB host.

| | coding-brain Coder-Next (2026-11-12) | deep-brain Qwen3.8-27B (notes) | Bolt 4bit (this run) |
|---|---|---|---|
| Tool-smoke | PASS | — | PASS |
| c1 tools | 10 / 10 | — | 10 / 10 |
| TTFT p50 (~30k) | 27.2 s | denser / slower class | **60.0 s** |
| Peak footprint | 52.0 GB | — | ~50–51 GB (manual `footprint`) |
| Short gen tok/s | — | ~26 class | ~50 tok/s on tasks 01–03 |

Slower agent TTFT than Coder-Next; much faster than Ripple (323 s). Fits as
swap-only (1 slot).

## Quality (`bench/tasks`)

| Task | tokens | s | Auto | Read |
|---|---|---|---|---|
| 01-bash-launchd | 124 | 2.6 | syntax-ok | — |
| 02-python-mcp-tool | 197 | 3.8 | syntax-ok | Concise |
| 03-refactor-judgment | 1526 | 26.1 | — | **Catches float-for-currency** (Decimal / ROUND_HALF_UP). Verbose mid |
| 04-long-context | 257 | 154.6 | — | **Uses the docs** at 96K ctx (refused at 64K: 66714 > 65536). Four dormant roles; Postgres `:5433`; no cloud-frontier fallback |

## Verdict

Strong swap candidate for **deep-brain** (quality + ~50 tok/s, multimodal).
Not a replacement for **coding-brain** on latency (60 s vs 27 s TTFT on
~30k tools). Do not change `roles.tsv` until a dedicated deep-brain
baseline c1 on the same harness is compared side-by-side and an ADR
accepts OpenMDW-1.1 + VLM engine for that role.
