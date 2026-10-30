# ADR 0015 — A silent MLX stall fails once, and the runner is killed

**Date:** 2026-10-31
**Status:** accepted
**Adjusts:** the `OLLAMA_KEEP_ALIVE=-1` line of ADR 0011

## Context

On 2026-10-30 a Zed turn to `local-big` (`qwen3.6:35b-mlx`, context 65536,
`ollama ps` size 26 GB) produced no tokens. The runner's graphics footprint
was 38–43 GB, against a ~48 GB GPU ceiling, and a sample showed `mlx_eval`
blocked in `MetalAllocator::malloc`. Ollama returned no error. The gateway
waited 120 s and retried twice, so one click lasted about six minutes and
then 500'd as a connection timeout. `local-big` has no fallback, so the
prompt stayed local. That part is correct.

Zed's cancel left the socket open. The single runner kept the GPU, so a
direct Ollama attempt queued behind it. `ollama stop` sat on "Stopping…".
The process on port 11434 was Ollama.app. The launchd service that carries
the memory knobs was crash-looping with "address already in use."

An earlier load at native 256K stayed resident for eight days because
keep-alive was `-1`. Later 64K requests do not shrink a context Ollama has
already allocated.

## Decision

- `local-big`: `timeout: 90`, `num_retries: 0`. One attempt. The global
  router default stays 2 retries / 120 s for the other roles. No cloud
  fallback is added.
- `OLLAMA_KEEP_ALIVE=10m` in `scripts/install-ollama-service.sh`. An idle
  model unloads. A stuck in-flight eval does not; that is the watchdog.
- Serve Ollama from the launchd plist, not Ollama.app, so `q8_0` KV cache,
  one loaded model, and the keep-alive actually apply. Measure the
  footprint after the switch. Do not assume `q8_0` took effect.
- `scripts/mlx-watchdog.sh`, launchd every 15 s. Kill the runner when its
  footprint is ≥ 38 GB, it is at least 45 s old, a connection has received
  a prompt (≥ 10 KB) and sent 0 bytes, and that has been true for 30 s.
  `ollama stop` is not used; it wedged. `kill`, then `kill -9`.

## Consequences

- A hung `local-big` turn returns in about 90 s instead of about six
  minutes. The error is still a timeout. The runner may already be dead
  by then, which frees the slot for the next request.
- A real prefill that is also silent and ≥ 38 GB for 30 s is killed.
- Keep-alive no longer pins a bad first load for days. Switching models
  still evicts, because only one stays loaded.
- Models are unchanged. The 64K 35B fits at ~26 GB. Shrinking it is a
  separate bench, not this fix.

## Rollback

Set `local-big` `num_retries` back to the router default and remove its
`timeout`. Set `OLLAMA_KEEP_ALIVE=-1` and re-run
`scripts/install-ollama-service.sh --apply`. `scripts/mlx-watchdog.sh --remove`.
