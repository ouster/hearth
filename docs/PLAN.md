# Build status

Last updated: 2026-08-02

**Not the source of truth.** For current reality read, in this order:
`litellm/config.yaml` → `docs/MODELS.md` → `docs/ARCHITECTURE.md` → `docs/RUNBOOK.md`.
This file tracks progress only. The original plan is preserved in
`docs/decisions/0001-inherited-state.md`.

## Where things stand

| Phase | State |
|---|---|
| 0 — capture inherited state | done — ADR 0001 |
| 1 — repo scaffold | done |
| 2 — role-based gateway config | **deployed and serving** |
| Postgres via Podman on :5433 | done, running |
| Virtual keys | done — four created, scoped |
| Leak test | **passing** — boundary enforced, not just documented |
| Aliases switched to roles | done |
| 3 — lock Ollama to localhost | **done** — LAN unreachable, verified |
| llama3.3:70b retired | done — ADR 0004. 440 s to 5 s |
| 4 — bench harness | done and run — found the local-chat verbosity problem |
| local-chat thinking disabled | done — ADR 0006. 29.7 s to 5.1 s |
| digest pinning | recorded + drift-checked (not enforceable in Ollama) |
| 5 — auto-update pipeline | deferred |
| 6 — Open WebUI | **done** — chat UI on :3000, private-scoped, local-chat default |
| Web search via SearXNG | **done** — opt-in per message, :8888, verified end to end |
| `usage.sh` visibility | done — role, tier, model, tokens, LOCAL/CLOUD split |
| 7 — verification tooling | done — preflight, deploy, healthcheck, audit |

## What changed from the original plan

- **Frontier providers: three, not one.** Fireworks was the original default purely
  because it was the provider first mentioned. Verified 2026-08-01, it is the
  dearest: $3.30/$16.50 versus $3.00/$15.00 from both OpenRouter and Moonshot
  direct. OpenRouter is now primary — one key, day-zero access to new models.
- **`cloud-code` is dormant by choice.** No Anthropic API key. A Console key bills
  separately from a Claude subscription, and Claude Code already runs on the
  subscription, so the gateway route only earns its place if aider, Cursor or the
  laptop need Claude.
- **Four keys, not three.** Added `lan-cloud` so the laptop can reach cloud models
  without widening the everyday `lan` key.
- **Postgres in Podman, not Docker Desktop.**
- **`ask` now defaults to local.** The old `ask` pointed at Anthropic with no key
  set, so it was broken. The safe default on a privacy-first stack should be the
  private one; cloud is now the explicit reach (`ask-cloud`).
- **Deployment does not touch launchd.** `run-litellm.sh` already loads
  `~/.config/litellm/config.yaml`, so that path becomes a symlink into the repo.
  Rollback is one `mv`.

## Bugs the harness caught before deploy

Kept as a record of why the tooling exists.

1. **Fallback leak** in the inherited config — `local-ollama → gemini` meant any
   Ollama timeout silently sent the prompt to Google.
2. **`ollama/` vs `ollama_chat/`** — the completion-API prefix causes tool-call
   loops and dropped context.
3. **Preflight reported a fake leak** when PyYAML was missing. A check that cannot
   run must never look like a finding; ERROR and FAIL are now distinct exit codes.
4. **Env check read the wrong environment** — it consulted the interactive shell,
   but launchd only sources `~/.config/litellm/env`. A false green.
5. **Model presence check was tag-naive** — `nomic-embed-text` did not match
   `nomic-embed-text:latest`.
6. **launchd detection** used `launchctl list | grep`, which misses gui-domain
   agents; it reported "not loaded" while the gateway was serving traffic.
7. **`db.sh` went missing** from disk and nothing noticed. Preflight now verifies
   every referenced script exists.
8. **Leak test could false-pass** — it probed a dormant role, where "model not
   found" also returns 4xx. Now probes a live cloud role and adds a positive
   control, since a merely broken key also refuses everything.
9. **`model_info: tier: local`** — `tier` is a real LiteLLM field accepting only
   `free` or `paid`. Pydantic rejected it and LiteLLM logged "ignoring and
   continuing with other deployments", silently dropping EVERY model. The
   gateway started clean, passed readiness, and served nothing.
10. **bash 4 syntax on bash 3.2** — `declare -A` and unguarded `"${arr[@]}"`
    pass everywhere except macOS, which is the only place it runs.
11. **`curl | python - args <<'PY'`** — the heredoc and the pipe both claim
    stdin, so `json.load(sys.stdin)` reads nothing. Symptom is a bogus
    "response was not JSON".
12. **`/key/delete` accepted a token hash and did nothing** — it wants
    `key_aliases`. A silent no-op that looks like success.
13. **Open WebUI env vars were overridden by its database.** Env only seeds a
    fresh DB; the persisted volume kept the first run's settings. `podman exec
    ... env` showed the feature enabled while the UI had it off.

## Next

1. **Re-run `bench.sh`** now that thinking is off, so the recorded numbers
   match reality, then **read the task 03 output.** `gpt-oss:20b` earned `local-big` on
   capacity, not quality — nothing has yet confirmed it reasons well. Task 03
   hides a float-for-currency bug in settlement arithmetic; a model that fixes
   the obvious `range(len())` and misses that is the wrong tool for conveyancing
   work. Syntax checks cannot answer this. It needs a human read.
2. **Record digests after that read**, with `scripts/pin-digests.sh`, so drift
   is detectable from a known-good state rather than an arbitrary one.
3. **Live with it for a week** before building the auto-updater. It is the
   piece most likely to be overbuilt for a problem that turns out to be small.

Optional, when the need arises:

- Enable `cloud-code` if aider, Cursor or the laptop ever need Claude — needs a
  Console API key, which bills separately from the subscription.
- Enable `cloud-frontier` (OpenRouter) for Kimi K3 and day-zero access to new
  models. There is no local K3 at any quantisation.
- A second Open WebUI without search configured, if you want "no web search on
  client work" to be structural rather than remembered.
