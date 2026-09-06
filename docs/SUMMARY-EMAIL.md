# hearth — what it solves, what it measured, what's next

Written 2026-08-02. All figures below are measured on the machine, not estimated.

---

## 1. The problems this actually solves

### Privacy that survives forgetting

The real risk was never "I might paste client data into ChatGPT." It was that
in a hurry, on a deadline, the fast option and the safe option are different
buttons — and eventually the wrong one gets pressed.

So the boundary is **structural, not advisory**. Client work uses a `private`
API key whose model list contains no cloud models. Ask it for Gemini and the
gateway returns 403. There is no prompt that talks its way around a key scope.

The inherited config had a fallback rule sending `local → gemini` on any Ollama
timeout. Every slow local response was silently shipping the prompt to Google.
Nothing in the setup would ever have told me. **Across a privacy boundary a
fallback is a leak, not resilience** — `audit-fallbacks.sh` now fails the build
if that pattern reappears.

### One place to change models instead of four

Before: aider pointed at Ollama, Cursor at cloud providers, scripts elsewhere.
Changing model meant editing four things and missing one.

Now everything asks for a **role** — `local-chat`, `local-code`, `local-big`,
`local-embed`, `cloud-cheap`. Concrete model names live in exactly two files.
Swapping a model is one config edit, no client changes. Given how fast this
field moves, that indirection is the single most valuable design choice here.

### Knowing where requests went, and what they cost

`usage.sh --summary` gives the LOCAL vs CLOUD token split — the proportion of
work that never left the machine. Virtual keys carry spend caps that act as
fuses: a leaked key or a runaway overnight loop hits a wall instead of a card.

### Containment for agents (added today)

Coding agents run with full user permissions and read whatever you point them
at. The gateway governs where data goes *on purpose*; it has no jurisdiction
over a compromised agent, which would just call `curl` directly and never touch
LiteLLM at all.

Current state of the field, 2026: prompt injection **cannot be reliably
detected** — adaptive attacks bypass essentially every published defence, and
the best of them still miss around one in ten. OWASP has it as the leading
agentic-AI failure in production, with coding agents driving most of the volume.

So there is nothing to filter. The only thing that works is cutting capability.
`scripts/sandboxed.sh` runs an agent with egress denied to everything except
the gateway. It read a secret? Fine — there's no channel to send it down.

Verified on macOS 26.4, 10 checks passed. It proved itself within seconds of
first use: aider's startup call to pypi.org was refused by the sandbox.

**Deliberately not solved:** reads stay unrestricted (restricting them breaks
every language runtime), and an agent can still corrupt the repo it was invited
into. That second one is handled by committing before a session and reading
`git diff` after — a workflow habit, not a control.

---

## 2. Routerly comparison

[github.com/Inebrio/Routerly](https://github.com/Inebrio/Routerly), AGPL-3.0.
It targets the exact thing that is most annoying about the current setup.

| | Routerly | LiteLLM (what I run) |
|---|---|---|
| Database | **none** — JSON files | Postgres + Prisma, 64 tables |
| Native Anthropic `/v1/messages` | **yes** | no — OpenAI shape only |
| Per-project tokens + budgets | yes | yes (virtual keys) |
| Routing policies | 9, incl. LLM-picks-the-model | static fallbacks |
| Providers | 8 | 100+ |
| Maturity | v0.1.5 · 43 stars · 3 contributors | widely deployed |

**The genuine unlock is native Anthropic format.** Claude Code is currently a
documented exception in my stack because LiteLLM only speaks OpenAI shape.
Routerly handles `/v1/messages` natively, so Claude Code could route through
the gateway and pick up spend tracking and logging. That is a real capability
gain, not a tidiness argument.

**Why I am not switching:**

- v0.1.5, one release, three contributors. This is pre-1.0 software that would
  hold my provider keys and enforce my privacy boundary. LiteLLM's 64 tables
  are ugly; **ugly is not the same as risky.**
- The cost of switching is the *verification*, not the config. Leak test,
  fallback audit, digest pinning, every script touching `/key/*` — all would
  need redoing and re-proving. That is the expensive part, and it buys removing
  a container I never look at.
- AGPL plus a commercial-licensing contact is an open-core shape. Worth
  watching whether the free tier narrows.

Revisit at 1.0, or the first time Postgres causes an actual problem rather than
merely offending my sense of proportion.

---

## 3. Token speed on a 64 GB Mac — the counter-intuitive part

### Throughput is not the number that matters

Benched three models across four fixed tasks, through the gateway:

| Model | tokens emitted | wall clock | avg tok/s |
|---|---|---|---|
| `qwen3-coder:30b` | 1,218 | 11.2 s | 108.8 |
| `gpt-oss:20b` | 4,466 (3.7x) | 47.6 s | 93.8 |
| `qwen3:8b` (thinking on) | 13,840 (11.4x) | 181.4 s | 76.3 |

Throughput barely moves — **65–120 tok/s across everything**, because the
machine is memory-bandwidth bound. The 8B model is not meaningfully faster per
token than the 30B one.

**Wall clock is set by how many tokens a model emits, not how fast it emits
them.** The smallest model was the slowest overall, by 16x, because it is a
hybrid reasoning model that thinks out loud by default. On one task it spent
**100 seconds and 7,548 tokens** where the coding model took 1.6 s and 192
tokens — forty times the output for the same question.

Fix: Ollama's `think: false` parameter. `local-chat` went from **2,370 tokens /
29.7 s to 386 tokens / 5.1 s** through the gateway. From slowest role to
fastest.

Worth noting I got this wrong twice and measurement corrected me both times. I
doubted `think: false` would work — it did. I was confident `/no_think` in the
prompt would work — it was silently ignored, 2,236 tokens before and 2,261
after.

### Residency beats model quality

The old `local-big` was llama3.3:70b at 42 GB. Cold, through the gateway:

| Role | Model | Time to first reply |
|---|---|---|
| `local-code` | qwen2.5-coder:32b | 29 s |
| `local-big` | **llama3.3:70b** | **440 s** |
| `cloud-cheap` | gemini-3.5-flash | 2 s |

Seven and a half minutes. Not because the model is slow — because at 42 GB it
could not stay resident alongside anything else, so every switch meant
reloading 42 GB from disk. Replaced with `gpt-oss:20b`: **440 s → 5 s.** Not a
faster model, a resident one.

### The real memory ceiling is not 64 GB

macOS caps GPU-accessible unified memory at ~75% above 36 GB — so **~48 GB on a
64 GB machine**, not 64. I had ~54 GB written in the docs and it was wrong.

| | Old set | Current set |
|---|---|---|
| Weights resident | 65.7 GB (impossible) | **37.5 GB** |
| Against ceiling | ~48 GB | ~48 GB |
| Disk | 63 GB | ~37 GB |

Current: `qwen3:8b` 5.2 GB + `qwen3-coder:30b` 19 GB + `gpt-oss:20b` 13 GB +
`nomic-embed-text` 0.3 GB. All four stay loaded; switching roles evicts nothing.

**MoE models are what make this work.** `qwen3-coder:30b` is 30B parameters but
activates ~3B per token, so it runs at roughly 7B speed while fitting in 19 GB.

### On switching to llama-server

Looked at it after seeing Vitalik Buterin's writeup. **Expected saving: about
zero.** His gain came from a hard VRAM wall on a discrete 24 GB GPU, where a
model either fits or collapses to CPU offload. Unified memory has no such
cliff, and Ollama on Apple Silicon now runs on MLX — Apple's own framework for
this architecture. Cost would be ~15 scripts and ~60 call sites, to probably go
slower. Not doing it.

---

## 4. What's left

1. **Audit untrusted MCP servers** — the one remaining unknown. Fetches from the
   open web, sits next to real client data, nobody has asked what tools it hands
   a model.
2. **Re-bench with thinking off** and actually *read* the task 03 output.
   `gpt-oss:20b` earned `local-big` on capacity, not quality — nothing has yet
   confirmed it reasons well. Task 03 hides a float-for-currency bug in
   money arithmetic. A syntax check cannot answer that; it needs a human.
3. **Record model digests** from a verified state, so drift is detectable.
4. **Local reference corpus** via `local-embed`, so the queries most worth
   not leaking never reach a search engine at all.
5. **Confirmation gates** — costs nothing today because nothing in the stack can
   send mail or move money. Matters the day something can.

### Sharing the repo

Close. No secrets in any tracked file, and no hardcoded home paths in
executable code — 68 uses of `$HOME` instead. What remains is naming: a LAN IP
as a default in the client scripts, a personal launchd label, business-specific
rules in the agent instructions, and no LICENSE. Roughly half a day.

One item there is a real bug rather than cosmetic: `healthcheck.sh` probes a
hardcoded LAN address to confirm Ollama is *not* reachable. On any other
machine that address is unreachable anyway, so the check passes and reports the
hole closed on a box where it may be wide open. Same false-pass shape as the
leak test bug — unreachable and secure produce identical output.

---

## The pattern worth keeping

Nearly every real problem here was found by measurement, not reasoning:

- The fallback leak — found by reading config, not by it failing.
- `model_info: tier: local` — a valid-looking field that made LiteLLM silently
  drop **every model** while still passing its own readiness check.
- The leak test that passed against a dormant model, where "model not found"
  also returns 4xx. A broken key and a perfectly scoped key looked identical.
- The 70B — retired on a 440-second measurement, not on an opinion about 70B
  models.
- `/no_think` — confidently predicted to work, silently ignored.

The recurring shape: **a check that cannot run must never look like a check
that passed.** Preflight now separates ERROR (couldn't run) from FAIL (real
problem), and every security test pairs a positive control with the negative
one. That single distinction has caught more genuine problems than any
individual feature in the stack.
