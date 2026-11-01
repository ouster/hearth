# LM Studio, MLX, and Apple Silicon local servers (1 November 2026)

Pages below were opened on 1 November 2026. Speed figures are included only when the source names a machine and a date. Vendor headlines that omit both are recorded as claims, not benchmarks.

## What changed in LM Studio from about 0.4.14 through the newest release?

### Takeaway

The newest version on the LM Studio changelog index is **0.4.28** (notes followed by **31 October 2026**). Since 0.4.14 the app has gained stable MTP speculative decoding, llama.cpp assistant drafters (DFlash, DSpark, MTP), a Mac-only Splash engine, and explicit Linux and Windows builds, including Windows on ARM with CUDA 13. The MLX engine still does not use built-in MTP heads, according to an open `mlx-engine` issue last updated in the August 2026 discussion.

### Cited Findings

Changelog index: https://lmstudio.ai/changelog/lmstudio. On that page a date line sits after each version's notes. Those dates are treated here as that version's publish date.

- **0.4.28**, notes followed by 31 October 2026. Build 1 fixed Flint chat-template parsing. Build 2 fixed macOS "Restart to apply update" reopening the current version instead of installing the update. — [Changelog index](https://lmstudio.ai/changelog/lmstudio)
- **0.4.27**, 29 October 2026. Improved LM Link reliability on large transfers and runtime discovery. Added Radeon 8065S detection for ROCm. Fixed switching to bundled MTP so it no longer keeps a previously selected draft model. On Mac, added maximum-memory and Neural Engine Prefill controls for Splash models, and fixed compatibility checks for M5-only Metal runtimes. — [Changelog index](https://lmstudio.ai/changelog/lmstudio)
- **0.4.26**, 13 October 2026. llama.cpp runtime updated to **2.50.0** (upstream b11337). Coexistence with Bionic 1.1.8+: Bionic can use LM Studio for local inference while LM Studio is running. CUDA 13 support on Windows ARM, plus a later build that fixed Windows on ARM CUDA not being detected. New endpoints: `/v1/systemone` (Jev / TypeSafe AI) and `/v1/decisions` (described as OpenAI-compatible). `lms` compatibility with Bionic fixed. — [Changelog index](https://lmstudio.ai/changelog/lmstudio)
- **0.4.25**, 19 September 2026. Mac: Splash engine on Apple Silicon **M3 or newer**, **macOS 26.4 or newer**. — [Changelog index](https://lmstudio.ai/changelog/lmstudio)
- **0.4.24**, 9 September 2026. Advanced llama.cpp argument overrides for GGUF loads via LM Studio Engine Protocol. Improved DSpark and DFlash assistant-drafter compatibility heuristics. Fixed Loaded Instances showing the wrong context length, and fixed `/api/v1/chat` splitting text and image inputs into separate user messages. — [Changelog index](https://lmstudio.ai/changelog/lmstudio)
- **0.4.23**, 28 August 2026. Reliability improvement for Qwen 3.8 Flash Next. No engine note. — [Changelog index](https://lmstudio.ai/changelog/lmstudio)
- **0.4.22**, 28 August 2026. DFlash, DSpark, and MTP assistant drafters, **requiring llama.cpp engine 2.29.1 or newer**. Tool results may return images on OpenAI `/v1/responses` and `/v1/chat/completions`, and on Anthropic `/v1/messages`. Linux: AppImage startup without FUSE 2 and without the Chromium sandbox; `lms` wake-up for AppImage; `.deb` desktop icons; in-app updates for AppImage and `.deb`; Wayland shortcut focus fix. — [Changelog index](https://lmstudio.ai/changelog/lmstudio)
- **0.4.21**, 12 August 2026. Local-server API key when the enterprise internal-network endpoint mode is on. mmap, mlock, and direct I/O load settings for llama.cpp engines 2.28.1 and newer. — [Changelog index](https://lmstudio.ai/changelog/lmstudio)
- **0.4.20**, 22 July 2026. Enterprise internal-network model endpoint. This device's models can be used in Bionic over LM Link. Developer setting for the llama.cpp engine log level. — [Changelog index](https://lmstudio.ai/changelog/lmstudio)
- **0.4.19**, 7 July 2026. LM Studio Engine Protocol defaulted on (beta in build 1, stable in build 2). Fixed reasoning being replayed as normal content on `/v1/responses` and in the chat UI. `/reasoning` added to `lms chat`. — [Changelog index](https://lmstudio.ai/changelog/lmstudio)
- **0.4.18**. Individual page has no date. Reasoning on/off could be ignored by some models; chat-title generation fixed for some reasoning models; guidance for llama.cpp options that move when Engine Protocol is enabled. — [0.4.18 notes](https://lmstudio.ai/changelog/lmstudio/lmstudio-v0.4.18)
- **0.4.17**. Individual page has no date. Build 4 fixed `/v1/responses` with `previous_response_id` causing excessive prompt processing, and fixed assistant output being replayed on a continuation. Engine Protocol turned off by default, including for people upgrading from beta builds. — [0.4.17 notes](https://lmstudio.ai/changelog/lmstudio/lmstudio-v0.4.17)
- **0.4.16**. Individual page has no date. "Locally" iPhone/iPad app uses LM Link. LM Link no longer requires a waitlist. Default context length set to 8k tokens. GGUF multi-GPU selection bugs fixed on some CUDA 12, ROCm, and Vulkan setups. — [0.4.16 notes](https://lmstudio.ai/changelog/lmstudio/lmstudio-v0.4.16)
- **0.4.15**. Individual page has no date. Engine Protocol beta 2. Fixed a bug that dropped the prompt cache on every message when using Claude Code. CUDA tensor parallelism for multi-GPU loads. llama.cpp "Physical Batch Size" load option. `/v1/messages` accepts `system` messages in the messages array (Claude Code invalid-role fix). REST hang when HTTP/2 clients sent upgrade headers. — [0.4.15 notes](https://lmstudio.ai/changelog/lmstudio/lmstudio-v0.4.15)
- **0.4.14**. Individual page has no date. Build 2 was the beta of MTP speculative decoding; build 4 called it stable: "Speeds up generation with models that include built-in multi-token prediction heads." The 0.4.14 page does not name an engine. Also fixed a non-MTP speculative-decoding error while MTP was enabled, and a chat UI bug that could strip whitespace when using MTP. Build 1 was the beta of LM Studio Engine Protocol. — [0.4.14 notes](https://lmstudio.ai/changelog/lmstudio/lmstudio-v0.4.14)
- A bug report against **0.4.14 build 4** includes runtime logs dated **29 May 2026**, so that build was already in use by then. The same log shows a VLM prompt-cache store (`cached_tokens=0`, then `VLM prompt cache disk usage`) for an MLX Qwen-family checkpoint, meaning a disk prompt cache existed and missed on that model. — [lmstudio-bug-tracker#1977](https://github.com/lmstudio-ai/lmstudio-bug-tracker/issues/1977)
- Separate-draft speculative decoding (a smaller draft model, not MTP heads) was already documented for **both** the llama.cpp and MLX engines in LM Studio **0.3.10**, which is before this window. — [LM Studio 0.3.10 blog](https://lmstudio.ai/blog/lmstudio-v0.3.10)
- `mlx-engine` issue, environment line "current release as of 2026-08-20": the MLX engine loads a checkpoint's built-in MTP (`nextn`) heads and does not use them, with no load-time notice. The reporter's first numbers are explicitly "normal chat use, not a controlled harness." A later comment on the same issue gives a controlled A/B: **M5 Max, 128 GB**, MLX runtime **1.11.0** (vendored `mlx_vlm` 0.6.5), temp 0, 512 tokens, target `lmstudio-community/Qwen3.8-27B-MLX-4bit` plus drafter `mlx-community/Qwen3.8-27B-MTP-4bit`. Baseline about **33 tok/s** through both the LM Studio server and `mlx_vlm.generate`. With `--draft-kind mtp`: prose 33.1 → 52.6 tok/s (61.8% acceptance), code 32.8 → 64.6 (87.1%), reasoning 32.9 → 60.6 (86.9%). That comment is an issue report, not an LM Studio publication. — [mlx-engine#370](https://github.com/lmstudio-ai/mlx-engine/issues/370)
- On current `mlx-engine` main, as quoted in issue 368, `BatchedVisionModelKit.is_draft_model_compatible()` returns false unconditionally and `load_draft_model` raises "Speculative decoding is not currently supported for batched vision models." Any `config.json` with `vision_config` takes that path, including text-only requests to a VLM. — [mlx-engine#368](https://github.com/lmstudio-ai/mlx-engine/issues/368)
- LM Studio 0.3.4 and newer for Mac ships `mlx-engine`, built on `mlx-lm`, `mlx-vlm`, and Outlines. The README's speculative-decoding demo is a separate draft model, not MTP heads. — [lmstudio-ai/mlx-engine](https://github.com/lmstudio-ai/mlx-engine/)
- **0.4.0** (before the requested floor, needed for the MLX batching timeline): parallel requests with continuous batching, default 4 slots, "supported for LM Studio's llama.cpp engine, with MLX coming later." Same release introduced headless `llmster`, installed on Linux/Mac with `curl -fsSL https://lmstudio.ai/install.sh | bash` and on Windows with `irm https://lmstudio.ai/install.ps1 | iex`. — [0.4.0 notes](https://lmstudio.ai/changelog/lmstudio/lmstudio-v0.4.0)
- Rapid-MLX's comparison table states that LM Studio continuous batching on the **MLX** engine dates from **0.4.2**. That claim was not checked against the 0.4.2 changelog page. — [Rapid-MLX README](https://github.com/raullenchai/Rapid-MLX/)
- Prompt-cache bug reports, not changelog features: MLX GPT-OSS 20B reprocessed the whole prompt on every turn in 0.4.8+1 while the GGUF of the same model reused cache ([#1697](https://github.com/lmstudio-ai/lmstudio-bug-tracker/issues/1697)). Against 0.4.17-beta+3, `/v1/responses` plus `previous_response_id` rebuilt a geometrically growing context on both GGUF (`llama.cpp-mac-arm64-apple-metal-advsimd@2.23.0`) and MLX (`mlx-llm-mac-arm64-apple-metal-advsimd@1.9.0`); the reporter said `/v1/chat/completions` prefix cache stayed healthy, and that MLX `cached_tokens=0` was model-specific (Gemma 4 MLX reported partial cache). 0.4.17 build 4 later says it fixed the excessive-prompt-processing bug. — [#2074](https://github.com/lmstudio-ai/lmstudio-bug-tracker/issues/2074), [0.4.17 notes](https://lmstudio.ai/changelog/lmstudio/lmstudio-v0.4.17)
- API surface already present by early 0.4, from the API changelog: native `/api/v1/*` in 0.4.0; Anthropic `POST /v1/messages` in 0.4.1. — [API changelog](https://lmstudio.ai/docs/developer/api-changelog)

### Inferences

- A localhost OpenAI-compatible server is the product's default shape: chat completions and the Responses API are both in the 0.4.2x fixes, and Anthropic `/v1/messages` has been there since 0.4.1. 0.4.26 adds two more local routes, `/v1/systemone` and `/v1/decisions`.
- MTP in this window is a llama.cpp feature. 0.4.14's stable MTP note does not name the engine; 0.4.22 then requires llama.cpp 2.29.1+ for DFlash, DSpark, and MTP drafters, and the August 2026 `mlx-engine` issue says the MLX path still ignores built-in `nextn` heads. Nothing through 0.4.28 says that gap closed.
- Prompt cache is a real LM Studio mechanism (0.4.15 Claude Code fix; disk VLM cache visible in May 2026 logs) and it is uneven on MLX. The Responses-API blow-up was acknowledged and marked fixed in 0.4.17; that note does not say every MLX model now reports `cached_tokens`.
- Splash is a third Mac runtime, beside llama.cpp and MLX. It is gated to M3+ and macOS 26.4+, and 0.4.27 exposes memory and Neural Engine prefill controls for it. It is not the cross-platform engine.
- Linux and Windows are shipping targets in this window (AppImage, `.deb`, CUDA, ROCm, Vulkan, Windows ARM CUDA 13, headless `llmster`). The Mac-only pieces are MLX and Splash.

### Gaps

- No date on the changelog pages for 0.4.14, 0.4.15, 0.4.16, 0.4.17, or 0.4.18. The index stopped at 0.4.19 behind "Load more."
- 0.4.2's own changelog was not opened, so "MLX continuous batching since 0.4.2" is only Rapid-MLX's statement.
- No LM Studio post through 0.4.28 was found that says the MLX engine uses MTP heads. The August 2026 issue may be stale relative to 0.4.27's "bundled MTP" fix, which does not name an engine.
- The default listen port was not on the pages opened.
- Splash's own project page was not opened. What is known is LM Studio's changelog plus oMLX calling Splash as an external process (see the oMLX section).

## What is new in MLX, mlx-lm, and mlx-vlm, and do they serve an OpenAI-compatible API?

### Takeaway

MLX **v0.32.4** (14 October 2026) is the framework, not a server. **mlx-lm v0.32.2** (16 October 2026) serves an OpenAI-style chat API on `localhost:8080` via `mlx_lm.server`; the server source on main implements `/v1/chat/completions` and `/v1/completions`, and does not register `/v1/responses`. **mlx-vlm v0.7.11** (28 October 2026) has its own server and, in this month's release notes, a Responses API. A third-party package, `mlx-openai-server` **v1.8.1** (3 May 2026), is the fuller OpenAI facade and is documented as Apple Silicon only.

### Cited Findings

MLX framework, GitHub releases API, five newest tags:

- **v0.32.4**, published 2026-10-14. Array and kernel fixes, including VJPs for scaled dot-product attention and gated delta net, and Python 3.15 support. — [mlx v0.32.4](https://github.com/ml-explore/mlx/releases)
- **v0.32.3**, published 2026-09-29. Includes a fix for sorted `gather_qmm` NAX row overflow above 32K. — same releases list
- **v0.32.2**, published 2026-08-25. Includes a GQA-8 decode attention change and a bound on GGUF metadata strings. — same
- **v0.32.1**, published 2026-08-18. Warns at configure time when NAX kernels are disabled. CUDA RMSNorm and FSDP work are in the notes. — same
- **v0.32.0**, published 2026-07-07. CUDA qmm fix and other framework work. — same

mlx-lm, GitHub releases API:

- **v0.32.2**, published 2026-10-16. Attention scaling fix for MiMo-V2-Flash, an SMM mask fix, Muse Spark Hugging Face names. — [mlx-lm v0.32.2](https://github.com/ml-explore/mlx-lm/releases/tag/v0.32.2)
- **v0.32.1**, published 2026-10-15. Muse chat-template fix. — [v0.32.1](https://github.com/ml-explore/mlx-lm/releases/tag/v0.32.1)
- **v0.32.0**, published 2026-10-15 (created 2026-09-30). Server accepts `max_tokens: 0` and the generator then rejects it. Also NVFP4 global scale for quantized MoEs, a Qwen 3.5 parallel head, tool-call parser fixes, MiniMax M3 long-generation crash fix, and `meta-models/Muse-Spark-Open-816B-A42B-NVFP4`. The notes do not mention `/v1/responses`. — [v0.32.0](https://github.com/ml-explore/mlx-lm/releases/tag/v0.32.0)
- **v0.31.3**, published 2026-04-22. Thread-local generation stream to match MLX v0.31.2. Server fixes for parallel tool calls. Gemma 4 tool-parser fixes. — [v0.31.3](https://github.com/ml-explore/mlx-lm/releases/tag/v0.31.3)
- **v0.31.2**, published 2026-04-07. Highlights include caching the system prompt and user messages for non-trimmable caches, and a batch-generator refactor. Server: `--allowed-origins`, missing `Content-Length` handling. Also a speculative-decoding output-corruption fix and Gemma 4 support. — [v0.31.2](https://github.com/ml-explore/mlx-lm/releases/tag/v0.31.2)

mlx-lm server, current docs and source (no release pin on the raw files; read as `main` on 1 November 2026):

- `mlx_lm.server --model <path_or_hf_repo>` listens on **port 8080** of localhost. The docs say the HTTP API "is intended to be similar to the OpenAI chat API" and "is not recommended for production as it only implements basic security checks." Documented example is `POST localhost:8080/v1/chat/completions`. Optional `draft_model` and `num_draft_tokens` (default 3) are request fields for speculative decoding. — [mlx_lm/SERVER.md](https://github.com/ml-explore/mlx-lm/blob/main/mlx_lm/SERVER.md)
- `server.py` on main routes only `/v1/completions`, `/v1/chat/completions`, and `/chat/completions`. There is no `/v1/responses` entry. — [mlx_lm/server.py](https://github.com/ml-explore/mlx-lm/blob/main/mlx_lm/server.py)
- An official example uses the OpenAI Python client against `http://localhost:8080/v1` with `api_key="not-needed"` and `client.chat.completions.create`, including tools. Copyright line on that example is 2025. — [openai_tool_use.py](https://github.com/ml-explore/mlx-lm/blob/main/mlx_lm/examples/openai_tool_use.py)
- Pull request **#1207**, opened 2026-04-27, still **open** on its last update **2026-09-25**, proposes adding `/v1/responses` because Codex CLI v0.125+ requires it. The PR text treats `/v1/chat/completions` as the existing endpoint. It was not in the v0.32.2 release notes of 16 October 2026, and it is absent from `server.py` on main. — [mlx-lm#1207](https://github.com/ml-explore/mlx-lm/pull/1207)

mlx-vlm, GitHub releases API:

- **v0.7.11**, published 2026-10-28. Server work in the notes: live-input STT WebSocket on the audio worker, and "Expose generation timings in Responses API results." Also NVFP4 AWQ loading, text-only input truncation fix, MiniMax M3.1 Flash, Nemotron 3.5 Parse, SoMark OXR-1.0. — [mlx-vlm releases](https://github.com/Blaizzy/mlx-vlm/releases)
- **v0.7.10**, published 2026-10-21. Muse Spark Open with audio, video, and images. Native Flint BF16. NVFP4 scale and MoE offload fixes. — same
- **v0.7.9**, published 2026-10-19. "Add Nemotron 3.5 Super VL with MTP and Bolt support." Live image-resolution controls on the server. "Release prompt cache of finished SpeculativeGenerationBatch." Qwen 3.5 ragged decode reads strided K/V instead of copying the KV cache every step. — same
- **v0.7.8**, published 2026-10-13. EmbeddingGemma 2 multimodal embeddings. Qwen 3.5 uses mlx-lm's packed gated-delta kernel for prefill. — same
- **v0.7.6**, published 2026-10-05. Stream compaction progress and recovery of oversized requests. — same

Third-party OpenAI server on top of these libraries:

- `cubist38/mlx-openai-server` **v1.8.1**, published 2026-05-03. Fixes VLM audio inputs, LM thread affinity, and an MLX-VLM batch scheduler. **v1.8.0**, 2026-04-26, added KV-cache quantization, continuous batching, and disk-backed prompt KV cache. PyPI describes v1.8.1 as an OpenAI-compatible server for MLX models, requiring macOS on Apple Silicon and Python 3.11+. Backends: `lm` → mlx-lm (chat, responses), `multimodal` → mlx-vlm (chat, responses), plus mflux image generation/edit, mlx-embeddings, and mlx-whisper. Default base URL in the docs is `http://localhost:8000/v1`. The releases listing showed v1.8.1 as the newest tag. — [GitHub releases](https://github.com/cubist38/mlx-openai-server/releases), [PyPI](https://pypi.org/project/mlx-openai-server/)

### Inferences

- For a minimal OpenAI-compatible text server on 127.0.0.1, stock `mlx_lm.server` qualifies for Chat Completions and does not qualify for clients that require `/v1/responses` (the still-open PR says Codex CLI is in that group).
- mlx-vlm is the vision/audio server, and its October 2026 notes treat a Responses API as something the server already returns timings for. A full endpoint list for mlx-vlm was not opened, so chat-completions parity is not copied from mlx-lm.
- `mlx-openai-server` is the project that deliberately covers both chat and responses, plus images, embeddings, and audio, and it is the one that states "Apple Silicon only" in the package text. Its last release in the listing is May 2026, about five months behind mlx-lm 0.32.2 and mlx-vlm 0.7.11.
- MLX 0.32 is not a Mac-only codebase: the 0.32.0–0.32.1 notes include CUDA work, and 0.32.1–0.32.3 mention NAX kernels (Apple's M5-class tensor units). That is framework support. It is not evidence that `mlx_lm.server` is a good Linux or Windows inference server.

### Gaps

- mlx-vlm's server README was not opened, so its exact route list and bind address are not recorded here. The release notes are enough to say a server and a Responses API exist.
- Whether PR #1207 landed on a branch after 25 September 2026 without a release note was not checked beyond `main`'s `server.py`, which does not route `/v1/responses`.
- No measured tok/s figure for stock `mlx_lm.server` was taken from these pages with both a machine and a date. Rapid-MLX's "up to 4× faster than mlx-lm" headline is a README claim and is not used as a benchmark.
- No page was opened that shows `mlx_lm.server` running well on Linux or Windows.

## Which other Apple Silicon servers are real OpenAI-compatible alternatives in 2026?

### Takeaway

Four projects are verifiably in use as local servers on Apple Silicon in 2026: **Ollama** (GGUF plus a Mac MLX preview), **Rapid-MLX** (MLX, OpenAI and Anthropic), **oMLX** (MLX, with GGUF handed to an external Splash process), and **vllm-metal** (vLLM's OpenAI server with an MLX backend). MLC-LLM was not verified as a 2026 project from the pages found. Rapid-MLX published its own 12 October 2026 comparison on a Mac Studio M5 Max with 36 GB; those numbers are vendor measurements.

### Cited Findings

**Ollama.** OpenAI-compatible local server at `http://localhost:11434/v1/`. Documented local routes include `/v1/chat/completions` (streaming, JSON mode, vision, tools, reasoning, logprobs), `/v1/completions`, `/v1/models`, `/v1/embeddings`, and audio routes. `POST /v1/responses` was added in **Ollama v0.13.3**. The same docs page says two things that conflict: "Only the non-stateful flavor is supported (i.e., there is no `previous_response_id` or `conversation` support)" and, under supported features, "Stateful requests." `previous_response_id` and `conversation` appear in a following list. The API key is required by clients and ignored by the local server. — [OpenAI compatibility](https://docs.ollama.com/api/openai-compatibility)

Ollama MLX, from Ollama's own blog:

- **30 March 2026.** MLX on Apple Silicon is a preview in Ollama **0.19**. The post says M5, M5 Pro, and M5 Max use the new GPU Neural Accelerators for time to first token and decode. The preview "accelerates the new Qwen3.5-35B-A3B model" and asks for a Mac with more than 32 GB unified memory. Launch examples use `qwen3.5:35b-a3b-coding-nvfp4`. Testing date in the post: **29 March 2026**, Qwen3.5-35B-A3B NVFP4 versus the previous implementation at Q4_K_M on Ollama 0.18. The post then says Ollama 0.19 "will see even higher performance (1851 token/s prefill and 134 token/s decode when running with int4 quantization)." The fetched post text does not name which Mac produced 1851 and 134, so those two numbers are not used as a benchmark. — [Ollama MLX preview](https://ollama.com/blog/mlx)
- **11 June 2026.** A later post says the MLX engine was updated again: NVFP4, fused Metal kernels, and a snapshot system so agent sessions can resume prefix state when the next request is not a pure extension of the last one (subagents, thinking tokens dropped from history, retries). Getting started is `ollama run gemma4:12b-mlx`. The "about 20% faster" line in that post is an average over 10 runs of an 8,300-token prompt; the fetched text does not name the Mac, so the percentage is not used as a benchmark. — [Ollama MLX performance](https://ollama.com/blog/mlx-performance)
- Ars Technica, March 2026, summarizing the same preview: MLX support is in Ollama 0.19, at announcement time only the 35B Qwen3.5 variant, Apple Silicon, at least 32 GB RAM, and Ollama had not given a timeline for leaving preview or adding models. — [Ars Technica](https://arstechnica.com/apple/2026/03/running-local-models-on-macs-gets-faster-with-ollamas-mlx-support/)
- Rapid-MLX's comparison table, which is their description of Ollama rather than Ollama's docs: on a Mac, Ollama has a GGML/GGUF engine plus an MLX engine for safetensors models; APIs are the Ollama API, an OpenAI-compatible subset, and an Anthropic-compatible subset; parallel requests are per model via `OLLAMA_NUM_PARALLEL` (default 1); prompt cache reuses the previous request's KV cache, with `OLLAMA_KV_CACHE_TYPE` for quantization. — [Rapid-MLX README](https://github.com/raullenchai/Rapid-MLX/)

**Rapid-MLX.** Apache-2.0. OpenAI- and Anthropic-compatible MLX server for Apple Silicon, aimed at tool calling for coding agents. `rapid-mlx serve` binds **127.0.0.1** and, if `--port` is omitted, the first free port from 8000 to 8009. Documented routes include `/v1/chat/completions`, `/v1/responses`, and `/v1/messages`. Requirements: Apple Silicon, macOS 14 or later. Intel Macs are unsupported because it is built on MLX. Homebrew: `brew install rapid-mlx`. — [Getting started](https://rapidmlx.com/docs/getting-started), [README](https://github.com/raullenchai/Rapid-MLX/)

Their own comparison, labeled as such: **Mac Studio, M5 Max, 36 GB, 12 October 2026**, single run per engine, same 4-bit weights. Rapid-MLX **0.16.1** default (MTP on a text-only lane; image input off; `--no-spec-decode` serves images) versus oMLX **0.7.0** with its documented SSD cache directory, and LM Studio headless on its MLX runtime.

| Model | Metric | Rapid-MLX 0.16.1 | oMLX 0.7.0 | LM Studio |
|---|---|---:|---:|---:|
| Qwen3.5-9B | Decode tok/s | 115.5 | 77.9 | 81.0 |
| Qwen3.5-9B | 4 streams, aggregate tok/s | 248.2 | 224.6 | 230.0 |
| Qwen3.8-27B | Decode tok/s | 37.9 | 25.3 | 26.0 |
| Qwen3.8-27B | 4 streams, aggregate tok/s | 82.8 | 75.3 | 69.7 |
| Qwen3.6-35B | Decode tok/s | 173.4 | 145.8 | 124.5 |
| Qwen3.6-35B | 4 streams, aggregate tok/s | 293.9 | 281.9 | 265.6 |
| Qwen3.6-35B | 2K-prompt first token, seconds | 0.55 | 1.14 | 1.49 |

The compare page says differences under about 5% are within run-to-run variation, and that this was a single run. The README headline "Up to 4× faster than Apple's MLX (mlx-lm) on the same weights" does not name a machine in that sentence and is not treated as a benchmark. — [Compare page](https://rapidmlx.com/compare/omlx), [README](https://github.com/raullenchai/Rapid-MLX/)

What the README says it is better at, as product claims rather than the table: per-model tool-call parsers (27 modules), continuous batching, an in-memory radix prefix cache with disk save/restore, and OpenAI plus Anthropic on one process. License row in that README: Rapid-MLX Apache-2.0; oMLX Apache-2.0; Ollama MIT; LM Studio "closed-source app; its MLX engine and `lms` CLI are MIT"; mlx-lm MIT.

**oMLX** (`jundot/omlx`). Apache-2.0. "LLM inference server with continuous batching & SSD caching for Apple Silicon — managed from the macOS menu bar." Requires macOS 15+, Python 3.11–3.13, Apple Silicon M1 through M5. `omlx serve` discovers models under a directory. OpenAI clients use `http://localhost:8000/v1`. Endpoint table on the README: `POST /v1/chat/completions`, `/v1/completions`, `/v1/messages`, `/v1/embeddings`, `/v1/rerank`, `/v1/systemone`, `GET /v1/models`, plus tokenize/detokenize. `/v1/responses` is not in that table. A security note mentions "stored Responses," which is not the same as documenting the route. Primary engine is MLX. GGUF files are listed and "run on an external engine." Splash is that external engine for named Qwen3.8-27B and Qwen3.6-35B-A3B checkpoints in MLX, NVFP4, and GGUF: official Splash on M3 or later, "Splash M1" on M1/M2. Cache design: vLLM-style block KV cache, RAM hot tier plus SSD cold tier, reused across restarts. The project says it started from `vllm-mlx` v0.1.0. A community benchmark table exists; rows are per-user submissions (chips, quant, context, date), not a cross-engine bake-off. — [README](https://github.com/jundot/omlx/), [community table](https://omlx.ai/benchmarks/performance?cursor=WyJwZXJmb3JtYW5jZTpoaWRlX3NwZWNwcmVmaWxsPTEiLCIyMDI2LTEwLTI0IDA4OjM5OjA0Iiw1NzM4NDgsMiwyLDEwXQ%3D%3D&hide_specprefill=1)

One sentence on what it is better at: keeping prefix KV cache on SSD so a coding session can resume after a restart or a context branch, which is the reason the author gives for building it.

**vllm-metal** (`vllm-project/vllm-metal`). A vLLM plugin. Upstream vLLM supplies the API server, scheduler, and paged block manager; `mlx_lm` supplies token-wise layers; vllm-metal supplies paged varlen attention, M5 NAX prefill, and speculative decoding. Requirements: macOS 15 or later, Apple Silicon. README news lines: **2026/08**, M5 NAX tensor units accelerate MHA, GQA, and MQA prefill, and Qwen3.8 (`mlx-community/Qwen3.8-27B-8bit`) runs as a hybrid SDPA + GDN model; **2026/04**, v0.2.0 made the unified paged varlen Metal kernel the default attention backend. The "83x TTFT, 3.6x throughput compared to v0.1.0" line on that README does not name a machine and is not used as a benchmark. Install path documented: Homebrew tap `vllm-project/vllm-metal`, then `vllm serve`. Model matrix is MLX-first, with a smaller PyTorch MPS column; several families are marked partial. — [vllm-metal](https://github.com/vllm-project/vllm-metal/), [supported models](https://docs.vllm.ai/projects/vllm-metal/en/latest/supported_models/), [installation](https://github.com/vllm-project/vllm-metal/blob/main/docs/installation.md)

Docker's post on the same plugin: vllm-metal was built with Docker and the vLLM project, runs MLX-format safetensors, and is started by Docker Model Runner as a host process because Metal has no container GPU passthrough. The runner then exposes vLLM's OpenAI API, and the post also says an Anthropic-compatible API. The fetched excerpt has no publication date. Platform table in that post: Linux vLLM on NVIDIA CUDA, Windows via WSL2 vLLM on NVIDIA CUDA, macOS vllm-metal on Apple Silicon. Docker Desktop 4.62 or later is the Mac requirement named there. — [Docker blog](https://www.docker.com/blog/docker-model-runner-vllm-metal-macos/)

One sentence on what it is better at: it is the way to keep vLLM's scheduler, paged KV cache, and OpenAI server while the math runs on MLX.

**MLC-LLM.** The search that asked for a 2026 status returned the **7 June 2024** MLC blog: `mlc_llm serve` with an OpenAI-style REST API and a compiled model library. No 2026 release, tag, or changelog was in the results. It is not treated as a confirmed 2026 alternative. — [MLC blog, 2024](https://blog.mlc.ai/2024/06/07/universal-LLM-deployment-engine-with-ML-compilation)

**LM Studio itself** belongs in this list as the incumbent: OpenAI, Anthropic, and its own `/api/v1` on the local machine, with llama.cpp for GGUF and MLX for Apple Silicon safetensors, plus Splash on newer Macs. See the first section.

### Inferences

- Real 127.0.0.1 OpenAI servers on Apple Silicon, confirmed from their own docs: LM Studio, Ollama (`:11434`), Rapid-MLX (`127.0.0.1`, port 8000 unless taken), oMLX (`:8000`), `mlx_lm.server` (`:8080`), `mlx-openai-server` (`:8000`), and `vllm serve` via vllm-metal.
- Format split: Rapid-MLX, oMLX's main path, mlx-lm, mlx-vlm, mlx-openai-server, and vllm-metal want MLX/safetensors weights. Ollama's portable path and LM Studio's non-Mac path want GGUF. oMLX can show GGUF in the model list and hand it to Splash; that is a second engine, not MLX loading GGUF itself.
- If the client is Codex-style and needs `/v1/responses`, Rapid-MLX documents that route, Ollama documents a non-stateful version since v0.13.3, and stock mlx-lm on main does not implement it. oMLX's published route table does not list it.
- Rapid-MLX's October table is the only same-machine, same-weights, dated comparison among Rapid-MLX, oMLX, and LM Studio found here. It is single-run and first-party. It is still the best sourced speed evidence in this note, and it should stay labeled as Rapid-MLX's measurement.

### Gaps

- Latest oMLX and Rapid-MLX tags after the 12 October 2026 comparison (oMLX 0.7.0, Rapid-MLX 0.16.1) were not looked up. Those versions are "what the comparison ran," not proven to be current on 1 November.
- Ollama's docs page contradicts itself on stateful Responses. The explicit sentence says stateful `previous_response_id` is absent.
- vllm-metal's default port was not copied from a docs page. Docker's blog date was not in the excerpt.
- MLC-LLM in 2026: no release found.
- No independent (non-vendor) bake-off with machine and date was opened for Rapid-MLX vs oMLX vs LM Studio vs Ollama. A Zenn write-up and an Ante Kapetanovic post turned up in search; their numbers are omitted because the excerpts did not jointly give a clear official machine and a publication date that could be separated from Ollama's own undated-machine figures.

## What can run on Linux and Windows as well as on a Mac?

### Takeaway

**Ollama** is the single product whose own docs show one local OpenAI API on the machine you are on, including Linux and Windows, with the MLX engine as a Mac preview on top of the GGUF path. **LM Studio is already not Mac-only**: 0.4.22 ships AppImage and `.deb` updates, and 0.4.26 adds CUDA 13 on Windows ARM, while MLX and Splash stay on the Mac. **vLLM** is the Linux NVIDIA server; the Mac port is a different plugin, vllm-metal, and Docker Model Runner is a shared CLI over those different backends. MLX's CUDA commits do not amount to a documented Linux OpenAI server.

### Cited Findings

- Ollama's OpenAI compatibility page documents the local server at `localhost:11434` and also a separate cloud base URL `https://ollama.com/v1`. The local API is the one that can serve pulled models. Nothing on that page restricts the local server to macOS. The MLX preview posts are explicitly Apple Silicon and, in June, `gemma4:12b-mlx` / NVFP4 tags. — [OpenAI compatibility](https://docs.ollama.com/api/openai-compatibility), [30 March 2026](https://ollama.com/blog/mlx), [11 June 2026](https://ollama.com/blog/mlx-performance)
- LM Studio changelog evidence that the app and `llmster` are multi-OS, collected in the first section: 0.4.0 installers for Linux/Mac and Windows; 0.4.15–0.4.16 CUDA, ROCm, and Vulkan multi-GPU; 0.4.22 Linux AppImage and `.deb`, including in-app updates; 0.4.26 Windows ARM CUDA 13 and llama.cpp **2.50.0**. MLX and Splash lines are marked `[Mac]`. — [Changelog index](https://lmstudio.ai/changelog/lmstudio)
- Rapid-MLX and oMLX both state Apple Silicon and a minimum macOS version. They are not Linux/Windows servers. — [Rapid-MLX install](https://rapidmlx.com/docs/getting-started), [oMLX README](https://github.com/jundot/omlx/)
- vllm-metal's requirements are macOS 15+ on Apple Silicon. Docker's platform table keeps CUDA vLLM for Linux and for Windows WSL2, and uses vllm-metal only on macOS. Same `docker model` commands, different backends. vllm-metal "runs natively on the host" because Metal is not passed into a container. — [vllm-metal install](https://github.com/vllm-project/vllm-metal/blob/main/docs/installation.md), [Docker blog](https://www.docker.com/blog/docker-model-runner-vllm-metal-macos/)
- MLX v0.32.0 and v0.32.1 release notes include CUDA kernel and FSDP work. mlx-lm's server doc does not describe a Linux or Windows setup. — [mlx releases](https://github.com/ml-explore/mlx/releases), [SERVER.md](https://github.com/ml-explore/mlx-lm/blob/main/mlx_lm/SERVER.md)
- The only MLC-LLM page found is the June 2024 announcement of one compiled engine and one OpenAI-style API across local and server environments. That is a 2024 design claim, not a 2026 status. — [MLC blog](https://blog.mlc.ai/2024/06/07/universal-LLM-deployment-engine-with-ML-compilation)

### Inferences

- The engine that can replace a Mac LM Studio **and** keep the same binary family on Linux and Windows is the GGUF / llama.cpp path. LM Studio already vendors that runtime (2.50.0 as of 0.4.26) on the non-Mac builds. Ollama is the other widely documented OpenAI server on all three operating systems; its MLX speed path does not come along to Linux or Windows.
- Choosing an MLX server (Rapid-MLX, oMLX, mlx-lm, vllm-metal) means a Mac-specific engine. vLLM's Linux CUDA server is a relative of vllm-metal at the API and scheduler layer, not the same Metal binary.
- There is no sourced 2026 candidate that is one MLX engine on the Mac and the same MLX engine, running well, on Linux and Windows.

### Gaps

- Standalone `llama-server` from upstream llama.cpp was not opened. The cross-platform llama.cpp facts here are LM Studio's vendored runtime and Ollama's GGUF path, not a fresh read of ggml-org's server README.
- Ollama's Linux and Windows install pages were not opened separately. Multi-OS support is inferred from the local API docs having no Mac restriction, from Ars describing Ollama as a general local runtime, and from the MLX posts calling out Apple Silicon as the special case. A dedicated install matrix was not fetched.
- No measurement was found of LM Studio's Linux or Windows llama.cpp build versus the Mac llama.cpp build on the same GGUF.
