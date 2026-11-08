# Laptop access

**SSH tunnel only.** The host's oMLX stays
bound to `127.0.0.1:1234`; a laptop forwards a local port to it over SSH. Same
setup on the LAN and away from it, traffic encrypted, nothing on the host
exposed to the network.

```mermaid
flowchart LR
    subgraph laptop["Laptop"]
        lz["Zed / aider / ai-*"]
        ld["macOS launchd<br/>com.hearth.tunnel"]
        lp["127.0.0.1:1234<br/>127.0.0.1:3000<br/>127.0.0.1:8888"]
    end
    subgraph host["Host"]
        sshd["sshd :22<br/>tunnel-only key"]
        srv["oMLX 127.0.0.1:1234<br/>token per machine"]
        webui["Open WebUI 127.0.0.1:3000<br/>SearXNG 127.0.0.1:8888"]
    end
    gem["Gemini<br/>laptop's own key"]
    ld -->|"ssh -N -L, KeepAlive"| lp
    lz --> lp
    lp -->|"ssh -L"| sshd
    sshd --> srv
    sshd --> webui
    lz -.->|"ask-cloud only"| gem
```

## What each laptop gets

| Thing | Where | Why |
|---|---|---|
| API key `laptop-m5-air` | laptop `~/.hearth-key` (mode 600) | the `sub-key add` argument. Revoke one machine without touching the others |
| `edit-brain` on the laptop's own oMLX (optional) | `~/.hearth/models`, linked into `~/.omlx/models` by `client/edit-model.sh laptop-up` | local edit prediction; host does not serve it. Paid Zed Zeta is the cloud alternative (`docs/IDES.md`, ADR 0033) |
| API keys `jetbrains-<name>`, `xcode-<name>` (optional) | typed into the IDE's own key field | revoke one editor without touching the laptop's key (`docs/IDES.md`) |
| SSH key `hearth_tunnel` | laptop `~/.ssh/hearth_tunnel`; host `authorized_keys` with `command="/usr/bin/false",restrict,port-forwarding,permitopen=…,permitlisten="none:1"` | the key can `-L` to `127.0.0.1:1234`, `:3000` and `:8888` only — no shell, no commands, no `-R`, no other ports |
| Google API key (optional) | laptop `~/.hearth-gemini-key` (mode 600) | `ask-cloud` with the laptop's own key; the host holds no Google key (ADR 0038) |
| `client/hearth-client.sh` / `.ps1` | laptop `~/.hearth-client.sh` | `ai-tunnel`, `ai-tunnel-install` (macOS), `ai-ping`, `ai-models`, `ai-ask`, `ai-webui`, `ask*`, `ask-deep`, `ask-cloud` |

Secrets are read from files per command and never exported into the
laptop's shell. A world-readable key file is refused.

## Names

`scripts/client-setup.sh` takes the short name. `m5-air` and `laptop-m5-air`
are the same machine. The short name is letters, digits, `-` and `_`.

| | Example |
|---|---|
| `sub-key add` argument | `laptop-m5-air` |
| SSH `authorized_keys` comment | `hearth-tunnel-m5-air` |

`scripts/omlx.sh sub-key list` prints names, not tokens. The argument is that
name (`laptop-m5-air`). A model id or a display name is rejected with
`name must be letters, digits, hyphen, or underscore`.

## Setup

On the host, `scripts/client-setup.sh m5-air` prints every step with this
host's name and user filled in (`--windows` for PowerShell). Ask which path
applies, then follow that path only.

### New machine

`laptop-m5-air` is absent from `scripts/omlx.sh sub-key list`.

1. **Host user**, with oMLX listening (`scripts/omlx.sh status`):
   `scripts/omlx.sh sub-key add laptop-m5-air`. The prompt says
   `paste the token for laptop-m5-air` and does not echo. The command does
   not invent a token. The same string is stored on the laptop as
   `~/.hearth-key`. A reboot runs `scripts/omlx.sh up`, which keeps sub-keys
   already registered.
2. **Laptop:** `ssh-keygen -t ed25519 -f ~/.ssh/hearth_tunnel -C hearth-tunnel-m5-air`,
   and a `Host hearth` entry in `~/.ssh/config` pointing at the host with
   `IdentitiesOnly yes`.
3. **Host:** `scripts/client-setup.sh m5-air --authorize hearth_tunnel.pub`.
   It refuses a key that is already authorized without restrictions.
4. **Laptop:** copy `client/hearth-client.sh` to `~/.hearth-client.sh`,
   store the token and (optionally) a Google key, add
   `HEARTH_SSH=hearth`, `HEARTH_CLOUD_MODEL=…` and `source ~/.hearth-client.sh`
   to the shell rc.
5. **Laptop:** `ai-tunnel` once, so the host fingerprint can be accepted.
   On macOS, then `ai-tunnel-install`. Then `ai-ping && ai-models`.

### Already registered

`laptop-m5-air` is already in `sub-key list`. Skip `sub-key add`. A second
add with a different token fails: `sub-key laptop-m5-air already exists`.

The laptop user:

1. Keep the existing `~/.hearth-key` (mode 600). That file is the token for
   `laptop-m5-air`. When the file is missing, ask the host user to
   `scripts/omlx.sh sub-key revoke laptop-m5-air` and then
   `scripts/omlx.sh sub-key add laptop-m5-air` with a new token. `sub-key list`
   cannot show the old one.
2. Keep `~/.ssh/hearth_tunnel` when the host's `--authorize` prints
   `already authorized`. Skip `ssh-keygen`. When the private key is gone,
   generate a new one and authorize that `.pub`.
3. Copy the current `client/hearth-client.sh` over `~/.hearth-client.sh` and
   source it with `HEARTH_SSH=hearth`.
4. On macOS, `ai-tunnel` once if the host fingerprint is new, then
   `ai-tunnel-install`. Login starts the tunnel after that. On Linux,
   `ai-tunnel`.

`ai-ping` answers: `up`, `BAD TOKEN` (revoked or wrong token), `NO ANSWER`
(tunnel up but host asleep or oMLX down — on the host, `scripts/boot.sh`),
or `DOWN` (no tunnel — `ai-tunnel`).
If something else is already listening on `127.0.0.1:1234`, the client refuses and does not send the token.

## Keeping the tunnel up

`ai-tunnel` alone is one `ssh -f`. When that session drops, nothing restarts
it. On macOS, `ai-tunnel-install` writes
`~/Library/LaunchAgents/com.hearth.tunnel.plist`: `ssh -N` with the same
`-L` forwards, `KeepAlive`, and `RunAtLoad`. launchd restarts it after a
drop and at login. Later `ai-tunnel` kickstarts that job. `ai-tunnel-stop`
unloads it (`launchctl bootout`) and also stops a one-shot `ssh -f`. Linux
and Windows stay on `ai-tunnel`. Logs:
`~/Library/Logs/hearth-tunnel.error.log`. Accept the host fingerprint with
one interactive `ai-tunnel` before install; launchd cannot prompt.

## AI-assisted setup

For an AI assistant (Claude Code, Cursor, …) running **on the laptop** in a
clone of this repo. The assistant is probably a cloud model: anything it reads
or prints goes to its vendor. That decides every rule below.

**Never:** read, print, grep, copy or edit `~/.hearth-key`,
`~/.hearth-gemini-key` or `~/.ssh/hearth_tunnel` (the private key); ask the
person to paste a token or key into the chat; run anything in `scripts/`
(host-only); add a router port-forward; suggest turning on Serve on Local
Network; configure hearth as a Cursor model provider (see below). Checking a
secret file's permissions with `ls -l` is fine.

**1. Ask the person which path, and for the short name.**

Example short name: `m5-air`. The host command is then
`scripts/omlx.sh sub-key add laptop-m5-air`. The SSH comment is
`hearth-tunnel-m5-air`. Letters, digits, `-`, `_`. Also ask for the host as
`user@host.local` (on the host: `id -un` and `scutil --get LocalHostName`)
and the shell: macOS / Linux (zsh or bash) or Windows PowerShell.

- **New.** `laptop-m5-air` is absent from the host's `scripts/omlx.sh sub-key list`.
  Ask the host user to run `sub-key add laptop-m5-air` and type a token.
- **Already registered.** That name is already in the list. Skip `sub-key add`.
  The laptop keeps its existing `~/.hearth-key`. When that file is missing,
  ask the host user to `sub-key revoke laptop-m5-air` and then
  `sub-key add laptop-m5-air` with a new token. The list cannot show the old one.

Read the Gemini model id yourself: the `cloud-cheap` row of
`config/roles.tsv`, column 3. Do not copy it anywhere except the
`HEARTH_CLOUD_MODEL` line.

**2. You may run** (macOS / Linux; Windows equivalents are in
`client/hearth-client.ps1`'s header). Skip `ssh-keygen` when
`~/.ssh/hearth_tunnel` already exists and the host will say
`already authorized`.

```bash
# Interactive (passphrase prompt) — ask the person to run it, or run it if your
# terminal is interactive. New tunnel key only:
ssh-keygen -t ed25519 -f ~/.ssh/hearth_tunnel -C hearth-tunnel-m5-air

# ~/.ssh/config — append only if there is no "Host hearth" entry already
printf 'Host hearth\n  HostName %s\n  User %s\n  IdentityFile ~/.ssh/hearth_tunnel\n  IdentitiesOnly yes\n  ServerAliveInterval 30\n  ServerAliveCountMax 3\n' <host.local> <user> >> ~/.ssh/config

cp client/hearth-client.sh ~/.hearth-client.sh
printf 'export HEARTH_SSH=hearth\nexport HEARTH_CLOUD_MODEL=%s\nsource ~/.hearth-client.sh\n' <cloud-cheap id> >> ~/.zshrc   # or ~/.bashrc
```

Showing the person `~/.ssh/hearth_tunnel.pub` is fine — it is public.

**3. Stop and hand over to the person** for each of these, then wait:

1. *On the host*, while oMLX is listening. New machine: the host user runs
   `scripts/omlx.sh sub-key add laptop-m5-air` and types the token.
   Already registered: they run `scripts/omlx.sh sub-key list` and confirm
   `laptop-m5-air` is there, and they skip add. Do not ask anyone to paste
   a token into the chat.
2. *On the host*, with the `.pub` file copied over:
   `scripts/client-setup.sh m5-air --authorize hearth_tunnel.pub`.
   `already authorized` means the laptop keeps the key it has.
3. *On the laptop, in their own terminal* (not through you). New token, or
   `~/.hearth-key` is missing:

   ```bash
   umask 077
   read -rs t && printf '%s' "$t" > ~/.hearth-key && unset t          # laptop-m5-air token
   read -rs t && printf '%s' "$t" > ~/.hearth-gemini-key && unset t   # optional: this laptop's OWN Google key
   ```

   Already registered and `~/.hearth-key` is already that token: skip the
   `read`. Then confirm with `ls -l ~/.hearth-key ~/.hearth-gemini-key`: mode
   `-rw-------`, non-zero size. Nothing more.

**4. Prove it** in a new shell. Both halves are required: the first shows the
key works, the second that it can do nothing else.

| Command | Expect |
|---|---|
| `ai-tunnel` | `tunnel: up` (the first run asks the person to confirm the host fingerprint) |
| `ai-tunnel-install` | macOS: `tunnel: installed com.hearth.tunnel`. Linux: skip this |
| `ai-ping` | `up` |
| `ai-models` | `main-brain` (plus `deep-brain` only while the host has it loaded) |
| `ai-ask "say ok"` | a short reply from main-brain |
| `ssh hearth true; echo $?` | **non-zero**, no shell: the key is tunnel-only |
| `ask-cloud` (optional) | aider on Gemini with the laptop's own key |
| `ask-deep` (optional) | refuses with "not loaded on the host" unless the host ran `scripts/demand-load.sh deep-brain up`; the laptop cannot load it (tunnel-only key). `main-brain` stays loaded beside it |

If `ai-ping` says `BAD TOKEN`, the person re-runs the `read -rs` step with
the right token; `NO ANSWER` means the host is asleep or oMLX is down
(fix on the host); `DOWN` means no tunnel. If `ssh hearth true` **succeeds**,
stop: the key was authorized without restrictions — tell the person, and do
not continue.

**5. Editors.** Zed: the block in [Zed on the laptop](#zed-on-the-laptop),
with the laptop's token entered through Zed's UI by the person.

**Cursor cannot use hearth as its model provider.** Cursor's backend makes
the model call, not the laptop, so a `localhost` base URL never reaches the
tunnel; the only workaround is a public endpoint, which the *Never* list
forbids, and prompts would still pass through Cursor's servers (checked
2026-10-31). Use Zed, aider or `ask` for main-brain on the laptop; Cursor
with its own models only, and not on sensitive repos.

## Zed on the laptop

Same provider as the host, through the tunnel:

```json
{
  "language_models": {
    "openai_compatible": {
      "hearth": {
        "api_url": "http://127.0.0.1:1234/v1",
        "available_models": [
          { "name": "main-brain", "display_name": "main-brain", "max_tokens": 131072 }
        ]
      }
    }
  },
  "agent": { "default_model": { "provider": "hearth", "model": "main-brain" } }
}
```

Token through the UI (Agent panel → settings → `hearth` → API key): the
laptop's `laptop-m5-air` token. On macOS, `ai-tunnel-install` starts the
tunnel at login. Run `ai-tunnel` before Zed when that agent is not installed,
or Zed's models show as unavailable.

A Gemini provider **is allowed on the laptop** (D3), with the laptop's own
key. The host has none. Keep sensitive repos on `hearth/main-brain`.

If using the legal-research worked example from `docs/MCP.md`, install and
review its source on the laptop too; its stdio process runs beside Zed, not on
the host. The same "Write enables every server" trap applies.

## Open WebUI from the laptop

`ai-webui` opens `http://127.0.0.1:3000` through the tunnel — the host's own
instance, no login, same history. Nothing to install on the laptop.

## Web search in the laptop's Zed (optional)

The tunnel also forwards the host's SearXNG to `127.0.0.1:8888` (ADR 0022;
`HEARTH_SEARXNG_PORT` changes the laptop end, `0` leaves it out). To give the
laptop's Zed agent web search, install the same pinned MCP server there and
register it the way the host does (`docs/MCP.md`, `docs/IDES.md`):

```bash
npm install --ignore-scripts --save-exact --prefix ~/.local/share/hearth/mcp-searxng mcp-searxng@2.9.0
```

Then a `searxng` stdio context server in Zed with
`SEARXNG_URL=http://127.0.0.1:8888` (or your `HEARTH_SEARXNG_PORT`). Enable
`searxng_web_search` only, in `web` (no file tools, `default_model`
`hearth/main-brain`) and, for a coding thread, `write-web` (Write's tools,
no pinned model). Do not switch either profile to Gemini. The tunnel has to
be up (`ai-tunnel-install` on macOS, otherwise `ai-tunnel`). Search queries
go to public search engines via the host.
An agent that can read files can put personal information from them into
that query.

SearXNG has no login. Once the tunnel is up, any process on the laptop can
POST a query to `127.0.0.1:8888` and the host will send it to the public
engines.

**Existing laptops:** follow [Already registered](#already-registered). The
host's tunnel keys were widened with `scripts/client-setup.sh --update-keys`
(2026-11-01). On the laptop, copy the new client
(`scripts/client-setup.sh m5-air --install user@laptop` from the host), then
`ai-tunnel-stop && ai-tunnel-install` (macOS) or `ai-tunnel` (Linux). Skip
`sub-key add` when `laptop-m5-air` is already listed. `ai-tunnel` refuses to
report the tunnel up when `:1234` is open and `:3000` or `:8888` is not, and
when `:1234` is open but the listener is not this client's ssh.

## Revoking a laptop

1. While oMLX is up: `scripts/omlx.sh sub-key revoke laptop-m5-air`.
2. Host: delete the `hearth-tunnel-m5-air` line from `~/.ssh/authorized_keys`.

Removing the tunnel key cuts the path. Revoke the sub-key so a reboot does
not let it back in.

## Never

- Port-forward `:22`, `:1234`, `:3000` or `:8888` on the router.
- Turn on Serve on Local Network for a laptop — the tunnel makes it unnecessary,
  and it would put the token on the LAN in plain HTTP.
- Copy the host's token or Google key to a laptop.

## Host SSH hardening (recommended, not done for you)

macOS Remote Login accepts passwords by default. With keys in place:

```bash
echo 'PasswordAuthentication no
KbdInteractiveAuthentication no' | sudo tee /etc/ssh/sshd_config.d/100-hearth.conf
sudo launchctl kickstart -k system/com.openssh.sshd
```

Test a key login from the laptop **before** closing your current session.
