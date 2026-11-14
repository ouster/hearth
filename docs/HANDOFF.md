# Handoff: ADR 0049, sub-key swap over the tunnel

Written 2026-11-14. Read `CLAUDE.md`, then
`docs/decisions/0049-subkey-tunnel-swap.md` (and 0048 for the resident flip).

## State

- **Decided:** `hearth-swapd` on host `127.0.0.1:1236` accepts a laptop
  sub-key, runs `demand-load.sh` with the host token. Tunnel forwards
  `:1236` as well as oMLX. `HEARTH_SSH_ADMIN` is fallback.
- **Also in tree:** ADR 0048 (`main-brain` resident everywhere).

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
5. `scripts/client-setup.sh --update-keys` so laptop keys get `permitopen` `:1236`.

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
