# Editors: Zed and aider

Two tools, deliberately. They are good at different halves of the work and both
address roles rather than model names, so neither needs touching when a model
changes.

| | aider | Zed |
|---|---|---|
| Where | terminal | editor |
| Unit of work | a diff you approve | inline edits and agent runs |
| Best for | changes you want to review before they land | exploring, refactoring in place |
| Agent | n/a — it always shows you the diff | yes, with restrictable tools |

---

## aider

### Fix the inherited config first

`~/.aider.conf.yml` was written before the gateway existed and names models that
no longer exist. Replace it:

```yaml
# ~/.aider.conf.yml
# Roles, not model names. Requires OPENAI_API_BASE + OPENAI_API_KEY, which
# scripts/aliases.zsh sets.
model: openai/local-code
weak-model: openai/local-chat      # commit messages, summaries — cheap and fast
dark-mode: true
auto-commits: true
map-tokens: 4096
```

`weak-model` matters more than it looks: aider uses it for commit messages and
summarisation. Pointing it at `local-chat` keeps the 30B free for actual work.

### Architect mode — the best fit for this stack

aider can split planning from editing: one model reasons about the change,
another applies it. That maps directly onto your roles.

```bash
aider --architect \
      --model openai/local-big \
      --editor-model openai/local-code
```

`local-big` (`gpt-oss:20b`) reasons, `local-code` (`qwen3-coder:30b`) writes
the diff. Both private; with `OLLAMA_MAX_LOADED_MODELS=1` the second load
evicts the first (ADR 0011). Add it as an alias:

```bash
alias ask-arch='OPENAI_API_BASE="${HEARTH_GATEWAY}/v1" \
  OPENAI_API_KEY="$(_ai_key private)" \
  aider --architect --model openai/local-big --editor-model openai/local-code'
```

### Switching mid-session

```
/model openai/local-big       swap to the reasoning role
/model openai/cloud-cheap     reach for cloud (general key only)
/ask                          question without editing anything
/architect                    toggle architect mode
```

`/ask` is worth the habit — it answers without proposing a diff, which keeps you
deciding what to change.

### Deliberate review

You have `auto-commits: true`, which is convenient and also the setting most
likely to let a change land without you reading it. For anything touching
flagged sensitive code:

```bash
aider --no-auto-commits
```

---

## Zed

### Point it at the gateway

Agent Settings, or directly in `settings.json`. **Agent default is `local-big`
(`gpt-oss:20b`)** — multi-turn write/edit survives better than `local-code`
under Zed's tool list (Ollama Qwen XML parse failures). Keep `local-code` in
the picker for short coding turns.

```json
{
  "agent": {
    "default_model": { "provider": "hearth", "model": "local-big" }
  },
  "language_models": {
    "openai_compatible": {
      "hearth": {
        "api_url": "http://127.0.0.1:4000/v1",
        "available_models": [
          { "name": "local-code", "display_name": "qwen3-coder:30b", "max_tokens": 65536 },
          { "name": "local-chat", "display_name": "qwen3:8b", "max_tokens": 40960 },
          { "name": "local-big",  "display_name": "gpt-oss:20b", "max_tokens": 65536 },
          { "name": "cloud-cheap", "display_name": "gemini-3.5-flash", "max_tokens": 1048576 }
        ]
      }
    }
  }
}
```

On a laptop use the gateway host's LAN address instead of `127.0.0.1`.

Context windows come from each role's `model_info` on the gateway (ADR 0009).
Prefer `zed-litellm` below over hand-editing numbers; it reads `/model/info`.
An overstated window fails at request time with a confusing error.

The API key goes in the UI so it lands in the keychain rather than a dotfile.
Use the `private` key on this machine; `lan` on other machines.

### Let a tool write that block

Zed requires models to be listed by hand, because OpenAI's `/models` endpoint
returns bare IDs with no context windows. LiteLLM's `/model/info` *does* return
that metadata, and [`zed-litellm`](https://github.com/joby-brentsmith/zed-litellm)
queries it and writes correct entries into `settings.json`, backing up first.

Worth re-running after any role change so context windows stay honest.
Default merge keeps hand-tuned fields like `display_name` (concrete Ollama
tags in the picker while API `name` stays the role). Avoid `--replace` /
`-f` unless you intend to wipe those labels.

### On a laptop

Full walkthrough in `docs/LAPTOP.md`. In short — Zed installs normally and edits
local files; only inference comes from the gateway host. Two changes from the block
above:

```json
"api_url": "http://HOST:4000/v1"
```

and use the **`lan`** key rather than `private`.

`zed-litellm` works from the laptop too — point it at the same LAN address and
it writes the model list with correct context windows.

**Where the code lives is a separate question.** Zed edits files on the machine
it runs on, so either:

- clone the repo to the laptop and work normally through git, or
- use Zed's **SSH remote projects** to open a directory on the gateway host directly —
  editing happens over SSH, the model call still goes to `:4000`.

The second keeps one copy of the work and pairs well with the gateway host being the
machine that never sleeps. It also means the laptop needs no toolchain.

If the gateway host is asleep, Zed still opens and edits — you just lose the AI panel
until it wakes. That degrades more gracefully than aider, which needs the
gateway to start at all.

### Agent profiles — the reason Zed is here

Zed's agent has **profiles with configurable tool access**. You can define one
that reads and proposes but cannot apply edits or run commands, and a separate
one that can.

That is the closest thing shipping today to an assistant that helps without
taking over, and it is why Zed earns its place over JetBrains here — JetBrains
only supports chat on local models.

Suggested split:

- **explore** — read files, search, discuss. No edits, no terminal. Use when you
  are trying to understand something.
- **build** — full tools. Use when you already know what you want.

The distinction is not about safety. It is about which mode you are in.

---

## Why two tools, and why this matters

The 2026 research on AI-assisted development is not comfortable reading.
Developers using AI assistance scored **17% lower on comprehension** afterwards,
with the steepest decline among those who fully delegated (Shen and Tamkin,
2026). The framing that stuck is **output up, capability down** — and the
distinction between *atrophy*, losing skills you had, and *foreclosure*, never
building them. Roughly half of programmer actions in LLM-assisted workflows show
identifiable cognitive bias, mostly anchoring on whatever the model proposed
first (Zhou et al., 2026).

Nothing ships to address this. The one paper directly on it —
[Agents That Teach](https://arxiv.org/html/2607.06101) — is a design proposal,
not a product. The measurement is years ahead of the tooling.

So the mitigations here are choices, not features:

- **aider shows a diff and waits.** That is friction, and the friction is the
  point. `/ask` and `--no-auto-commits` add more when you want it.
- **Zed's explore profile can't edit.** Reading and discussing without the option
  to apply keeps you deciding.
- **Local models are weaker, and that is quietly protective.** A model that
  cannot one-shot the answer keeps you in the loop — the opposite of how model
  quality is usually discussed.
- **Architect mode separates deciding from typing**, which keeps the design
  decision visible instead of buried in a diff.

None of this is about distrusting the output. It is about noticing when you have
stopped thinking, which by definition is not something you notice.

---

## Other editors

Not recommended here, recorded so the question does not come round again.

| Editor | State |
|---|---|
| JetBrains | Native LiteLLM support, free tier, but **chat only** on local models — no agent, no next-edit |
| VS Code + Continue | Works fully, but an extension rather than built in |
| Cursor | Not used here — rejects non-HTTPS base URLs; agent mode unreliable with custom endpoints |
