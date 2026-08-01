# ai-stack — build plan v1

Status: **awaiting approval**
Date: 2026-08-01
Host: Mac Studio M4 Max, 64 GB, macOS 26.4, 192.168.50.154

---

## Decisions taken

| Question | Decision |
|---|---|
| Home base | Git repo `~/dev/ai-stack` + Claude Project pointing at its docs |
| Goals | Privacy routing, cost control, model-churn resilience, frontier access |
| Auto-update | Discover + bench automatically; **promotion requires approval** |
| Chat UI | Open WebUI in v1 |
| Ollama exposure | Bind to localhost; LAN clients go through the gateway |
| Name | `ai-stack`, not `local-ai-stack` — half the design is cloud |

---

## Current state

Working today:

- Ollama 0.32.5, models under `/Users/Shared/Ollama/models` (63 GB on disk)
- LiteLLM 1.85.1 on `:4000` under launchd, master key auth on
- Existing route: `local-ollama` → `qwen2.5-coder:32b`, fallback `gemini/gemini-3.5-flash`
- aider 0.85.2 with four aliases

Problems this plan fixes:

1. **Aider bypasses the gateway.** All four aliases hit Ollama or Anthropic directly, so
   there is no spend tracking, no logging, and no enforceable privacy boundary.
2. **Ollama is open on the LAN.** `*:11434`, no auth. Any device on 192.168.50.0/24 can
   use the GPU directly and skip every rule below.
3. **Models are named in aliases.** Swapping a model means editing shell config, Cursor
   settings and scripts. Nothing has a single swap point.
4. **Tags are mutable.** `qwen2.5-coder:32b` can silently become different weights on any
   `ollama pull`. Roles are not pinned.
5. **RAM budget is oversubscribed.** `llama3.3:70b` (42 GB) + `qwen2.5-coder:32b` (19 GB)
   = 61 GB of a 64 GB machine. They cannot coexist; switching roles forces an eviction and
   a cold reload. Needs a `keep_alive` policy, and 70B probably needs replacing.

---

## Target roles

Concrete models live **only** in `litellm/config.yaml` and `docs/MODELS.md`.

| Role | Initial backing | Notes |
|---|---|---|
| `local-fast` | `qwen2.5-coder:7b` | quick edits, autocomplete |
| `local-code` | `qwen2.5-coder:32b` | default coding model, ~19 GB |
| `local-big` | `llama3.3:70b` | **flagged** — 42 GB for dated quality; a ~30B MoE with 256K context is likely better *and* smaller. Bench before keeping. |
| `local-embed` | `nomic-embed-text` | local RAG |
| `cloud-cheap` | Gemini Flash | existing fallback, keep |
| `cloud-code` | Claude (current Sonnet) | hard coding / agentic |
| `cloud-frontier` | Kimi K3 via Fireworks | $3.30/M in, $16.50/M out — expensive, use deliberately |

## Virtual keys

Privacy enforced by key scope, so the wrong route is impossible rather than discouraged.

| Key | Can reach | Used by |
|---|---|---|
| `private` | `local-*` only | conveyancing work, Open WebUI default, anything touching client data |
| `general` | all roles | Cursor, Claude Code, aider on non-sensitive repos |
| `lan` | `local-*` + `cloud-cheap` | other machines on 192.168.50.0/24, tight budget |

---

## Phases

### Phase 0 — capture and back up
Read the existing launchd plist and LiteLLM config, commit them verbatim as
`docs/decisions/0001-inherited-state.md` before changing anything. `git init`.
**Needs from you:** the two files (command below).

### Phase 1 — repo scaffold
`CLAUDE.md`, `AGENTS.md`, `docs/{ARCHITECTURE,ROUTING,MODELS,RUNBOOK}.md`,
`litellm/`, `scripts/`, `bench/`. `.gitignore` for keys; `.gitattributes` for LF.

### Phase 2 — gateway config
Role groups, three virtual keys with budgets, spend tracking, `store_model_in_db`
so promotions can happen via API without a restart. Cost-map auto-sync enabled
(`/schedule/model_cost_map_reload?hours=6`) — prices and context windows stay
current with zero manual work.

### Phase 3 — lock down and rewire
`OLLAMA_HOST=127.0.0.1:11434`, launchd updated. Replace the four aider aliases with
role-based ones through the gateway. Point Cursor and Claude Code at `:4000`.
Reconfigure LAN machines with the `lan` key.
**Breaking:** other machines stop working until re-pointed. Do this when you have ten minutes.

### Phase 4 — bench harness
`bench/tasks/` seeded with prompts from your actual work (auslaw-mcp, stepup-conveyancing,
shell scripting). Scoring script. Every role pinned to a **digest**, not a tag.

### Phase 5 — auto-update pipeline
Weekly launchd job:
1. Diff Ollama library + Fireworks/OpenRouter model lists against `docs/MODELS.md`
2. Filter to what fits the 48 GB weight budget
3. Stage-pull candidates under a `candidate-` prefix
4. Bench against the incumbent
5. Write `reports/YYYY-MM-DD.md` — ranked, with a one-line promote command
6. Notify; **nothing is promoted without you**

Promotion writes an ADR and re-pins the digest. Rollback is the previous digest.

### Phase 6 — Open WebUI
Local chat UI on the gateway, defaulting to the `private` key so it physically cannot
reach a cloud model. A separate model selector entry exposes cloud roles when you want them.

### Phase 7 — verify
- Healthcheck hits every role and reports latency + first-token time
- **Leak test:** attempt `cloud-code` with the `private` key, confirm rejection
- Confirm LAN access works through the gateway and direct `:11434` is refused
- Confirm cost tracking increments

---

## Risks

| Risk | Mitigation |
|---|---|
| Gateway becomes a single point of failure | LiteLLM fallbacks already configured; runbook documents direct-Ollama break-glass |
| Rewiring breaks a working setup | Phase 0 captures current state; each phase reversible |
| Auto-updater fills the disk | Staging pulls capped, candidates purged after benching |
| Bench is unrepresentative | Tasks seeded from your real repos, not synthetic |
| 70B eviction thrash | `keep_alive` policy; likely retire 70B after Phase 4 |

---

## Open question

Anthropic key location is still unknown — not in your shell env, but `ask` works. It is
either in aider config, a dotenv, or the launchd plist. Phase 0 resolves this. Do not
want to move key handling blind.

## To unblock Phase 0

```bash
{
echo "=== PLIST ==="; ls -1 ~/Library/LaunchAgents/ | grep -i -E 'litellm|ollama'
for p in ~/Library/LaunchAgents/*litellm*.plist ~/Library/LaunchAgents/*ollama*.plist; do
  [ -f "$p" ] && echo "--- $p ---" && sed -E 's/(sk-[A-Za-z0-9_-]+|fw_[A-Za-z0-9_-]+|AIza[A-Za-z0-9_-]+)/<REDACTED>/g' "$p"
done
echo "=== CONFIG ==="; CFG=$(ps -p 4082 -o command= | grep -oE '\-\-config [^ ]+' | cut -d' ' -f2)
echo "config path: ${CFG:-none on cmdline}"
[ -n "$CFG" ] && sed -E 's/(sk-[A-Za-z0-9_-]+|fw_[A-Za-z0-9_-]+|AIza[A-Za-z0-9_-]+)/<REDACTED>/g' "$CFG"
echo "=== AIDER CFG ==="
for f in ~/.aider.conf.yml ~/.aider.model.settings.yml ~/.env; do
  [ -f "$f" ] && echo "--- $f ---" && sed -E 's/(sk-[A-Za-z0-9_-]+|AIza[A-Za-z0-9_-]+)/<REDACTED>/g' "$f"
done
} 2>&1
```
