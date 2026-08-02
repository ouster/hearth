# ADR 0003 — Bind Ollama to localhost

Date: 2026-08-02
Status: accepted

## Context

Ollama listened on `*:11434` — all interfaces, no authentication of any kind.
Any device on the LAN subnet could use the GPU, enumerate the model list, and
send arbitrary prompts.

That is not merely an exposure. It is a hole straight through the entire design:
every routing rule, spend cap and privacy scope in this stack is enforced by the
gateway, and `:11434` is a way around all of them. The `private` key cannot reach
a cloud model, but nothing stopped a LAN client reaching Ollama directly and
skipping the gateway altogether.

Ollama has no authentication to enable. The only control available is which
interface it binds to.

## Decision

Bind Ollama to `127.0.0.1:11434` via `OLLAMA_HOST`, set at login by
`~/Library/LaunchAgents/com.user.setollamahost.plist` — the same pattern already
used for `OLLAMA_MODELS`.

LAN clients go through the gateway on `:4000` with the `lan` key, which grants
local roles plus `cloud-cheap` and carries a spend cap.

## Consequences

- **Breaking for other machines.** Anything pointed at `http://<LAN-IP>:11434`
  stops working until repointed at the gateway. `scripts/lock-ollama.sh --apply`
  prints the exact client configuration.
- LAN traffic is now logged, capped and scoped, and addresses roles rather than
  model names — so swapping a model no longer requires touching other machines.
- **There are two controls, and the app's wins.** macOS GUI applications do not
  inherit shell environment, so Ollama added an in-app "Expose Ollama to the
  network" toggle that overrides `OLLAMA_HOST`. Setting the variable alone
  changes nothing for the menu-bar app — the toggle must be turned off in
  Settings, and Ollama fully quit and reopened. The launchctl variable still
  governs `ollama serve` launched from a terminal, so both are worth setting.
  This cost a round trip to discover; `scripts/lock-ollama.sh` now says it up
  front.
- The gateway becomes a single point of failure for LAN inference. Break-glass is
  documented in `docs/RUNBOOK.md`: on this machine, `127.0.0.1:11434` still works
  directly.

## Verification

`scripts/lock-ollama.sh --check` reports the binding, what is listening, and
whether the LAN address answers. `scripts/preflight.sh` and
`scripts/healthcheck.sh` both check LAN reachability and warn while it is open.

## Rollback

`scripts/lock-ollama.sh --revert`, then restart Ollama.app.
