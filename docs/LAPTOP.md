# Laptop setup — aider and Zed

> **Stale until phase 4.** This still describes laptop access through the retired gateway on `:4000`. Phase 4 of `docs/MIGRATION-LMSTUDIO.md` rewrites it for LM Studio on `:1234` with a per-machine token. Do not follow the commands below.

Start to finish for a second machine. macOS and Linux; Windows notes at the end.

Nothing here downloads a model. Inference happens on the gateway host; the laptop
sends requests to the gateway. **If the gateway host is asleep, none of it works** —
that is the trade for not putting 37 GB of weights on every device.

---

## 1. Get the key and the shim

On the **gateway host**:

```bash
cd <hearth-repo>
scripts/client-setup.sh lan                      # prints instructions + key
scripts/client-setup.sh lan --install user@laptop   # or does it over ssh
```

Manually, on the **laptop**:

```bash
scp USER@HOST:<hearth-repo>/client/hearth-client.sh ~/.hearth-client.sh
printf '%s' 'sk-...' > ~/.hearth-key && chmod 600 ~/.hearth-key

# ~/.zshrc on macOS, ~/.bashrc on Linux
echo 'export HEARTH_GATEWAY=http://<LAN-IP>:4000' >> ~/.zshrc
echo 'source ~/.hearth-client.sh'                       >> ~/.zshrc
```

Use the **`lan`** key. `private` is for the gateway host; `lan-cloud` only differs once
a frontier provider is configured.

## 2. Verify before installing anything else

```bash
ai-ping                  # gateway reachable?
ai-models                # which roles this key may use
ai-ask "say hello"       # one-shot, no editor needed
```

If `ai-ping` fails, stop here — everything below depends on it. Check the gateway host
is awake and you are on the same network.

---

## 3. aider

```bash
pipx install aider-chat          # or: pip install --user aider-chat
```

Create `~/.aider.conf.yml` on the laptop:

```yaml
model: openai/local-code
weak-model: openai/local-chat
dark-mode: true
auto-commits: true
map-tokens: 4096
```

Roles, not model names — so this file never needs editing when a model changes
on the gateway host.

The shim gives you:

```bash
ask "explain this repo"     # local-code
ask-chat "..."              # local-chat, general questions
ask-big "..."               # local-big, reasoning
ask-cloud "..."             # cloud-cheap, leaves the machine
```

### Architect mode

Worth setting up on the laptop too — `local-big` reasons about the change,
`local-code` writes the diff:

```bash
alias ask-arch='OPENAI_API_BASE="${HEARTH_GATEWAY}/v1" \
  OPENAI_API_KEY="$(cat ~/.hearth-key)" \
  aider --architect --model openai/local-big --editor-model openai/local-code'
```

See `docs/IDES.md` for why this is the mode to reach for.

---

## 4. Zed

Install Zed normally — it edits local files and only calls the gateway host for
inference.

`settings.json`:

```json
{
  "language_models": {
    "openai_compatible": {
      "hearth": {
        "api_url": "http://<LAN-IP>:4000/v1",
        "available_models": [
          { "name": "local-code", "max_tokens": 262144 },
          { "name": "local-chat", "max_tokens": 40960 },
          { "name": "local-big",  "max_tokens": 131072 },
          { "name": "cloud-cheap", "max_tokens": 1048576 }
        ]
      }
    }
  }
}
```

Enter the **`lan`** key through the UI so it lands in the keychain rather than a
dotfile.

Better: let [`zed-litellm`](https://github.com/joby-brentsmith/zed-litellm) write
that block. It reads real context windows from the gateway's `/model/info`,
which avoids hand-maintaining numbers that will drift.

### Where does the code live?

Zed edits files on the machine it runs on, so pick one:

| | Clone to the laptop | Zed SSH remote projects |
|---|---|---|
| Copies of the work | two, synced by git | one, on the gateway host |
| Toolchain needed on laptop | yes | no |
| Works with Studio asleep | yes (minus AI) | no |

SSH remote suits this setup — the gateway host is the machine that's always on — but
cloning is more resilient when you're out.

### Agent profiles

Set up two, per `docs/IDES.md`:

- **explore** — read, search, discuss. No edits, no terminal.
- **build** — full tools.

Not a safety measure. A way of being explicit about which mode you're in.

---

## 5. Optional — your own chat UI

Only if you want a browser chat surface with history **local to this laptop**.
Needs podman or docker.

```bash
scp USER@HOST:<hearth-repo>/client/hearth-webui.sh ~/hearth-webui.sh
chmod +x ~/hearth-webui.sh && ~/hearth-webui.sh up      # http://127.0.0.1:3000
```

Alternative: browse the gateway host's instance and share history across machines.
`scripts/webui.sh up --lan` on the gateway host, or tunnel port 3000.

### Web search

SearXNG is bound to the gateway host's localhost, so it needs forwarding:

```bash
~/hearth-webui.sh tunnel                              # prints the ssh line
ssh -N -L 8888:127.0.0.1:8888 USER@HOST    # leave running
~/hearth-webui.sh up                                  # detects it, wires search
```

Then enable it in Admin Panel → Settings → Web Search — Open WebUI's database
overrides the env vars.

Remember the search **query** leaves the network even though the conversation
does not. Never on a chat involving client data. See `docs/ROUTING.md`.

---

## 6. Off your own network

LAN traffic is plain HTTP. Fine at home, wrong on cafe or hotel wifi. Tunnel:

```bash
ssh -N -L 4000:127.0.0.1:4000 USER@HOST
export HEARTH_GATEWAY=http://127.0.0.1:4000
```

**Never port-forward `:4000` to the internet.** Key auth is not hardening, and a
public LiteLLM holding your provider keys becomes somebody else's budget.

---

## 7. Windows

The `.sh` shim is POSIX shell. Three routes, easiest first:

```bash
scripts/client-setup.sh lan --windows    # prints all three, on the gateway host
```

- **WSL or Git Bash** — the `.sh` works unchanged.
- **Native PowerShell** — `client/hearth-client.ps1` gives the same commands on
  5.1 or 7+. Two gotchas: no `chmod`, so lock the key with `icacls`; and the
  execution policy blocks `$PROFILE` until you set `RemoteSigned`.
- **Nothing installed** — point any OpenAI-compatible tool at
  `http://<LAN-IP>:4000/v1` with the key and a role as the model.

Zed and aider both work on Windows independently of which route you pick.

---

## Troubleshooting

| Symptom | Cause |
|---|---|
| `ai-ping` says UNREACHABLE | Studio asleep, or different network |
| `ai-models` lists nothing | Wrong key, or key not in `~/.hearth-key` |
| A role 400s | It may not exist for this key — `ai-models` shows what does |
| Zed sees no models | `api_url` missing `/v1`, or key entered in the wrong field |
| Zed errors on long files | Context window in `settings.json` overstates the model |
| Web search does nothing | Tunnel dropped, or not enabled in Admin Panel |
| First request very slow | Cold model load on the gateway host; later ones are fast |

Rotate a lost laptop's key on the gateway host with `scripts/create-keys.sh --force`,
then re-run `client-setup.sh` for the machines you keep.
