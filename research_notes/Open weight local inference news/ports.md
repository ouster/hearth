# Linux and Windows servers behind Hearth's OpenAI loopback

Read 2026-11-01. Facts below are from the fetched pages and from the Hearth files named in each citation. Sentences marked **Judgment** are design choices, not claims those projects make.

Hearth's client contract, as built: one OpenAI-compatible server on `127.0.0.1:1234`, clients send the role name (`local-big`, `local-embed`), a Bearer token is required, CORS is off, JIT loading is off, `local-big` stays resident at context 131072 with 3 slots and draft MTP, `local-embed` stays resident beside it, and that port holds only local weights. Cloud is a separate path (`cloud-cheap` / Gemini via `ask-cloud`) and must not be attached to the local server. Sources: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), [docs/ROUTING.md](docs/ROUTING.md), [config/roles.tsv](config/roles.tsv), [docs/decisions/0016-lmstudio-direct.md](docs/decisions/0016-lmstudio-direct.md).

`config/roles.tsv` columns are `role`, `backend`, `model_key`, `ctx`, `slots`, `weights`, `draft`. Live rows: `local-big` and `local-embed` have backend `lmstudio`; `cloud-cheap` has backend `gemini`. `draft=mtp` means `lms load --speculative-draft-mtp`. The `local-big` weights path is an MLX 4-bit file. [config/roles.tsv](config/roles.tsv).

## llama.cpp llama-server

### Takeaway

`llama-server` from ggml-org/llama.cpp is an OpenAI-compatible loopback server with official Linux and Windows builds, an API key, a default bind of `127.0.0.1`, embeddings, parallel slots, and speculative decoding including an MTP type. One process does not do chat and embeddings together, and the default listen port is 9931, so matching Hearth's single `:1234` with two resident roles means router mode plus an explicit port, not a stock single-model launch.

### Cited Findings

- The server README lists OpenAI-compatible chat completions, responses, and embeddings; Anthropic Messages; parallel decoding; continuous batching; tool use; and speculative decoding. [llama.cpp server README](https://github.com/ggml-org/llama.cpp/blob/0ec4027a2a0183de87c007069adddc06e665f7de/tools/server/README.md) (blob `0ec4027`, fetched 2026-11-01).
- `--host` defaults to `127.0.0.1`. It accepts comma-separated IPs or UNIX socket paths ending in `.sock`. `--port` defaults to 9931. Quick start says a default launch listens on `127.0.0.1:9931`. Unix example is `./llama-server -m …`; Windows example is `llama-server.exe -m …`. [llama.cpp server README](https://github.com/ggml-org/llama.cpp/blob/0ec4027a2a0183de87c007069adddc06e665f7de/tools/server/README.md).
- `--api-key` takes one key or a comma-separated list (env `LLAMA_API_KEY`). Default is none. `--api-key-file` reads one key per line. OpenAI examples send `Authorization: Bearer …`. The Anthropic example sends `x-api-key`. [llama.cpp server README](https://github.com/ggml-org/llama.cpp/blob/0ec4027a2a0183de87c007069adddc06e665f7de/tools/server/README.md).
- `--embedding` / `--embeddings` "restrict to only support embedding use case; use only with dedicated embedding models" (default disabled). `POST /v1/embeddings` is the OpenAI-compatible route and requires pooling other than `none`. There is also a non-OpenAI `POST /embeddings`. [llama.cpp server README](https://github.com/ggml-org/llama.cpp/blob/0ec4027a2a0183de87c007069adddc06e665f7de/tools/server/README.md).
- `-np` / `--parallel` is "number of server slots" (default `-1` = auto). `--kv-unified-per-slot N` is "context limit per parallel slot (default: unset, behavior unchanged). when set without -c/--ctx-size, the shared KV pool is sized to n_parallel*N". `-c` / `--ctx-size` is "size of the prompt context" (default 0 = loaded from the model). The README does not say that `-c 131072 -np 3` gives each slot 131072 tokens. [llama.cpp server README](https://github.com/ggml-org/llama.cpp/blob/0ec4027a2a0183de87c007069adddc06e665f7de/tools/server/README.md).
- Speculative decoding flags include `--spec-type` with values `none`, `draft-simple`, `draft-eagle3`, `draft-mtp`, `draft-dflash`, `draft-dspark`, and several ngram modes (default `none`), plus `--spec-draft-model` / `-md` for a separate draft file. Cached models can list sidecars `mmproj`, `mtp`, `dflash`, `eagle3`, `dspark`. [llama.cpp server README](https://github.com/ggml-org/llama.cpp/blob/0ec4027a2a0183de87c007069adddc06e665f7de/tools/server/README.md).
- `--alias` sets "model name aliases, comma-separated (to be used by API)". In single-model mode the `model` field is ignored. In router mode `model` is required and routes the request. Default model `id` is the model path; `--alias` replaces that id (the README's example is `--alias gpt-4o-mini`). [llama.cpp server README](https://github.com/ggml-org/llama.cpp/blob/0ec4027a2a0183de87c007069adddc06e665f7de/tools/server/README.md).
- Router mode is `llama-server` with no model argument. It forwards each request to a child instance. `--models-preset` points at an INI file whose section names are presets; keys are CLI arguments. Preset-only keys include `load-on-startup`. The router controls host, port, API key, HF repo, and model alias, and strips or overwrites those on the child. Autoload is on by default; `--no-models-autoload` disables it. `--models-max` defaults to 4 (0 = unlimited) and unloads least-recently-used models past that cap. `--models-memory-margin` unloads until a new model fits. `POST /models/load` and `POST /models/unload` exist. [llama.cpp server README](https://github.com/ggml-org/llama.cpp/blob/0ec4027a2a0183de87c007069adddc06e665f7de/tools/server/README.md).
- CORS: `--cors-origins` defaults to `*`. The special value `localhost` reflects the Origin header only when it is localhost. There is no documented switch whose description is "CORS off". [llama.cpp server README](https://github.com/ggml-org/llama.cpp/blob/0ec4027a2a0183de87c007069adddc06e665f7de/tools/server/README.md).
- Release b9464 (2026-06-01, not marked pre-release in the release text) publishes Ubuntu x64 and arm64 CPU tarballs, Ubuntu Vulkan and ROCm tarballs, Windows x64 and arm64 CPU zips, and Windows x64 CUDA 12, CUDA 13, Vulkan, and HIP zips. Release b10636 (2026-08-26, pre-release) says the Windows CUDA/Vulkan/SYCL jobs build only the backend library and that `llama-server` with the embedded UI is injected into those zips from the Windows CPU package. The releases index shows pre-release b12023 on 2026-10-31 with Ubuntu x64/arm64 (CPU, Vulkan, CUDA 12, CUDA 13), Ubuntu ROCm 10.0, and Windows x64/arm64 CPU plus Windows CUDA, Vulkan, and ROCm 10.0. [b9464](https://github.com/ggml-org/llama.cpp/releases/tag/b9464), [b10636](https://github.com/ggml-org/llama.cpp/releases/tag/b10636), [releases index](https://github.com/ggml-org/llama.cpp/releases/).
- Docker examples are `ghcr.io/ggml-org/llama.cpp:server` and `:server-cuda`. Those examples pass `--host 0.0.0.0 --port 8080`, which is not the binary default. [llama.cpp server README](https://github.com/ggml-org/llama.cpp/blob/0ec4027a2a0183de87c007069adddc06e665f7de/tools/server/README.md).

### Inferences

- A single-model `llama-server` cannot be Hearth's one port. Chat and embeddings are different process modes, and single-model mode ignores the `model` name, which is the same silent substitution Hearth already warns about for an unknown id when JIT is off ([docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)). Router mode is the feature that keeps one listen port, two resident models, and a `model` field that selects a role.
- **Judgment:** generate the preset INI from `roles.tsv` in a script. Section names should be the role names. Do not write model tags into shell aliases. Pin context with the per-slot flag the README actually defines (`--kv-unified-per-slot` equal to the `ctx` column, plus `--parallel` equal to `slots`) rather than assuming `-c` is per slot.
- **Judgment:** `--no-models-autoload` plus `load-on-startup` is the match for "JIT off, no TTL". Leaving autoload on reintroduces the eviction behaviour ADR 0016 removed.
- **Judgment:** `--spec-type draft-mtp` is the flag that corresponds to `draft=mtp`. It is not the same command as `lms load --speculative-draft-mtp`. The sidecar list implies MTP may be an extra file, while Hearth's tsv comment says the LM Studio MTP flag uses the same weights ([config/roles.tsv](config/roles.tsv)). Treat those as different until a bench says otherwise.

### Gaps

- No fetched sentence states that an INI section `[local-big]` is the string clients must send as `"model"`. The preset and routing sections imply it. Unconfirmed.
- No fetched sentence states that `--spec-type draft-mtp` works with no extra GGUF. The README lists both a draft-model path and an `mtp` sidecar.
- No fetched sentence states what router mode returns for an unknown model name (404 versus autoload versus error).
- Whether `--cors-origins` can make the CORS header absent, which is what `healthcheck.sh` looks for ([docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)), was not tested.
- The README blob is `0ec4027`. The newest release on the index is pre-release b12023 from 2026-10-31. This note does not claim those flags are unchanged in b12023.
- A third-party write-up says a chat server returns 501 for embeddings unless started with `--embeddings`, and that an embedding server does not chat ([jacar.es](https://jacar.es/en/llama-server-openai-compatible-api-docker/)). That agrees with the official flag text. It is not the project's own docs, and its claim that `dimensions` is ignored was not checked against the README.

## Does LM Studio run on Linux and Windows?

### Takeaway

Yes. LM Studio's own download and requirements pages list macOS, Windows, and Linux, and the Linux and Windows downloads offered on 2026-11-01 are version 0.4.28, the same version number Hearth runs on the Mac. MLX is Apple Silicon only, so the current `local-big` weights file cannot be the Linux or Windows load. The `lms` CLI, including `--identifier`, is documented for Mac, Linux, and Windows.

### Cited Findings

- Download page schema lists `operatingSystem` as macOS, Windows, and Linux. The page offers "Download LM Studio for Windows 0.4.28". The Linux URL offers an AppImage and a `.deb`, both labeled 0.4.28. Headless `llmster` install is `curl -fsSL https://lmstudio.ai/install.sh | bash` for Mac/Linux and `irm https://lmstudio.ai/install.ps1 | iex` for Windows. [lmstudio.ai/download](https://lmstudio.ai/download), [Linux download](https://lmstudio.ai/download?os=linux).
- Requirements, fetched in full: Apple Silicon only (M1–M4), macOS 14 or newer, Intel Macs unsupported. Windows x64 and ARM (Snapdragon X Elite); x64 needs AVX2; 16 GB RAM and 4 GB VRAM recommended. Linux x64 and ARM64; distributed as an AppImage; "Ubuntu 20.04 or newer is required"; "Ubuntu versions newer than 22 are not well tested"; x64 ships AVX2. The page does not date that Ubuntu sentence. [System requirements](https://lmstudio.ai/docs/app/system-requirements).
- App docs: "LM Studio is available for macOS, Windows, and Linux." It runs GGUF via llama.cpp on Mac, Windows, and Linux. "On Apple Silicon Macs, LM Studio also supports running LLMs using Apple's MLX." [Welcome](https://lmstudio.ai/docs/app).
- `lms` ships with the app and with llmster and talks to either. `lms server start` listens on `http://localhost:1234` in the documented example. Bootstrap is `~/.lmstudio/bin/lms bootstrap` on Mac/Linux and `%USERPROFILE%/.lmstudio/bin/lms.exe bootstrap` on Windows. "You need to run LM Studio at least once before you can use `lms`." If the app is not running, an `lms` command starts it. [LM Studio, llmster, and lms](https://lmstudio.ai/docs/app/basics/lmstudio-vs-llmster-vs-lms), [lms announcement](https://lmstudio.ai/blog/lms).
- llmster is the headless daemon for a Linux server, a GPU box without a display, or CI, and it does not require the GUI app. [LM Studio, llmster, and lms](https://lmstudio.ai/docs/app/basics/lmstudio-vs-llmster-vs-lms).
- `lms load` documents `--identifier`, `--context-length`, `--gpu` (`off`, `max`, or 0–1), `--ttl`, and `--estimate-only`. The identifier is what API clients send as `model`. [lms load](https://lmstudio.ai/docs/cli/local-models/load). The CLI source also has `--parallel` ("Maximum number of predictions the model can run at a given time"). [lms load.ts](https://github.com/lmstudio-ai/lms/blob/efce9967/src/subcommands/load.ts).
- Server settings, same page Hearth already cites: port, Require Authentication (`Authorization` header), Serve on Local Network, Enable CORS, Just in Time Model Loading, and auto-unload of JIT models. [Server settings](https://lmstudio.ai/docs/developer/core/server/settings).
- OpenAI-compatible embeddings are `POST` on the local server, base URL `http://localhost:1234/v1`, with a `model` argument. [Embeddings](https://lmstudio.ai/docs/developer/openai-compat/embeddings). Native embeddings example uses `http://localhost:1234/api/v0/embeddings` and `Authorization: Bearer`. [REST API v0](https://lmstudio.ai/docs/developer/rest/endpoints).
- Speculative decoding in the current app docs is a second, smaller draft model that shares the main model's vocabulary, chosen in the chat sidebar. The 0.3.10 blog says this exists on both the llama.cpp and MLX engines, and that a request may pass `draft_model`. [Speculative decoding](https://lmstudio.ai/docs/app/advanced/speculative-decoding), [0.3.10 blog](https://lmstudio.ai/blog/lmstudio-v0.3.10).
- Hearth's Mac process is the LM Studio app 0.4.28, not headless llmster. The app and llmster cannot share `~/.lmstudio`. The load line is `lms load --identifier <role> -c <ctx> --gpu max --parallel <slots>`, and `draft=mtp` adds `--speculative-draft-mtp`. Saved bind once drifted to `0.0.0.0` with CORS on; boot resets `--bind 127.0.0.1`. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), [config/roles.tsv](config/roles.tsv).

### Inferences

- The Mac path does not need a new server product to exist on Linux or Windows. The same app family already speaks the contract: port 1234, role identifier, token, JIT switch, parallel predictions, embeddings, loopback versus LAN.
- **Judgment:** a Linux or Windows LM Studio still cannot load `lmstudio-community/Qwen3.6-35B-A3B-MLX-4bit`. Those machines need a GGUF (llama.cpp runtime) recorded as their own `model_key` and `weights` in `roles.tsv` and `docs/MODELS.md`, then benched. The role name clients send stays `local-big`.
- **Judgment:** on a Linux box with no display, llmster is the documented daemon. Hearth's Mac choice of "app, not llmster" does not have to be copied, and the two still must not both own `~/.lmstudio`.
- **Judgment:** do not treat "LM Studio is installed" as "the port is local-only". The developer nav lists Using LM Link, and this research did not read that page. A linked remote model on `:1234` would break the privacy rule in [docs/ROUTING.md](docs/ROUTING.md).

### Gaps

- Public `lms load` docs fetched today do not list `--parallel` or `--speculative-draft-mtp`. `--parallel` is in the CLI source at commit `efce9967`. `--speculative-draft-mtp` was not found in the fetched docs or that source excerpt. Hearth's history says the Mac CLI accepted the MTP flag ([docs/HISTORY.md](docs/HISTORY.md)). Whether the Linux and Windows `lms` binaries accept it was not checked.
- The requirements page still says Ubuntu newer than 22.04 is poorly tested, while the download page ships 0.4.28. Which Ubuntu releases 0.4.28 actually supports was not found.
- Server-settings docs describe switches, not the `lms server start --bind` flag Hearth uses. Cross-platform behaviour of that flag was not re-fetched.
- LM Link, and whether a linked model is served on the same port as local models, was not fetched.
- No page fetched here says the Linux or Windows build can load an MLX file. The app docs limit MLX to Apple Silicon.

## Ollama, vLLM, and other OpenAI-compatible servers

### Takeaway

Ollama is the other server with first-party macOS, Linux, and Windows builds and an OpenAI subset on loopback. It does not enforce a local API key, it can serve Ollama cloud models through that same local port unless cloud is switched off, parallel defaults to 1, and idle models unload after 5 minutes. vLLM's OpenAI server is real on Linux and is not a native Windows server; one process serves one model, and its API key does not cover every route. Neither is a drop-in for the Hearth contract. This note did not review LocalAI, koboldcpp, SGLang, or Hugging Face TGI.

### Cited Findings

- Ollama's local OpenAI base URL is `http://localhost:11434/v1`. The OpenAI client requires an API key string and the local server ignores it. Documented local routes include `/v1/chat/completions`, `/v1/completions`, `/v1/models`, and `/v1/embeddings` (`model`, `input`, `encoding format`, `dimensions`, `user`). Chat features listed on the HTML docs include streaming, JSON mode, tools, and vision. [OpenAI compatibility](https://docs.ollama.com/api/openai-compatibility), [API introduction](https://docs.ollama.com/api/introduction).
- The same HTML page lists `tool_choice`, `logit_bias`, `user`, and `n` under supported chat fields, and lists logprobs as a supported feature. The GitHub mdx and `openai-compatibility.md` still mark logprobs, `tool_choice`, `logit_bias`, `user`, and `n` unchecked. [OpenAI compatibility](https://docs.ollama.com/api/openai-compatibility); contradicted by [openai-compatibility.mdx](https://github.com/ollama/ollama/blob/main/docs/api/openai-compatibility.mdx) and [openai-compatibility.md](https://docs.ollama.com/api/openai-compatibility.md).
- Local API at `http://localhost:11434` does not require authentication. An API key is for `https://ollama.com`. Signing in lets the local server use cloud models such as `gemma4:cloud`. Prompts for cloud-hosted models are processed by Ollama. Cloud can be disabled with `disable_ollama_cloud` in `~/.ollama/server.json` or `OLLAMA_NO_CLOUD=1`. [Authentication](https://docs.ollama.com/api/authentication), [FAQ](https://docs.ollama.com/faq), [OpenAI compatibility](https://docs.ollama.com/api/openai-compatibility).
- Default bind is `127.0.0.1:11434`. `OLLAMA_HOST` changes it, including examples that set `0.0.0.0:11434`. CORS allows origins `127.0.0.1` and `0.0.0.0` by default; more origins go in `OLLAMA_ORIGINS`. Install path covers macOS, Linux (systemd), and Windows. [FAQ](https://docs.ollama.com/faq).
- Default context is 4096 (`OLLAMA_CONTEXT_LENGTH` or per-request `num_ctx`). `OLLAMA_NUM_PARALLEL` defaults to 1; RAM scales with parallel times context. `OLLAMA_MAX_LOADED_MODELS` defaults to 3 times the GPU count, or 3 for CPU. If a new model does not fit, Ollama queues and unloads idle models. `keep_alive` defaults to 5 minutes; a negative value keeps a model loaded. Windows Radeon defaults to one loaded model. [FAQ](https://docs.ollama.com/faq).
- There is no documented load identifier separate from the Ollama model name. The OpenAI `model` field is that name. [OpenAI compatibility](https://docs.ollama.com/api/openai-compatibility).
- Hearth removed Ollama on 2026-10-31 after measuring one slot, eviction when a second model loaded, MLX stalls, and a gateway hop. ADR 0016's cited causes include `OLLAMA_NUM_PARALLEL=1` and `MAX_LOADED_MODELS=1`. [docs/decisions/0016-lmstudio-direct.md](docs/decisions/0016-lmstudio-direct.md). The FAQ fetched today still says parallel defaults to 1. The FAQ's default max loaded models is 3 per GPU, not 1, so the "1" in that ADR was configuration, not the current documented default.
- vLLM serves OpenAI completions, chat, responses, and embeddings (embeddings only on an embedding model) and documents `--api-key` / `VLLM_API_KEY`. That key authenticates `/v1`, `/v2`, and `/inference` only. `/invocations` is named as an unauthenticated route with the same inference capability. The docs say not to rely on `--api-key` alone. [OpenAI-compatible server](https://docs.vllm.ai/en/latest/serving/online_serving/openai_compatible_server/).
- Quickstart: one server, one model, default `http://localhost:8000`, `--host` and `--port`. The FAQ says serving multiple models on one OpenAI port is not supported; run one process per model and route outside. [Quickstart](https://docs.vllm.ai/en/stable/getting_started/quickstart/), [FAQ](https://docs.vllm.ai/en/stable/usage/faq/).
- Official GPU install: "OS: Linux". "vLLM does not support Windows natively." The documented Windows path is WSL, plus a pointer to the community fork `SystemPanic/vllm-windows`. [GPU install](https://docs.vllm.ai/en/latest/getting_started/installation/gpu/). That fork's release v0.32.0 (2026-10-22) is a third-party Windows wheel for Python 3.12, CUDA 13, and PyTorch 2.11, not a vLLM project release. [SystemPanic/vllm-windows releases](https://github.com/SystemPanic/vllm-windows/releases).
- Apple Silicon GPU serving is vLLM-Metal, described as a community plugin that uses MLX weights and an OpenAI server. The sample client uses `api_key="dummy"` and says no auth is required. [GPU install](https://docs.vllm.ai/en/stable/getting_started/installation/gpu/).
- A production-stack router (`vllm-router`) can front several engines and defaults `--host` to `0.0.0.0`. [Router CLI](https://docs.vllm.ai/projects/production-stack/en/latest/user_manual/router/cmd.html).

### Inferences

- **Judgment:** do not put Ollama back on `:1234`. The ignored local key fails the 401 check. Cloud-through-localhost fails the rule that the local port cannot leave the host, unless `OLLAMA_NO_CLOUD=1` is set and kept set. Parallel still defaults to the setting ADR 0016 blamed for stalls. The 5-minute unload is the TTL Hearth refused. Fixing all of that still leaves no Bearer token unless a proxy is added, and that proxy is the gateway ADR 0016 deleted.
- **Judgment:** vLLM matches none of the "boring, all three OSes, two resident roles, one authenticated loopback" tests. An external router in front of two vLLM processes recreates a gateway and, on the production-stack defaults, binds all interfaces.
- Role identifiers: Ollama can only match them if the model is created under the role name. vLLM uses the Hugging Face id it was started with. llama-server can alias. LM Studio has `--identifier`. Only the last two keep the concrete name inside `roles.tsv` without renaming the model artifact.

### Gaps

- No Ollama page fetched here documents speculative decoding or MTP.
- No Ollama page fetched here says what status an unknown model name returns.
- vLLM speculative-decoding flags were not fetched.
- LocalAI, koboldcpp, SGLang, and Hugging Face TGI were not fetched. This note does not rank them.
- The Ollama docs conflict on `tool_choice` and logprobs (HTML versus mdx). Which build Hearth would actually get was not resolved.

## What would have to change

### Takeaway

**Judgment:** keep `roles.tsv` and the Mac LM Studio path. On Linux and Windows, prefer LM Studio itself (llmster or the app) when a GUI-or-daemon install is acceptable, because the client contract is already that product's. If the new machines should not take an LM Studio dependency, add one new backend value, `llama-server`, and point only those machines' load and health scripts at it. Do not add a cloud model, an Ollama cloud sign-in, or a second gateway on the local port.

### Cited Findings

- Backend is already a column. Scripts load only `lmstudio` rows, via `lms`, and refuse a cloud backend on that server except an explicit `gemini` row. [config/roles.tsv](config/roles.tsv), [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), [docs/ROUTING.md](docs/ROUTING.md), [docs/decisions/0016-lmstudio-direct.md](docs/decisions/0016-lmstudio-direct.md).
- `scripts/lms-load.sh` maps `slots > 1` to `--parallel` and `draft=mtp` to `--speculative-draft-mtp`. It unloads anything not in the tsv and does not pass `--ttl`. [scripts/lms-load.sh](scripts/lms-load.sh).
- Containment is `sandbox-exec`. `scripts/sandbox-probe.sh` fails if `sandbox-exec` is missing. ADR 0007 records that Apple has deprecated it and that the probe must be re-run after macOS updates. Egress allowed to sandboxed agents is `127.0.0.1:1234` only. [scripts/sandboxed.sh](scripts/sandboxed.sh), [scripts/sandbox-probe.sh](scripts/sandbox-probe.sh), [docs/decisions/0007-agent-containment.md](docs/decisions/0007-agent-containment.md).
- Open WebUI is started with Podman (`scripts/webui.sh`, `podman machine`). The architecture diagram shows the container reaching LM Studio via `host.containers.internal`. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), [scripts/webui.sh](scripts/webui.sh).
- Login supervision is launchd `com.hearth.boot`, which opens the Mac app, restarts the server with `--bind 127.0.0.1`, loads `roles.tsv`, and starts Podman. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
- Weight pins hash paths under `~/.lmstudio/models`. [config/roles.tsv](config/roles.tsv).
- Client-visible port, token, and role names are what Zed, aider, the laptop SSH tunnel, and the sandbox already use. Changing them means touching every client. Binding the new server to `127.0.0.1:1234` with the same Bearer token and the same role strings avoids that. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

### Inferences

**Judgment. Shape to build, not a claim that it has been tried.**

Leave every Mac script on `backend=lmstudio`. Add `llama-server` as a backend value used only on Linux and Windows rows (or a second tsv those hosts read). Columns stay. `model_key` and `weights` on those rows are GGUF paths, still written only in `roles.tsv` and `docs/MODELS.md`. `ctx`, `slots`, and `draft` keep their meanings. `cloud-cheap` stays `gemini` and is still not loaded into the local server.

A Linux/Windows load script, sibling to `lms-load.sh`, would:

1. Start one `llama-server` with `--host 127.0.0.1 --port 1234`, `--api-key` from the same mode-600 env file the aliases already use, and `--no-models-autoload`.
2. Write a preset INI from the tsv. One section per local role. `load-on-startup` true. `parallel` from `slots`. Context from the per-slot flag in the Gaps of the first section, not from a guessed `-c`. `draft=mtp` becomes `--spec-type draft-mtp` only after that flag is confirmed against the chosen GGUF. The embedding row sets `--embeddings`. The chat row does not.
3. Refuse to start if any local row's weights are MLX, or if any row points at a remote URL or a `gemini` model.
4. Re-read the router `/models` list and fail unless exactly the tsv roles are loaded. That replaces `lms ps`.

Mac clients, the SSH tunnel, and the sandbox allow-list stay on `127.0.0.1:1234`. They do not learn a new port or a new product name.

Hard parts, named:

- **No `lms`.** `lms-load.sh`, `lms server start`, `lms ps`, `lms log stream`, and `pin-digests.sh` paths under `~/.lmstudio/models` are LM Studio. The llama-server host needs its own load, status, and hash commands. The tsv `weights` column is the right place for the GGUF path. Do not put the model name in a shell alias.
- **Sandbox profile is macOS `sandbox-exec`.** It will not run on Linux or Windows. `sandbox-probe.sh` already exits if the binary is gone. A Linux equivalent has to allow egress only to `127.0.0.1:1234` and still allow local reads, matching ADR 0007. Windows has no `sandbox-exec`. This is new containment work, not a flag on the inference server.
- **Podman versus Docker.** `webui.sh` talks to a Podman machine and the diagram uses `host.containers.internal`. That is the Mac VM path. Linux can run Podman or Docker on the host, where the host gateway address is different. Windows is Docker Desktop or a Podman machine, not the Mac machine. The container must still reach only the host's loopback server and must not gain a cloud API key.
- **Supervision.** `com.hearth.boot` is launchd. Linux is a systemd unit. Windows is either the LM Studio / llmster startup install or a Task Scheduler entry that runs `llama-server.exe`. Hearth's boot script also exists because LM Studio's saved settings drifted to `0.0.0.0` and CORS on. llama-server has the same footgun if someone copies the Docker sample (`--host 0.0.0.0`).
- **One port, two models.** Chat and `--embeddings` are different llama-server modes. The router inside `llama-server` is what keeps a single port without putting LiteLLM back. An nginx or vLLM router in front would be a gateway again, and the vLLM one defaults to `0.0.0.0`.
- **Context times slots.** Copying `131072` and `3` straight into `-c` and `-np` is not justified by the README. The only sentence that states a per-slot size is `--kv-unified-per-slot`. Getting this wrong either OOMs or silently shortens context. Re-bench. Rule 5 in [AGENTS.md](AGENTS.md) already requires that before a role's weights change.
- **CORS and the unknown-model check.** llama-server's CORS default is `*`. Hearth's healthcheck wants no CORS. Router mode routes by name; single-model mode ignores the name. Healthcheck's "unknown model does not load, and a typo must not be silent" needs expected responses written down for the new server. They will not match LM Studio's current "unknown name is answered by the loaded LLM" behaviour.
- **MTP.** The Mac flag is `lms`-specific and the project itself notes that `lms ps` cannot show the drafter ([docs/HISTORY.md](docs/HISTORY.md)). A GGUF MTP sidecar is a different mechanism until measured.
- **Privacy.** Nothing in the new preset may be an HTTP model, an Ollama `:cloud` tag, or an LM Link host. `OLLAMA_NO_CLOUD` is irrelevant if Ollama is not installed. The structural rule stays: the process on `:1234` has no cloud credential and no remote backend.

**Judgment, if LM Studio is used on Linux and Windows instead of llama-server.** The client contract barely changes. What still changes: GGUF rows in `roles.tsv`, `lms.exe` versus `lms`, llmster instead of the Mac app on headless hosts, launchd versus systemd or the Windows llmster startup script, the sandbox, and Podman networking. Confirm `--parallel` and `--speculative-draft-mtp` on that OS's `lms` before reusing `lms-load.sh` unchanged. Read LM Link and turn it off. The Ubuntu-newer-than-22 warning on the requirements page is unresolved.

**Judgment:** Ollama and vLLM are the wrong backends for this contract. Reasons are in the previous section. Do not put either on `:1234`.

### Gaps

- `host.containers.internal` from a Linux Podman container, and from Docker Desktop on Windows, was not fetched. The Mac diagram uses it. Assume it has to be re-checked, not reused.
- A Linux or Windows sandbox profile that matches ADR 0007 was not designed here.
- Whether `lms server start --bind 127.0.0.1` exists on the Linux and Windows CLIs was not fetched.
- No measurement on a non-Mac machine was done. RAM numbers in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) are the Mac's unified memory and do not transfer to a discrete GPU.
