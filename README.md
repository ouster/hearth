# Hearth

Local-first LLM serving for a single developer (or a small LAN).
Inference that still works when vendors get expensive, overloaded, or unavailable.

LM Studio serves local models on `127.0.0.1:1234` with a token required. The
LM Studio app owns the server (D6, changed 2026-10-31 from headless `llmster`). Cloud (Gemini) is reached by each tool directly with its own
key, never through the local server — so nothing sent to `:1234` can leave the
machine. ADR 0016 replaced the earlier LiteLLM + Ollama gateway; what was tried
before is in [`docs/HISTORY.md`](docs/HISTORY.md).

## Why

Model names change every few months. Hardcoding a model tag into shell
aliases, IDE settings, and laptop configs means every upgrade is a scavenger
hunt. This stack addresses **roles** instead:

```
local-main   cloud-cheap
```

Each local role is an LM Studio `--identifier`, so clients ask for
`local-main`, never a model. Concrete models live in exactly two files —
[`config/roles.tsv`](config/roles.tsv) and [`docs/MODELS.md`](docs/MODELS.md).

```mermaid
flowchart LR
    subgraph host["Host"]
        zed["Zed agent"]
        aider["aider / ask-*"]
        webui["Open WebUI :3000"]
        sbx["sandboxed.sh agents<br/>egress: 127.0.0.1:1234 only"]
        lms["LM Studio 127.0.0.1:1234<br/>local-main x3 slots<br/>token required"]
    end
    laptop["Laptop<br/>own token, tunnel-only key"]
    cloud["Gemini<br/>tool's own key"]
    searx["SearXNG<br/>opt-in search"]

    zed --> lms
    aider --> lms
    webui --> lms
    sbx --> lms
    laptop -->|"SSH tunnel"| lms
    aider -.->|"ask-cloud only"| cloud
    webui -.->|"opt-in per message"| searx

    classDef localCls fill:#E1F5EE,stroke:#0F6E56,color:#085041
    classDef leaveCls fill:#FAEEDA,stroke:#854F0B,color:#633806
    class lms localCls
    class cloud,searx leaveCls
```

## Three guarantees

1. **Privacy is structural.** LM Studio holds only local models, so anything
   sent to `:1234` stays on the host by construction. Cloud needs a separate
   provider key in the calling tool; only `ask-cloud` has one. Sandboxed agents
   can reach `127.0.0.1:1234` and nothing else (`scripts/sandbox-probe.sh`).
2. **No silent route changes.** There is no router, so there is no fallback to
   leak through. If `local-main` is down, requests fail.
3. **Nothing is claimed without being measured.** Role and serving changes get
   an ADR and a bench (`bench/results/`, committed).

## Requirements

- macOS on Apple Silicon (the reference host is 64 GB)
- The LM Studio app (0.4.28 here) — it owns the server and is where auth and
  tokens are set; there is no CLI for either (lmstudio-ai/lms#489)
- The `lms` CLI at `~/.lmstudio/bin/lms` (installed by the app, or by the
  llmster installer with `--no-modify-path`)
- [Podman](https://podman.io) for Open WebUI / SearXNG

## Quick start

```bash
git clone <this-repo> hearth && cd hearth

# 1. Server and models (see docs/RUNBOOK.md for the settings to set in the app)
#    LM Studio app open, "Enable Local LLM Service (headless)" on
~/.lmstudio/bin/lms server start --bind 127.0.0.1 -p 1234
scripts/lms-load.sh                 # loads exactly what config/roles.tsv lists

# 2. Token — created in the LM Studio app, stored mode 600
#    ~/.config/hearth/env:  LMSTUDIO_HOST_TOKEN=...

# 3. Shell aliases
echo "source $PWD/scripts/aliases.zsh" >> ~/.zshrc
```

Ops detail: [`docs/RUNBOOK.md`](docs/RUNBOOK.md). Architecture:
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md). Migration status:
[`docs/MIGRATION-LMSTUDIO.md`](docs/MIGRATION-LMSTUDIO.md).

## Usage

### On the host

```bash
# Local models — all mean local-main (D1)
ask                # aider with openai/local-main
ask-big            # same
ask-arch           # aider architect mode (two local-main sides)
ask-deep           # aider on local-deep: slow, careful, loaded for the session only (ADR 0020)
ask-cloud          # Gemini via GOOGLE_API_KEY — the only alias that leaves the host

# Server management
ai-load            # scripts/lms-load.sh — load roles.tsv, report drift
ai-loaded          # lms ps — list loaded models
ai-restart         # stop and start the server on 127.0.0.1:1234
ai-log             # lms log stream
ai-status          # scripts/status.sh
ai-health          # scripts/healthcheck.sh
ai-boot            # scripts/boot.sh
```

### On a laptop

Source `~/.hearth-client.sh` (set by `scripts/client-setup.sh`): run
`ai-tunnel` first to open the SSH tunnel, then any of these — they all go
through the tunnel to the host's LM Studio on `:1234`.

```bash
# Tunnel management
ai-tunnel          # open the SSH tunnel (needed once)
ai-tunnel-stop     # close the tunnel
ai-ping            # check tunnel + server health (up / DOWN / BAD TOKEN)
ai-models          # list models available through the tunnel

# Asking
ai-ask "question"  # one-shot question without aider
ask                # local-main. ask-big / ask-local / ask-chat / ask-fast are the same
ask-arch           # aider architect mode, local-main on both sides
ask-deep           # aider on local-deep — only while the host has it loaded
ask-cloud          # Gemini via THIS machine's own key — the only cloud alias

# Open WebUI through the tunnel
ai-webui           # open host's Open WebUI (http://127.0.0.1:3000)
```

Editors (aider + Zed): [`docs/IDES.md`](docs/IDES.md).

## Laptops

SSH tunnel only — the server never listens on the LAN. Each laptop gets its
own LM Studio token and an SSH key that can forward to `:1234` / `:3000` / `:8888` and
nothing else. `scripts/client-setup.sh <laptop-name>` prints the steps;
details in [`docs/LAPTOP.md`](docs/LAPTOP.md). Never port-forward `:22`,
`:1234`, `:3000` or `:8888`.

## Using an AI assistant with this repo

Claude Code reads `CLAUDE.md`; Cursor reads `AGENTS.md` (a symlink to it) and
`CLAUDE.md`. Both pick the rules up from the repo root with no setup. The top
of `CLAUDE.md` tells the assistant which machine it is on, because the host and
a laptop get very different instructions.

### Setting up a laptop

On the laptop, clone the repo (it needs read access to the GitHub remote),
open it in Claude Code or Cursor, and paste:

> I'm on a laptop, setting it up to use the hearth host. Read the "Which
> machine are you on?" block in CLAUDE.md, then follow docs/LAPTOP.md →
> AI-assisted setup step by step. Never read, print or copy my key or token
> files, and never ask me to paste a secret into this chat — tell me the
> command and I'll run it myself. Stop whenever a step has to happen on the
> host.

The assistant does the plumbing (SSH key, `~/.ssh/config`, client script,
shell rc) and the checks; you type the secrets and do the two host-side steps.
Cursor can help with setup but **cannot use hearth as a model provider** — its
servers make the model calls, so they would need the host exposed publicly.
Use Zed or aider for `local-main` on the laptop.

### Changing this repo

Run it on the host, and start with:

> Read CLAUDE.md, and docs/ROUTING.md if this touches routing. Plan first and
> wait for my approval before changing anything. Before saying it's done, run
> scripts/preflight.sh (and scripts/healthcheck.sh if you touched the server)
> and show me the result: exit 0 pass, 1 real problem, 2 could not run.

The rules it must keep are in `CLAUDE.md`. The ones most often broken: model
names only in `config/roles.tsv` and `docs/MODELS.md`; nothing against the
removed gateway (`:4000`, `:11434`, LiteLLM); never read
`~/.config/hearth/env`; bash 3.2; Mermaid only.

## Security notes

- Web search via SearXNG is opt-in per message. The **search query leaves**
  even when the model stays local. See `docs/ROUTING.md`.
- Zed's `auslaw` MCP tools send queries to AustLII; they are enabled only in
  Zed's Research profile. See `docs/MCP.md`.
- Prompt-injection / agent containment: `docs/THREAT-MODEL.md`, ADR 0007.

## Layout

```
CLAUDE.md / AGENTS.md   rules for coding agents in this repo
config/roles.tsv        role → LM Studio model key, context, slots
docs/                   architecture, routing, models, runbook, history, ADRs
scripts/                lms-load, benches, sandbox, client setup, …
client/                 laptop shims (bash/zsh + PowerShell), SSH-tunnel based
bench/tasks/            fixed prompts for comparing models
bench/results/          every bench run, committed
```

## License

MIT — see [LICENSE](LICENSE).
