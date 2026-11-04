# Runbook

Start, stop, diagnose. oMLX serves `127.0.0.1:1234` from `~/.hearth/models`
(ADR 0026). `scripts/omlx.sh down` stops oMLX and leaves the port empty
(ADR 0028).

## Layout of the running system

| Piece | Where | Notes |
|---|---|---|
| Server | `127.0.0.1:1234` | oMLX, `scripts/omlx.sh up`. `down` stops it |
| Weights | `~/.hearth/models` | the directories named in `config/roles.tsv` |
| Roles | `config/roles.tsv` | `local-main` resident, 128K × 3. `local-deep` loads beside it (ADR 0028) |
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
3. `scripts/omlx.sh up` writes `~/.omlx/settings.json` (loopback, CORS off,
   no model fallback), serves `local-main`, and refuses to start if something
   else holds `:1234`.
4. Prove auth holds — a positive control first. Do not `source` the env file
   into a shell you keep; `scripts/healthcheck.sh` reads it itself.
5. `echo "source $PWD/scripts/aliases.zsh" >> ~/.zshrc`

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

`scripts/boot.sh` runs `scripts/omlx.sh up`. It serves `local-main` from
the copy in `~/.hearth/models` on `127.0.0.1:1234`, with the host token, a
56 GB memory guard, an 8 GB RAM cache, and a 20 GB SSD cache. `ask-deep`
loads `local-deep` beside `local-main` and unloads `local-deep` on the way
out. The GPU wired limit is 57344 MB (56 GB), installed by
`scripts/iogpu-wired.sh`.
`scripts/omlx.sh bench` checks thinking, tools, and a repeated 30K prompt.
`scripts/omlx.sh down` stops oMLX and leaves the port empty.
A reboot starts oMLX again.
A laptop token is registered with `scripts/omlx.sh sub-key add laptop-<name>`
(the prompt does not echo) and dropped with `sub-key revoke`. That key can
call the model and cannot log in as admin. The operator pastes the token.
`sub-key list` prints names.

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

Footprint of the model worker (the number that matters against the 56 GB
GPU ceiling — RSS understates it):

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
`local-main`.

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
| aider errors naming `ollama_chat/…` or `local-code` | an old `.aider.conf.yml` in the repo dir | roles are `openai/local-main` now |

Bench any change the same way as the baseline:

```bash
scripts/concurrency-bench.sh --base-url http://127.0.0.1:1234/v1 \
  --token-env OMLX_HOST_TOKEN --model local-main --concurrency 3
```

## Rollback

There is no old stack to roll back to: it was removed on 2026-10-31 (ADR
0016, Rollback). Backups are in `~/hearth-backups/` (mode 700). Client config
backups from 2026-10-31 sit beside the live files with a dated suffix.

## Laptop access

SSH tunnel only; the server stays on `127.0.0.1`. `docs/LAPTOP.md` has the
whole setup. On the host:

```bash
scripts/client-setup.sh <laptop-name>                       # print the steps
scripts/client-setup.sh <laptop-name> --authorize key.pub   # tunnel-only key
```

`healthcheck.sh` section 5 should say "LAN: no answer" — a LAN answer means
the server is not bound to loopback. Revoke a laptop with
`scripts/omlx.sh sub-key revoke laptop-<name>` and delete its
`hearth-tunnel-<name>` line in `~/.ssh/authorized_keys`.
**Never port-forward `:22`, `:1234` or `:3000`.**
