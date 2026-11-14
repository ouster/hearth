# Handoff: ADR 0049, sub-key swap over the tunnel

Written 2026-11-14. Read `CLAUDE.md`, then
`docs/decisions/0049-subkey-tunnel-swap.md` (and 0048 for the resident flip).

## State

- **Decided:** `hearth-swapd` on host `127.0.0.1:1236` accepts a laptop
  sub-key, runs `demand-load.sh` with the host token. Tunnel forwards
  `:1236` as well as oMLX. `HEARTH_SSH_ADMIN` is fallback.
- **Also in tree:** ADR 0048 (`main-brain` resident everywhere).

- **Review fixes, same day, not committed when written:**
  - A tunnel installed before ADR 0049 still serves oMLX. Only `hearth-load`
    needs the `:1236` forward, and says what to run when it is missing.
  - `hearth-load` reports a refusal from the host as a refusal. It uses
    `HEARTH_SSH_ADMIN` only when swapd does not answer or has no forward.
  - `scripts/demand-load.sh <role> down` prints `not-loaded` and changes
    nothing when that role is not loaded and another one is.
  - swapd is threaded, drops an idle connection after 30 s, caps the body
    at 4096 bytes, and no longer holds the host token in its environment.
  - A failed swapd start is a warning in `boot.sh`, `install-autostart.sh
    --check`, preflight and `healthcheck.sh` (new section 9).

## Checked on the 48 GB laptop (swapd on a spare port)

| Check | Result |
|---|---|
| no token, wrong token | 401 |
| host token, `GET /v1/hearth/agent` | 200, `{"agent": "main-brain"}` |
| bad role, bad action, non-object body, 6000-byte body | 400 each |
| `coding-brain up` on 48 GB | 422, refused by `demand-load.sh` |
| a second request while one connection sits idle | answered |
| `OMLX_HOST_TOKEN` in the daemon's environment | absent |
| `scripts/demand-load.sh deep-brain down` with `main-brain` loaded | `not-loaded`, nothing unloaded |
| client against the old tunnel (`:1235` only) | `ai-ping` path accepted; `hearth-load` names the missing forward |

No model was loaded or unloaded. The steps below are still unproven.

## Prove on the 64 GB host

1. Pull. `scripts/install-autostart.sh --apply` (installs `com.hearth.swap`).
2. `scripts/omlx.sh up` then `scripts/hearth-swapd.sh status` → `up 127.0.0.1:1236`.
3. With a sub-key (or host token as Bearer):

```bash
curl -s -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"role":"coding-brain","action":"up"}' http://127.0.0.1:1236/v1/hearth/load
# expect: loaded
curl -s -H "Authorization: Bearer $TOKEN" http://127.0.0.1:1236/v1/hearth/agent
# expect: {"agent": "coding-brain"}
curl -s -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"role":"coding-brain","action":"down"}' http://127.0.0.1:1236/v1/hearth/load
# expect: restored main-brain
```

4. Sub-key must still fail oMLX admin login (blast radius is swap only).
5. Overlap: `coding-brain up`, then `deep-brain up`, then `coding-brain down`
   → `not-loaded` and `deep-brain` stays in. Then `deep-brain down` →
   `restored main-brain`.
6. `scripts/healthcheck.sh` section 9: host token 200, no token 401.
7. `scripts/client-setup.sh --update-keys` so laptop keys get `permitopen` `:1236`.

## Prove on the laptop

1. Pull. Reinstall client (`client/install-client.sh` or `--dual`).
2. `ai-tunnel-stop && ai-tunnel-install`. Expect oMLX and swapd forwards
   (`:1235`+`:1237` when dual; `:1234`+`:1236` on a plain laptop).
3. **Without** `HEARTH_SSH_ADMIN`: `hearth-load coding-brain up` → `loaded`,
   then `down` → `restored main-brain`.
4. `coding-brain-remote` (or `coding-brain`) for one aider turn, then confirm
   agent is `main-brain` again via `curl …/v1/hearth/agent`.

## Open problems (outside 0049)

| # | Problem | Where |
|---|---|---|
| 1 | 48 GB `262144 × 3` unbenched on 48 GB hardware | `roles.tsv`, `MODELS.md` |
| 2 | Weight pins fail across machines; stale second `main-brain` pin row | `pins/digests.tsv` |
| 3 | Docs reference missing `batch.sh` / `nodes.sh` / `tag-docs.sh` | preflight |
| 4 | `client/hearth-client.ps1` has no `hearth-load` / swapd path | Windows client |
| 5 | Benches are cold 30K × 3 slots, not one long Cline prefix | `bench/` |

Workflow: plan, operator refines and approves, then build.
