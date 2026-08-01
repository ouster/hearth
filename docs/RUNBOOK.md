# Runbook

## Layout of the running system

| Piece | Where | Managed by |
|---|---|---|
| Ollama | `127.0.0.1:11434` (after Phase 3; currently `*:11434`) | Ollama.app |
| LiteLLM gateway | `:4000` | launchd, `com.colinnevin.litellm` |
| Postgres | `127.0.0.1:5433` | Podman, `ai-stack-postgres` |
| Open WebUI | `127.0.0.1:8080` (Phase 6) | Docker |

Config: `~/dev/ai-stack/litellm/config.yaml`
Launch wrapper: `~/.config/litellm/run-litellm.sh`
Logs: `~/Library/Logs/litellm.log`, `litellm.error.log`

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

## Diagnosing

**Gateway won't start.** Check `litellm.error.log` first. Most common cause is a
missing env var referenced by `os.environ/` in config.yaml — LiteLLM fails the whole
config, not just that model.

**A role 500s but others work.** Provider issue or a bad model name. `curl` the role
directly with the master key to see the raw error.

**Local role is slow on first call.** Cold load. `llama3.3:70b` is 42 GB and cannot
coexist with `local-code` (19 GB) in a 64 GB machine, so switching between them forces
an eviction and a full reload. `ollama ps` shows what's resident. This is the main
argument for retiring the 70B.

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
