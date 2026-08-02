# How this compares to other private-AI setups

Read 2026-08-02. Two reference points worth knowing about: one person solving
the same problem from a different angle, and one product solving the piece we
found most annoying.

---

## Vitalik Buterin — "My self-sovereign / local / private / secure LLM setup"

[April 2026](https://vitalik.eth.limo/general/2026/04/02/secure_llms.html).
Near-identical brief: *"what kind of AI setup would we build if we took privacy,
security and self-sovereignty as non-negotiable?"*

### Where we independently landed on the same thing

- **SearXNG** for search, for the same reason — reduce what any single engine
  learns about you.
- **AGENTS.md** as the shared instruction file.
- **Local-first with a deliberate cloud escape hatch.** He hit the same wall we
  did: local models are fine on well-trodden ground and fall apart on hard
  problems. He tried and failed to get Qwen3.5:35B to implement BLS-12-381
  hash-to-point, and sent it to Claude, which one-shotted it. Our `cloud-code`
  role exists for exactly that moment.
- **Roughly the same speed floor.** He says "anything slower than 50 tok/sec
  feels too annoying to be worth it." Our roles run 65–120.

### Where he is ahead — and these are real gaps for us

**1. Sandboxing. We have none.**

He runs LLM work inside [bubblewrap](https://github.com/containers/bubblewrap):
`sbox` in any directory creates a sandbox rooted there, and anything started
inside can only see that directory plus explicit whitelists. Ports, audio and
filesystem are all constrained.

We have nothing equivalent. `aider` and Zed's agent run with full user
permissions — they can read `~/.ssh`, `~/.aws`, every repo on the machine, and
the gateway's own `.env`. Our privacy boundary stops data going to the *wrong
model*. It does nothing about an agent reading the wrong *file*.

**2. A threat model we never wrote down: prompt injection.**

He cites research that roughly **15% of published agent skills contained
malicious instructions**, and a demonstration where summarising a web page
caused an agent to download and execute a shell script. Our stack has SearXNG
wired into a chat UI and agents that read repositories. Both are injection
surfaces. We have thought hard about where data *goes* and not at all about what
untrusted content might *make the agent do*.

**3. Human confirmation as a firewall.**

His messaging daemon can read messages and send only to himself autonomously.
Sending to anyone else requires explicit confirmation. His framing is the one
worth stealing:

> the new "two-factor confirmation" is that the two factors are the human and
> the LLM ... the hope is that humans and LLMs fail in distinct ways

We have `--no-auto-commits` and Zed's tool-restricted profiles, which are the
same instinct applied only to code. Nothing gates an action with consequences.

**4. A local `world_knowledge` corpus.**

A Wikipedia dump plus manuals for things he cares about, so questions answerable
locally never reach a search engine. For conveyancing that would be legislation
and practice notes — the queries most worth not leaking. Our `local-embed` role
exists and indexes nothing.

### Where we are ahead

**Multi-machine access.** He dismisses the DGX Spark partly because *"you have to
figure out the networking details of how to connect to it from your actual work
device"*. That is precisely what our gateway plus scoped keys plus client shim
solves. His setup is one-machine; ours serves laptops with per-device keys,
spend caps and revocation.

**Structural privacy at a different layer.** His isolation is process-level
(sandbox). Ours is route-level (key scope). They fail differently and are
complementary rather than competing:

| Threat | Sandbox | Key scope |
|---|---|---|
| Agent reads a file it shouldn't | **caught** | not caught |
| Prompt sends client data to a cloud model | not caught | **caught** |
| Compromised client machine | partly | **caught** — key is scoped |
| Malicious skill exfiltrates via curl | **caught** | not caught |

We have one column. He has the other. Having both is the correct answer.

**Measurement.** He reports tok/s per hardware. We bench roles on real tasks and
record the decision. His post is explicitly a starting point, not a finished
product — he says so in a warning at the top.

**Model indirection.** He swaps models by hand through llama-swap; we address
roles, so nothing downstream changes.

### One tooling disagreement worth noting

He moved from Ollama to `llama-server` + `llama-swap`, because **Ollama could
not fit Qwen3.5:35B on his GPU and llama-server could**. That is a real
efficiency difference, not tribal preference. On 64 GB unified we are not
memory-pressed at 37.5 GB resident, so it has not bitten us — but if a future
role does not fit, that is the first thing to try before buying hardware.

---

## Routerly — the database-free gateway

[github.com/Inebrio/Routerly](https://github.com/Inebrio/Routerly), AGPL-3.0.
Directly addresses the thing we found most irritating.

### What it does that LiteLLM does not

| | Routerly | LiteLLM (ours) |
|---|---|---|
| Database | **none** — JSON in `~/.routerly/` | Postgres + Prisma, 64 tables |
| Native Anthropic `/v1/messages` | **yes** | no — translates to OpenAI format |
| Per-project tokens + budgets | yes | yes (virtual keys) |
| Per-project model list | yes | yes |
| Routing policies | 9, including LLM-picks-the-model | static fallbacks |
| Provider breadth | 8 | 100+ |
| Maturity | v0.1.5, 43 stars, 3 contributors | widely deployed |

**The interesting unlock is native Anthropic format.** Claude Code is currently a
documented exception in our stack because LiteLLM only speaks OpenAI shape.
Routerly handles `/v1/messages` natively, so Claude Code could route through the
gateway and gain spend tracking and logging. That is a real capability, not a
tidiness argument.

### Why we are not switching yet

- **v0.1.5, one release, three contributors, 43 stars.** This is pre-1.0
  software that would hold our provider keys and enforce our privacy boundary.
  LiteLLM's 64 tables are ugly; ugly is not the same as risky.
- **The cost of switching is the verification, not the config.** The leak test,
  fallback audit, digest pinning and every script touching `/key/*` would need
  redoing and re-proving. That is the expensive part, and it buys removing
  something that currently runs in a container we never look at.
- **AGPL plus a commercial-licensing address** is an open-core shape. Worth
  watching whether the free tier narrows.

Revisit at 1.0, or the first time Postgres actually causes a problem rather
than merely offending.

---

## What we should actually do about this

In rough priority. Nothing here is urgent; the sandboxing one is the only
genuine hole.

1. **Sandboxing for agent work.** The clearest gap. On macOS `sandbox-exec` is
   deprecated but functional; containers or a dedicated user account are
   alternatives. Even scoping aider to the repo directory would be an
   improvement on nothing.
2. **Write down a prompt-injection threat model.** We have web search feeding a
   chat UI and agents reading repos, and have never asked what untrusted content
   could make them do.
3. **Confirmation gates for consequential actions.** Currently only `git commit`
   qualifies, which is why this has not hurt. It would matter the moment
   anything in this stack can send an email or move money.
4. **`world_knowledge` for conveyancing.** Legislation and practice notes
   indexed locally via `local-embed`, so the queries most worth not leaking
   never reach SearXNG.
5. **Note llama-server** as the first thing to try if a model does not fit,
   before assuming the hardware is the limit.

The honest summary: **we built the routing and governance layer well, and the
isolation layer not at all.** Vitalik built the isolation layer and skipped the
routing. Neither is complete.
