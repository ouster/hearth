# Runbook

Start, stop, diagnose. oMLX serves `127.0.0.1:1234` from `~/.hearth/models`
(ADR 0026). `scripts/omlx.sh down` stops oMLX and leaves the port empty
(ADR 0028).

## Layout of the running system

| Piece | Where | Notes |
|---|---|---|
| Server | `127.0.0.1:1234` | oMLX, `scripts/omlx.sh up`. `down` stops it |
| Weights | `~/.hearth/models` | the directories named in `config/roles.tsv` |
| Roles | `config/roles.tsv` | `main-brain` resident, 128K × 3. `deep-brain` evicts `main-brain` for its session. `edit-brain` is laptop-only (ADR 0031, 0033) |
| Token | `~/.config/hearth/env`, mode 600 | `OMLX_HOST_TOKEN`. Scripts pass it to the server as `OMLX_API_KEY` |
| Server settings | `~/.omlx/settings.json` (mode 600) | written by `scripts/omlx.sh up`: loopback, CORS off, no model fallback |
| Remote Login (sshd) | `:22` | laptops' tunnel; their keys are `restrict`ed to `-L` `:1234`/`:3000`/`:8888`, with `-R` denied (`scripts/client-setup.sh --update-keys` brings old keys up to date) |
| Open WebUI | Podman, `127.0.0.1:3000` | `scripts/webui.sh` |
| SearXNG | Podman, `:8888` | `scripts/searxng.sh` |

Removed 2026-10-31: Ollama, LiteLLM, Postgres, Rapid-MLX, llmster and their
launchd agents. Ports 4000, 5433 and 11434 should be free.

## First-time setup

1. Put each role's weights at `~/.hearth/models/<weights>` using the path in
   `config/roles.tsv`. Sources are in `docs/MODELS.md`.
2. Store the API key without echoing:
   ```bash
   mkdir -p ~/.config/hearth && umask 077 && \
     printf 'OMLX_HOST_TOKEN=%s\n' "$(pbpaste)" >> ~/.config/hearth/env && \
     chmod 600 ~/.config/hearth/env && pbcopy </dev/null
   ```
   The value is the oMLX API key.
3. Install oMLX either way — Hearth works with both, and does not wipe the
   app's existing `~/.omlx/settings.json`:
   - **Headless:** a venv at `~/.omlx/venv` with `omlx` on that PATH (typical
     early host setup).
   - **DMG:** install `oMLX.app`; it drops `~/.omlx/bin/omlx` → the app CLI.
     Before or after Hearth is fine. `scripts/omlx.sh up` prefers the DMG CLI
     when it runs, falls back to the venv, **merges** host policy into the
     shared settings (loopback, CORS off, `auto_start_on_launch: false`, RAM
     envelope, host token) while leaving UI / aliases / MCP / other app keys
     alone, and picks `main-brain`'s `reasoning_parser` from the live
     `/admin/api/grammar/parsers` list (`qwen_3_5` on 0.7.4+, `qwen` on
     0.7.3). If the app is already serving `:1234`, `up` configures that
     process in place (admin API) and does not take it over.
4. `scripts/omlx.sh up` merges settings, links weights as the org/leaf path
   from `roles.tsv` (discovery id = leaf; `model_alias` = role so clients
   still call `main-brain`, ADR 0034), serves or attaches, and refuses only
   if a non-oMLX process holds `:1234`.
5. Prove auth holds — a positive control first. Do not `source` the env file
   into a shell you keep; `scripts/healthcheck.sh` reads it itself.
6. `echo "source $PWD/scripts/aliases.zsh" >> ~/.zshrc`

## Surviving a reboot

`scripts/install-autostart.sh --apply` installs `com.hearth.boot`, a launchd
agent that runs `scripts/boot.sh` once at login. `boot.sh` runs
`scripts/omlx.sh up`, then starts the Podman VM, SearXNG and Open WebUI.

The plist sets `AbandonProcessGroup`: without it launchd kills every process
`boot.sh` leaves behind when it exits — which is the Podman VM, so WebUI and
SearXNG died minutes after login (seen and reproduced 2026-10-31).

Log: `~/Library/Logs/hearth-boot.log`. Check it with
`scripts/install-autostart.sh --check`. By hand: `scripts/boot.sh`.

The same install loads `com.hearth.context-watch` (`scripts/context-watch.sh`,
KeepAlive). It watches `~/Library/Logs/hearth-omlx.log` and notifies if a
trim line appears. oMLX does not emit that line today, so it stays quiet.
`scripts/install-autostart.sh --watch` loads only that agent. Notices land in
`~/Library/Logs/hearth-context-watch.log`.

### oMLX

`scripts/boot.sh` runs `scripts/omlx.sh up`. It serves `main-brain` from
the copy in `~/.hearth/models` on `127.0.0.1:1234`, with the host token, a
memory guard of RAM minus 8 GB, an 8 GB RAM cache (4 GB below 64 GB RAM),
and a 20 GB SSD cache — or, if oMLX is already listening (app-first install),
merges the same policy into the shared settings and applies it live without
replacing the process. Weights are linked as `~/.omlx/models/<org>/<leaf>`
so omlx.ai benches and the admin UI show the real leaf; `/v1` exposes the
role via `model_alias` (ADR 0034). It does not load `edit-brain` (ADR 0033
amend: laptop oMLX only); a leftover pin in `~/.omlx/model_settings.json` is
cleared on `up` so a post-DMG install cannot preload it. `ask-deep` evicts
`main-brain` for the session and unloads `deep-brain` on the way out
(ADR 0031, 0033). The GPU wired limit is the same RAM minus 8 (57344 MB on
64 GB, 40960 MB on 48 GB), installed by `scripts/iogpu-wired.sh`. Preflight
warns if either differs. `scripts/omlx.sh bench` checks thinking, tools,
and a repeated 30K prompt. `scripts/omlx.sh down` stops a Hearth-started
oMLX (launchd) and leaves the port empty; it does not kill an app-owned
server. A reboot runs `up` again. The Mac app may stay as a settings panel.
A laptop token is registered with
`scripts/omlx.sh sub-key add laptop-m5-air` (the prompt does not echo; the
operator types the token; the name is letters, digits, hyphen, or underscore).
`sub-key list` prints names, not tokens. A name already in that list is left
alone; the laptop uses its existing `~/.hearth-key`. A lost token is
`sub-key revoke laptop-m5-air` and then add again. That key can call the
model and cannot log in as admin.

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
ai-status                      # one glance: server, bind, roles, containers, autostart
ai-health                      # scripts/healthcheck.sh — the real verdict (exit 0/1/2)
scripts/preflight.sh           # static checks: roles.tsv, rule 1, oMLX settings, secrets, drift
ai-loaded                      # scripts/omlx.sh status
ai-load                        # scripts/omlx.sh up
ai-restart                     # oMLX down, then up, on 127.0.0.1:1234
ai-log                         # tail -f ~/Library/Logs/hearth-omlx.log
```

Footprint of the model worker (the number that matters against the
GPU ceiling, RAM minus 8 — RSS understates it):

```bash
footprint -p "$(cat ~/.omlx/hearth.pid)" | awk '/Footprint:/'
```

## Chat UI and visibility

```bash
scripts/webui.sh up            # local only — there is no cloud mode, and no login
scripts/webui.sh down
```

The container reaches the host's `127.0.0.1:1234` via
`host.containers.internal` with "serve on local network" off. `webui.sh up`
refuses to start unless the host token gets a 200. SearXNG stays published
on `127.0.0.1:8888` for Zed and laptop tunnels. The WebUI container does not
use that bind: both containers join the `hearth` Podman network and WebUI
calls SearXNG by container name on port 8080. `up` writes that URL into the
WebUI database, which is the value the search toggle actually uses.

**The connection lives in WebUI's database.** Environment variables only seed
a fresh database. `up` does not rewrite the saved OpenAI URL, and the
anonymous session cannot open the admin panel. Default and task model are
`main-brain`.

### Using the chat UI from a laptop

Open WebUI is a **web app** — nothing to install on the laptop. **Preferred:
SSH tunnel**, which keeps the UI localhost-only:

```bash
ssh -N -L 3000:127.0.0.1:3000 USER@HOST     # then http://127.0.0.1:3000
```

There is no login: `WEBUI_AUTH` is off, and `webui.sh` refuses `--lan` because
that would publish the chat UI with nothing in front of it. **Do not
port-forward :3000 to the internet.** The tunnel is the only remote path.

The anonymous session does not keep chats. Open WebUI creates that user as
admin, and this image skips temporary-chat enforcement for admins, so
`webui.sh up` demotes the user, turns chat sharing off, deletes saved chats,
and refuses new chat rows. A refresh starts empty. The admin panel is not
available in that session. `up` does not rewrite the saved OpenAI connection;
that row in the WebUI database is what the model list uses.

### Do not enable tools in Open WebUI without thinking

Web search feeds arbitrary attacker-controlled page text straight into the
model's context. That is tolerable **only** because the chat model has no tools:
it can mislead you convincingly, but it cannot act.

Enabling tools, functions, or code execution turns this into the highest-risk
surface in the stack. Open WebUI stores these settings in its database, where
they override the environment and survive container recreation. Treat
enabling them as an ADR-worthy decision. See `docs/THREAT-MODEL.md` §3.

### Web search: the env vars are not enough

Same database-wins trap. The anonymous session cannot open the admin panel,
so the value already stored in the volume is the one the toggle follows.
The toggle then appears per message.

### Vulnerability monitoring (Snyk)

Hearth has no dependency manifests, so what Snyk watches is the two container
images: `scripts/snyk-monitor.sh` exports the image each container is running
(by ID — the tags move) and records it as Snyk projects `hearth/webui` and
`hearth/searxng`, plus the Zed SearXNG MCP server's npm lockfile as
`hearth/mcp-searxng` (ADR 0022). Snyk re-tests those snapshots daily and emails new issues.
Only the image's package list leaves the machine, not this repo's code.

- One-time: `brew tap snyk/tap && brew install snyk-cli`, then `snyk auth`
  (browser sign-in; free plan).
- `scripts/webui.sh up` and `scripts/searxng.sh up` re-run it in the
  background; output in `~/Library/Logs/hearth-snyk.log`. After pulling a new
  image, run `scripts/snyk-monitor.sh` by hand if you did not `up`.
- Exit 2 means it could not run (no CLI, not signed in, Podman down), not that
  the images are clean.

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
| Wrong model answers | `scripts/healthcheck.sh` | An unknown model name can be answered by the loaded role. Check the client's model id is a role |
| Slow under load | `concurrency-bench.sh` at the failing settings | prefill is serialised; see `docs/ARCHITECTURE.md` |
| Zed agent stalls | `ai-log`, `scripts/status.sh`, bench | capture them **before** changing anything |
| Server LAN-visible or CORS on | `ai-status`, `ai-health` | `scripts/boot.sh` restarts it on 127.0.0.1 without CORS |
| aider errors naming `ollama_chat/…` or `local-code` | an old `.aider.conf.yml` in the repo dir | roles are `openai/main-brain` now |

Bench any change the same way as the baseline:

```bash
scripts/concurrency-bench.sh --base-url http://127.0.0.1:1234/v1 \
  --token-env OMLX_HOST_TOKEN --model main-brain --concurrency 3
```

## Rollback

There is no old stack to roll back to: it was removed on 2026-10-31 (ADR
0016, Rollback). Backups are in `~/hearth-backups/` (mode 700). Client config
backups from 2026-10-31 sit beside the live files with a dated suffix.

## Laptop access

SSH tunnel only; the server stays on `127.0.0.1`. `docs/LAPTOP.md` has the
whole setup. On the host:

```bash
scripts/client-setup.sh m5-air                              # print the steps
scripts/omlx.sh sub-key add laptop-m5-air                   # new token only
scripts/client-setup.sh m5-air --authorize key.pub          # tunnel-only key
```

`laptop-m5-air` already in `sub-key list`: skip add; the laptop keeps
`~/.hearth-key`. `healthcheck.sh` section 5 should say "LAN: no answer" — a
LAN answer means the server is not bound to loopback. Revoke a laptop with
`scripts/omlx.sh sub-key revoke laptop-m5-air` and delete its
`hearth-tunnel-m5-air` line in `~/.ssh/authorized_keys`.
**Never port-forward `:22`, `:1234` or `:3000`.**
