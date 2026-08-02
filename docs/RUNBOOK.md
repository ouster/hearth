# Runbook

## Layout of the running system

| Piece | Where | Managed by |
|---|---|---|
| Ollama | `127.0.0.1:11434` — localhost only since ADR 0003 | Ollama.app |
| LiteLLM gateway | `:4000` | launchd, `com.colinnevin.litellm` |
| Postgres | `127.0.0.1:5433` | Podman, `ai-stack-postgres` |
| Open WebUI | `127.0.0.1:3000` | Podman, `ai-stack-webui` |

Config: `~/dev/ai-stack/litellm/config.yaml` (symlinked from `~/.config/litellm/config.yaml`)
Launch wrapper: `~/.config/litellm/run-litellm.sh`
Logs: `~/Library/Logs/litellm.log`, `litellm.error.log`

### Two env files — know which is which

**`~/.config/litellm/env`** is the only one launchd reads. Provider keys,
`LITELLM_MASTER_KEY`, `DATABASE_URL` go here.

**`~/dev/ai-stack/litellm/.env`** is read by `scripts/*.sh` only —
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

cd ~/dev/ai-stack
cp litellm/.env.example litellm/.env    # fill in keys + a real POSTGRES_PASSWORD
scripts/db.sh up

set -a; source litellm/.env; set +a
scripts/create-keys.sh                  # paste the four keys back into .env
scripts/healthcheck.sh
```

Point the running gateway at this repo without touching launchd — `run-litellm.sh`
already loads `~/.config/litellm/config.yaml`, so replace that file with a symlink:

```bash
mv ~/.config/litellm/config.yaml ~/.config/litellm/config.yaml.pre-ai-stack
ln -s ~/dev/ai-stack/litellm/config.yaml ~/.config/litellm/config.yaml
launchctl kickstart -k gui/$(id -u)/com.colinnevin.litellm
```

Provider keys go in `~/.config/litellm/env`, which `run-litellm.sh` sources.
Rollback is `mv` the `.pre-ai-stack` file back and kickstart.

## Everyday

```bash
# restart the gateway
launchctl kickstart -k gui/$(id -u)/com.colinnevin.litellm

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
scripts/webui.sh up          # private scope — local roles only
scripts/webui.sh up --general  # cloud reachable, deliberate
scripts/webui.sh down
```

Then `http://127.0.0.1:3000`. First visit creates a local account; signup is
disabled afterwards. In Settings → Interface, enable **Display "Response Info"**
to see the model and token count under each reply.

`ENABLE_OLLAMA_API=False` is set deliberately. Left on, Open WebUI would talk to
Ollama directly and bypass the gateway — reopening the hole Phase 3 closed.
Title and tag generation is pinned to `local-chat` so background housekeeping
cannot quietly become cloud spend.

Seeing where requests actually went:

```bash
scripts/usage.sh             # last 25: role, tier, model, tokens, cost
scripts/usage.sh --summary   # totals by role, LOCAL vs CLOUD token split
scripts/usage.sh --keys      # per-key spend against its cap
```

The LOCAL percentage in `--summary` is the number worth watching — it is the
proportion of your work that never left the machine. LOCAL/CLOUD is derived from
`config.yaml`, so it stays accurate when models are swapped.

## Diagnosing

**Gateway won't start.** Check `litellm.error.log` first. Most common cause is a
missing env var referenced by `os.environ/` in config.yaml — LiteLLM fails the whole
config, not just that model.

**A role 500s but others work.** Provider issue or a bad model name. `curl` the role
directly with the master key to see the raw error.

**Local role is slow on first call.** Cold load only. The current set totals
37.5 GB against a ~54 GB budget, so all four stay resident and nothing evicts
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
export OPENAI_API_BASE=http://192.168.50.154:4000/v1
export OPENAI_API_KEY=<the lan or roam key>
```

- `lan` — local roles plus `cloud-cheap`. The everyday key.
- `roam` — full cloud including frontier. For the laptop when it actually needs
  Claude or K3.

The dollar figures on these keys are **fuses, not billing** — you are the only user.
They cap spend on your provider account so that a leaked key or a runaway overnight
agent loop hits a wall instead of your card. Raise them whenever they get in the way;
just don't set `null` on a key that can reach a paid model.

Two keys rather than one so the everyday key stays cheap and a lost laptop has a
small, visible blast radius. Rotate with `scripts/create-keys.sh` and delete the old
key via the admin API.

This is LAN only. Do not port-forward `:4000` to the internet — key auth is not
hardening, and a public LiteLLM holding your provider keys is somebody else's budget.
