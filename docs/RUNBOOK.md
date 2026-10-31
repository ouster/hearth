# Runbook

Start, stop, diagnose. The LM Studio app serving `127.0.0.1:1234`, ADR 0016
(D6: the app, not headless `llmster`, since 2026-10-31). `lms` lives at `~/.lmstudio/bin/lms` (installed with
`--no-modify-path`; the aliases call it by full path as `$HEARTH_LMS`).

## Layout of the running system

| Piece | Where | Notes |
|---|---|---|
| LM Studio app | `/Applications/LM Studio.app` | owns the daemon and `~/.lmstudio`. "Enable Local LLM Service (headless)" on. Never run llmster as well |
| Server | `127.0.0.1:1234` | `lms server start --bind 127.0.0.1 -p 1234` |
| Roles | `config/roles.tsv` → `scripts/lms-load.sh` | `local-big` 64K × 3 parallel, `local-embed` |
| Token | `~/.config/hearth/env`, mode 600 | `LMSTUDIO_HOST_TOKEN`, created in the app |
| Server settings | `~/.lmstudio/.internal/http-server-config.json` | edited through the app; auth/tokens are stored elsewhere |
| Remote Login (sshd) | `:22` | laptops' tunnel; their keys are `restrict`ed to forwarding `:1234`/`:3000` |
| Open WebUI | Podman, `127.0.0.1:3000` | `scripts/webui.sh` |
| SearXNG | Podman, `:8888` | `scripts/searxng.sh` |

Removed 2026-10-31: Ollama, LiteLLM, Postgres, Rapid-MLX, llmster and their
launchd agents. Ports 4000, 5433 and 11434 should be free.

## First-time setup

1. Read, then run, the installer: `curl -fsSL https://lmstudio.ai/install.sh
   -o install.sh && less install.sh && sh install.sh --no-modify-path`.
2. Runtimes: `lms runtime get mlx-llm -y` and `lms runtime get llama.cpp -y`
   (the embedding model is GGUF).
3. Weights: `lms get <hugging face URL> -y` for each row in `config/roles.tsv`
   (exact sources in `docs/MODELS.md`). A bare staff-pick name with `-y` can
   choose a different quantisation. If `lms get` dies with "WebSocket
   connection closed", download the file from Hugging Face into
   `~/.lmstudio/models/<publisher>/<repo>/` and check its sha256.
4. **Server settings, once, in the LM Studio app** — llmster has no CLI for
   auth or tokens (lmstudio-ai/lms#489). Mode switch at the bottom → Developer;
   then the **Developer tab** in the left sidebar (not Settings) → Server
   Settings:

   | Setting | Value |
   |---|---|
   | Port | 1234 |
   | Require Authentication | **on** |
   | Serve on Local Network | off — laptops use an SSH tunnel |
   | Enable CORS | off |
   | Allow per-request MCPs | off |
   | Allow calling servers from mcp.json | off |
   | Just-in-Time Model Loading | off |
   | Log sensitive data | off — it writes prompts to the server logs |

   Manage Tokens → Create Token `host`. Store it without echoing:
   ```bash
   mkdir -p ~/.config/hearth && umask 077 && \
     printf 'LMSTUDIO_HOST_TOKEN=%s\n' "$(pbpaste)" >> ~/.config/hearth/env && \
     chmod 600 ~/.config/hearth/env && pbcopy </dev/null
   ```
   In Settings → Developer turn **"Enable Local LLM Service (headless)" on**.
   If llmster was installed, stop it first (`lms daemon down` while the app is
   closed) — the two cannot share `~/.lmstudio`.
5. Start and load (app open):
   ```bash
   lms server start --bind 127.0.0.1 -p 1234
   scripts/lms-load.sh
   ```
6. Prove auth holds — a positive control first:
   ```bash
   . ~/.config/hearth/env
   curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $LMSTUDIO_HOST_TOKEN" http://127.0.0.1:1234/v1/models   # 200
   curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:1234/v1/models                                                    # 401
   ```
7. `echo "source $PWD/scripts/aliases.zsh" >> ~/.zshrc`

## Surviving a reboot

`scripts/install-autostart.sh --apply` installs `com.hearth.boot`, a launchd
agent that runs `scripts/boot.sh` once at login:

1. opens LM Studio hidden (stops llmster first if it grabbed the daemon);
2. **restarts the server with an explicit `--bind 127.0.0.1`** — the app's
   saved settings were found at `0.0.0.0` + CORS on (2026-10-31), and
   `lms server start --bind` rewrites them;
3. checks a no-token request gets 401;
4. runs `scripts/lms-load.sh`;
5. starts the Podman VM, SearXNG and Open WebUI.

The plist sets `AbandonProcessGroup`: without it launchd kills every process
`boot.sh` leaves behind when it exits — which is the Podman VM, so WebUI and
SearXNG died minutes after login (seen and reproduced 2026-10-31).

Log: `~/Library/Logs/hearth-boot.log`. Check it with
`scripts/install-autostart.sh --check`. By hand: `scripts/boot.sh`.

### Sleep

A sleeping host means every laptop loses inference. These are printed, not
run, because silently changing when your machine sleeps is not something a
script should do:

```bash
sudo pmset -c sleep 0        # never sleep on AC
sudo pmset -c disksleep 0
sudo pmset -a womp 1         # wake on network access
sudo pmset -c displaysleep 10   # displays can still sleep, that is free
```

## Everyday

```bash
ai-status                      # one glance: app, server, bind, roles, containers, autostart
ai-health                      # scripts/healthcheck.sh — the real verdict (exit 0/1/2)
scripts/preflight.sh           # static checks: roles.tsv, rule 1, saved settings, secrets, drift
ai-loaded                      # lms ps — identifiers, context, parallel
scripts/lms-load.sh --check    # drift against roles.tsv; changes nothing
scripts/lms-load.sh            # fix drift
ai-restart                     # server stop + start on 127.0.0.1:1234
ai-log                         # lms log stream — live requests
lms server status
lms daemon status
```

Footprint of the model worker (the number that matters against the ~48 GB
GPU ceiling — RSS understates it):

```bash
for p in $(pgrep -f '\.lmstudio/|LM Studio'); do footprint -p $p | awk '/Footprint:/'; done
```

## Chat UI and visibility

```bash
scripts/webui.sh up            # local only — there is no cloud mode
scripts/webui.sh up --lan      # reachable from other machines (see below)
scripts/webui.sh down
```

The container reaches the host's `127.0.0.1:1234` via
`host.containers.internal` with "serve on local network" off. `webui.sh up`
refuses to start unless the host token gets a 200.

**The connection lives in WebUI's database.** Environment variables only seed
a fresh database, so after the cutover the saved OpenAI connection may still
point at `:4000`. If the model list is empty: Admin Panel → Settings →
Connections → OpenAI API, URL `http://host.containers.internal:1234/v1`, key
= the host token, and delete any `:4000` / `:11434` entry. Default and task
model are `local-big`.

### Using the chat UI from a laptop

Open WebUI is a **web app** — nothing to install on the laptop. **Preferred:
SSH tunnel**, which keeps the UI localhost-only:

```bash
ssh -N -L 3000:127.0.0.1:3000 USER@HOST     # then http://127.0.0.1:3000
```

**Alternative:** `scripts/webui.sh up --lan`, then `http://<LAN-IP>:3000`. It
has its own login, but it is plain HTTP and another authenticated surface.
Either way, **do not port-forward :3000 to the internet.**

### Do not enable tools in Open WebUI without thinking

Web search feeds arbitrary attacker-controlled page text straight into the
model's context. That is tolerable **only** because the chat model has no tools:
it can mislead you convincingly, but it cannot act.

Enabling tools, functions, or code execution turns this into the highest-risk
surface in the stack. Open WebUI stores these settings in its database, where
they override the environment and survive container recreation. Treat
enabling them as an ADR-worthy decision. See `docs/THREAT-MODEL.md` §3.

### Web search: the env vars are not enough

Same database-wins trap. Enable it where it counts:

```
Admin Panel -> Settings -> Web Search -> Enable Web Search
  Engine:    searxng
  Query URL: http://host.containers.internal:8888/search?q=<query>
```

The toggle then appears per message. If it vanishes, sign out and back in.

## Running agents contained

```bash
scripts/sandboxed.sh aider              # confine to $PWD
scripts/sandboxed.sh --dir ~/dev/x aider
scripts/sandboxed.sh --print-profile    # audit the profile
scripts/sandbox-probe.sh                # re-verify the controls still hold
```

Inside a sandboxed session the agent can reach **only** `127.0.0.1:1234`.
`pip install`, `npm install`, `git push` and any `curl` fail by design.

**Re-run `sandbox-probe.sh` after every macOS update.** `sandbox-exec` is
deprecated and Apple can change or remove it without notice.

If an agent crashes on a permission error naming a path outside the repo, that
is the sandbox working. Add a preset in `sandboxed.sh` or widen once with
`--also-write PATH`; every widening is printed at startup.

It does **not** protect against an agent reading your keys or corrupting the
repo it was invited into. Commit first; `git diff` before accepting.

## Diagnosing

| Symptom | Check | Fix |
|---|---|---|
| Every client 401s | `curl` with the host token | token wrong or missing in `~/.config/hearth/env`; Zed keeps its own copy in the keychain |
| Wrong model answers | `scripts/lms-load.sh --check` | LM Studio answers an **unknown model name with the loaded LLM** instead of refusing (JIT off; nothing loads). Check the client's model id is a role |
| `lms daemon status` says "llmster … is running" | llmster took the daemon | `lms daemon down`, then open the app |
| Stuck "Local inference is changing ownership" | app and llmster both installed (lmstudio-bug-tracker#2485) | quit both; `lms daemon down; lms daemon up` |
| Slow under load | `concurrency-bench.sh` at the failing settings | prefill is serialised at any `--parallel`; see `docs/ARCHITECTURE.md` |
| Zed agent stalls | `scripts/diagnose.sh`, `ai-log`, bench | capture all three **before** changing anything |
| Server LAN-visible or CORS on | `ai-status`, `ai-health` | `scripts/boot.sh` restarts it on 127.0.0.1 without CORS |
| aider errors naming `ollama_chat/…` or `local-code` | an old `.aider.conf.yml` in the repo dir | roles are `openai/local-big` now |

Bench any change the same way as the baseline:

```bash
scripts/concurrency-bench.sh --base-url http://127.0.0.1:1234/v1 \
  --token-env LMSTUDIO_HOST_TOKEN --model local-big --concurrency 3 \
  --proc-match '(\.lmstudio/|LM Studio)'
```

## Rollback

There is no old stack to roll back to: it was removed on 2026-10-31 (ADR
0016, Rollback). Backups are in `~/hearth-backups/` (mode 700). Client config
backups end in `.pre-lmstudio-2026-10-31`.

## Laptop access

SSH tunnel only; the server stays on `127.0.0.1`. `docs/LAPTOP.md` has the
whole setup. On the host:

```bash
scripts/client-setup.sh <laptop-name>                       # print the steps
scripts/client-setup.sh <laptop-name> --authorize key.pub   # tunnel-only key
```

`healthcheck.sh` section 5 should say "LAN: no answer" — a LAN answer means
someone turned on Serve on Local Network. Revoke a laptop: delete its token in
LM Studio and its `hearth-tunnel-<name>` line in `~/.ssh/authorized_keys`.
**Never port-forward `:22`, `:1234` or `:3000`.**
