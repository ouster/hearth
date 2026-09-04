# Runbook

## Layout of the running system

| Piece | Where | Managed by |
|---|---|---|
| Ollama | `127.0.0.1:11434` — localhost only since ADR 0003 | Ollama.app |
| LiteLLM gateway | `:4000` | launchd (`com.hearth.litellm` by default) |
| Postgres | `127.0.0.1:5433` | Podman, `hearth-postgres` |
| Open WebUI | `127.0.0.1:3000` | Podman, `hearth-webui` |

Config: `<repo>/litellm/config.yaml` (symlinked from `~/.config/litellm/config.yaml`)
Launch wrapper: `~/.config/litellm/run-litellm.sh`
Logs: `~/Library/Logs/litellm.log`, `litellm.error.log`

Launchd label overrides (optional): `HEARTH_LITELLM_LABEL`, `HEARTH_OLLAMA_LABEL`,
`HEARTH_BOOT_LABEL`. Scripts auto-discover an already-installed agent.

### Two env files — know which is which

**`~/.config/litellm/env`** is the only one launchd reads. Provider keys,
`LITELLM_MASTER_KEY`, `DATABASE_URL` go here.

**`<repo>/litellm/.env`** is read by `scripts/*.sh` only —
`POSTGRES_PASSWORD`, the virtual keys, and a copy of `DATABASE_URL` for `db.sh`.

launchd reads neither the repo `.env` nor `~/.zshrc`. A var exported in your shell
will pass a careless check and then fail at runtime; `preflight.sh` deliberately
checks the service environment and flags "set in your shell but NOT in
~/.config/litellm/env" as a failure.

## First-time setup

```bash
# Podman, once ever
brew install podman
podman machine init --cpus 2 --memory 2048 --disk-size 20
podman machine start

cd /path/to/hearth
cp litellm/.env.example litellm/.env    # fill in keys + a real POSTGRES_PASSWORD
scripts/db.sh up

set -a; source litellm/.env; set +a
scripts/create-keys.sh                  # paste the four keys back into .env
scripts/deploy.sh                       # symlink + restart + verify
scripts/healthcheck.sh
```

Or point the running gateway at this repo by hand — `run-litellm.sh` already
loads `~/.config/litellm/config.yaml`, so replace that file with a symlink:

```bash
REPO=/path/to/hearth
mv ~/.config/litellm/config.yaml ~/.config/litellm/config.yaml.pre-hearth
ln -s "$REPO/litellm/config.yaml" ~/.config/litellm/config.yaml
# restart: scripts/aliases.zsh defines ai-restart, or:
launchctl kickstart -k "gui/$(id -u)/com.hearth.litellm"
```

Provider keys go in `~/.config/litellm/env`, which `run-litellm.sh` sources.
Rollback is `mv` the `.pre-hearth` file back and kickstart.

## Surviving a reboot

```bash
scripts/install-autostart.sh --check    # what does and does not come back
scripts/install-autostart.sh --apply    # install the boot agent
scripts/status.sh                       # is everything up right now
```

What already survives, and what does not:

| Piece | After a reboot |
|---|---|
| LiteLLM | comes back — launchd `KeepAlive` |
| `OLLAMA_HOST` | set at login by `com.user.setollamahost.plist` (also in serve plist) |
| Ollama memory | `FLASH_ATTENTION=1`, `KV_CACHE_TYPE=q8_0`, `MAX_LOADED_MODELS=1`, `KEEP_ALIVE=-1` via serve plist — ADR 0011 |
| Ollama itself | **only if "Open at Login" is ticked in its Settings** |
| Podman VM | **does not start itself** — this is the real gap |
| Containers | restart policies only apply once the VM is up |

`scripts/boot.sh` closes the gap: starts the Podman VM, starts the containers,
waits for Postgres, then kicks the gateway if it has not settled.

LiteLLM would eventually recover on its own — it crash-loops against a missing
database and launchd restarts it every 10 s — but a clean start beats a minute
of restart noise in the log.

### Sleep

A sleeping Studio means every laptop loses the gateway. `install-autostart.sh`
**prints** these rather than running them, because silently changing when your
machine sleeps is not something a script should do:

```bash
sudo pmset -c sleep 0        # never sleep on AC
sudo pmset -c disksleep 0
sudo pmset -a womp 1         # wake on network access
sudo pmset -c displaysleep 10   # displays can still sleep, that is free
```

`womp` is the interesting one — with it a laptop reaching the host can wake
it. Without it, asleep means unavailable.

## Everyday

```bash
# restart the gateway (or: source scripts/aliases.zsh && ai-restart)
launchctl kickstart -k "gui/$(id -u)/com.hearth.litellm"

# is it up
curl -s localhost:4000/health/readiness | python3 -m json.tool

# health of every role + the leak test
scripts/healthcheck.sh

# tail errors
tail -f ~/Library/Logs/litellm.error.log

# what's loaded in memory right now
ollama ps

# spend
curl -s -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  localhost:4000/spend/logs | python3 -m json.tool | head -50
```

## Chat UI and visibility

```bash
scripts/webui.sh up            # private scope — local roles only
scripts/webui.sh up --general  # cloud reachable, deliberate
scripts/webui.sh up --lan      # reachable from other machines (see below)
scripts/webui.sh down
```

### Using the chat UI from a laptop

Open WebUI is a **web app** — nothing to install on the laptop, and you get the
same chat history rather than a second disconnected copy. It only needs to be
reachable.

**Preferred: SSH tunnel.** Keeps the UI localhost-only, works from anywhere you
can ssh, and encrypts the traffic:

```bash
# on the laptop — USER@HOST is the gateway machine
ssh -N -L 3000:127.0.0.1:3000 USER@HOST
# then browse to http://127.0.0.1:3000
```

**Alternative: bind to the LAN.**

```bash
scripts/webui.sh up --lan     # then http://<LAN-IP>:3000
```

Open WebUI has its own login, so this is not wide open. But it is another
authenticated surface on a machine whose other services — Ollama, Postgres — are
deliberately localhost-only, and the traffic is plain HTTP. Fine on a trusted
home network; the tunnel is better if you can be bothered.

Either way, **do not port-forward :3000 to the internet.**

Then `http://127.0.0.1:3000`. First visit creates a local account; signup is
disabled afterwards. In Settings → Interface, enable **Display "Response Info"**
to see the model and token count under each reply.

`ENABLE_OLLAMA_API=False` is set deliberately. Left on, Open WebUI would talk to
Ollama directly and bypass the gateway — reopening the hole Phase 3 closed.
Title and tag generation is pinned to `local-chat` so background housekeeping
cannot quietly become cloud spend.

### Do not enable tools in Open WebUI without thinking

Web search feeds arbitrary attacker-controlled page text straight into the
model's context. That is tolerable **only** because the chat model has no tools:
it can mislead you convincingly — which matters for legal research — but it
cannot act.

Enabling tools, functions, or code execution turns this into the highest-risk
surface in the stack: untrusted web content plus the ability to do something
with it. Open WebUI also stores these settings in its database, where they
override the environment and survive container recreation, so a toggle flipped
once stays flipped invisibly.

Treat enabling them as an ADR-worthy decision, not a settings change. See
`docs/THREAT-MODEL.md` §3, surface 5.

### Web search: the env vars are not enough

Open WebUI treats these as config values stored in its **database**, and the
database value **takes precedence over the environment**. Environment variables
only seed a *fresh* database. Because `webui.sh up` recreates the container but
keeps the `hearth-webui-data` volume, whatever was written on first run wins —
so the toggle can be absent even though `podman exec hearth-webui env` clearly
shows `ENABLE_WEB_SEARCH=True`.

Enable it where it actually counts:

```
Admin Panel -> Settings -> Web Search -> Enable Web Search
  Engine:    searxng
  Query URL: http://host.containers.internal:8888/search?q=<query>
```

The toggle then appears in the chat input, per message. If it later disappears,
that is usually a stale access token — sign out and back in.

This is a general trap with any tool that has both env config and a settings UI:
checking the environment tells you what was *intended*, not what is *in effect*.

Seeing where requests actually went:

```bash
scripts/usage.sh             # last 25: role, tier, model, tokens, cost
scripts/usage.sh --summary   # totals by role, LOCAL vs CLOUD token split
scripts/usage.sh --keys      # per-key spend against its cap
```

The LOCAL percentage in `--summary` is the number worth watching — it is the
proportion of your work that never left the machine. LOCAL/CLOUD is derived from
`config.yaml`, so it stays accurate when models are swapped.

## Running agents contained

```bash
scripts/sandboxed.sh aider              # confine to $PWD
scripts/sandboxed.sh --dir ~/dev/x aider
scripts/sandboxed.sh --print-profile    # audit the profile, no Mac required
scripts/sandbox-probe.sh                # re-verify the controls still hold
```

Inside a sandboxed session the agent can reach **only** the gateway. That means
`pip install`, `npm install`, `git push` and any `curl` will fail — by design.
Run those in a normal shell.

**Re-run `sandbox-probe.sh` after every macOS update.** `sandbox-exec` is
deprecated and Apple can change or remove it without notice. The probe is how
you find that out on purpose instead of by being breached.

If an agent crashes on a permission error naming a path outside the repo, that
is the sandbox working. Either add a preset in `sandboxed.sh` (preferred, so it
is remembered) or widen once with `--also-write PATH`. Every widening is printed
at startup — if you see a `WIDENED` line you did not expect, stop and find out why.

What this does **not** protect against: an agent reading your keys (reads are
unrestricted on purpose) or corrupting the repo it was invited into. Commit
before starting a session and `git diff` before accepting. Full reasoning in
`docs/THREAT-MODEL.md`.

## Diagnosing

**Gateway won't start.** Check `litellm.error.log` first. Most common cause is a
missing env var referenced by `os.environ/` in config.yaml — LiteLLM fails the whole
config, not just that model.

**A role 500s but others work.** Provider issue or a bad model name. `curl` the role
directly with the master key to see the raw error.

**Local role is slow on first call.** Cold load only. The current set totals
37.5 GB against a ~48 GB GPU ceiling, so all four stay resident and nothing evicts
anything. `ollama ps` shows what is loaded. If a role is suddenly slow again,
check that a newly added model has not pushed the set over budget.

**Everything local fails.** By design local roles do not fall back to cloud, so they
fail loudly rather than silently shipping your prompt to Google. Check Ollama:
`curl localhost:11434/api/tags`.

**Break-glass.** If the gateway is down and you need inference now, hit Ollama directly
at `127.0.0.1:11434`. No logging, no spend tracking, no key scoping — unblock yourself,
then fix the gateway.

## Rollback

Inherited config and aliases are recorded verbatim in
`docs/decisions/0001-inherited-state.md`. Restore
`~/.config/litellm/config.yaml` from that file and kickstart the agent.

## Upgrading LiteLLM

Four steps, and skipping the third produces a failure that looks like success.

```bash
# 1. Dump the database. It holds your key VALUES, the research team and spend
#    history — losing it means re-pasting keys on every laptop.
mkdir -p ~/hearth-backups
podman exec -e PGPASSWORD="$POSTGRES_PASSWORD" "$(. scripts/lib.sh; ai_container postgres)" \
  pg_dump -U litellm -d litellm > ~/hearth-backups/litellm-$(date +%Y%m%d-%H%M%S).sql

# 2. Upgrade. --force recreates the venv, so the injected packages go with it.
pipx install --force 'litellm[proxy]==<version>'
pipx inject litellm prisma psycopg2-binary

# 3. Regenerate the prisma client AND sync the schema.
scripts/setup-prisma.sh

# 4. Restart and verify.
launchctl kickstart -k "$(. scripts/lib.sh; ai_litellm_agent)"
scripts/preflight.sh && scripts/healthcheck.sh && scripts/audit-mcp-scope.sh
```

**Why step 3 matters.** Recreating the venv deletes the generated prisma
client, so the gateway will not start at all — that failure is loud and
obvious. The quiet one comes next: a new LiteLLM expects database columns the
live schema does not have, and then the gateway *does* start,
`/health/readiness` reports `db:connected`, `/v1/models` answers, and every
`/key/*` call returns 500 with

```
The column `LiteLLM_VerificationToken.key_type` does not exist
```

Scoped keys and MCP grants stop resolving while `status.sh` shows a green
stack. Preflight now checks the key API directly for exactly this.

Take the release LiteLLM marks **stable**, not the newest on PyPI — the latter
is often hours old. 1.85.1 → 1.94.1 on 2026-08-02 needed all four steps and
also rebuilt the venv on a newer Python.

## Postgres (Podman)

```bash
scripts/db.sh up        # start (starts the Podman VM if needed)
scripts/db.sh status
scripts/db.sh logs
scripts/db.sh psql
scripts/db.sh down      # stop, keeps data
scripts/db.sh destroy   # DESTROYS all keys and spend history, prompts first
```

Bound to `127.0.0.1:5433` — deliberately unreachable from the LAN, and on 5433 to
avoid clashing with any other Postgres.

**Podman gotcha:** the container runs inside a Linux VM, and that VM does not start
itself after a reboot. `scripts/db.sh up` starts it for you, but if the gateway boots
first it will come up with no database and virtual keys will fail until you run it.
If that becomes annoying, add a launchd agent for `podman machine start`.

## LAN and laptop access

The gateway listens on `:4000` across interfaces and is protected by key auth, so
other machines just need a base URL and a key:

```bash
# Prefer: scripts/client-setup.sh lan   (fills in this host's LAN IP)
export OPENAI_API_BASE=http://<LAN-IP>:4000/v1
export OPENAI_API_KEY=<the lan or lan-cloud key>
```

- `lan` — local roles plus `cloud-cheap`. The everyday key.
- `lan-cloud` — every live cloud role. For a laptop that actually needs Claude
  or K3. Same LAN, wider scope — the difference is reach, not location.

The dollar figures on these keys are **fuses, not billing** — you are the only user.
They cap spend on your provider account so that a leaked key or a runaway overnight
agent loop hits a wall instead of your card. Raise them whenever they get in the way;
just don't set `null` on a key that can reach a paid model.

Two keys rather than one so the everyday key stays cheap and a lost laptop has a
small, visible blast radius. Both are LAN-only; neither works off this network. Rotate with `scripts/create-keys.sh` and delete the old
key via the admin API.

This is LAN only. Do not port-forward `:4000` to the internet — key auth is not
hardening, and a public LiteLLM holding your provider keys is somebody else's budget.
