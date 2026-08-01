# ADR 0001 — Inherited state, captured before changes

Date: 2026-08-01
Status: accepted (record only)

## Context

State of the stack before ai-stack existed. Recorded verbatim so every later change
has a baseline and a rollback target.

## What was running

Host: Mac Studio M4 Max, 64 GB, macOS 26.4, 192.168.50.154

- Ollama 0.32.5, models at `/Users/Shared/Ollama/models` (63 GB)
  - `llama3.3:70b` (42 GB), `qwen2.5-coder:32b` (19 GB), `qwen2.5-coder:7b` (4.7 GB),
    `nomic-embed-text` (274 MB)
  - listening on `*:11434` — all interfaces, no auth
- LiteLLM 1.85.1 on `*:4000` under launchd
  - `com.colinnevin.litellm.plist` → `~/.config/litellm/run-litellm.sh`
  - config at `~/.config/litellm/config.yaml`
- `com.user.setollamamodels.plist` sets `OLLAMA_MODELS` at login
- aider 0.85.2, `~/.aider.conf.yml` → `ollama_chat/qwen2.5-coder:32b`,
  weak model `qwen2.5-coder:7b`

### Inherited config.yaml

```yaml
model_list:
  - model_name: local-ollama
    litellm_params:
      model: ollama/qwen2.5-coder:32b
      api_base: http://127.0.0.1:11434
  - model_name: cloud-fallback
    litellm_params:
      model: gemini/gemini-3.5-flash
      api_key: os.environ/GOOGLE_API_KEY
router_settings:
  fallbacks: [{"local-ollama": ["cloud-fallback"]}]
  num_retries: 2
  timeout: 120
general_settings:
  master_key: "<hardcoded>"
```

### Inherited shell aliases

```sh
alias ask='aider --model anthropic/claude-sonnet-4-6'
alias ask-local='aider --model ollama_chat/qwen2.5-coder:32b'
alias ask-fast='aider --model ollama_chat/qwen2.5-coder:7b'
alias ask-llama='aider --model ollama_chat/llama3.3:70b'
```

## Problems identified

1. **Fallback leaked to cloud.** `local-ollama → cloud-fallback` meant any Ollama
   timeout, cold load or restart silently sent the prompt to Google. On a privacy
   boundary a silent fallback is a leak, not resilience. Highest-severity finding.

2. **Ollama open on the LAN.** `*:11434`, no auth. Any device on 192.168.50.0/24
   could use the GPU directly, bypassing the gateway and every routing rule.

3. **Aider bypassed the gateway.** All four aliases addressed Ollama or Anthropic
   directly, so no spend tracking, no logging, no enforceable boundary.

4. **Wrong Ollama prefix.** Config used `ollama/`; LiteLLM recommends `ollama_chat/`.
   The completion-API prefix causes tool-call loops and dropped context. The aider
   config already used `ollama_chat/` — the gateway was the inconsistent one.

5. **Model names hardcoded in aliases.** No single swap point.

6. **Tags not pinned.** Mutable Ollama tags could change weights under a benched role.

7. **`master_key` hardcoded** in a file destined for git.

8. **Stale cloud model.** `claude-sonnet-4-6` is a generation behind `claude-sonnet-5`.

9. **RAM oversubscribed.** 70B (42 GB) + 32B (19 GB) = 61 GB of 64. Cannot coexist.

## Decision

Keep the working parts — launchd supervision, Gemini as a cheap tier, aider's
`ollama_chat/` choice, the master key — and rebuild routing around roles, scoped
keys, and local-only fallbacks.

## Rollback

Restore `~/.config/litellm/config.yaml` from the block above, reload the launchd
agent, and restore the four aliases in `~/.zshrc`.
