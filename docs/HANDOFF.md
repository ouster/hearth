# Handoff: ADR 0048, `main-brain` default everywhere

Written 2026-11-14 on the 48 GB laptop (a dual machine: its own oMLX on
`:1234`, a tunnel to the 64 GB Mac on `:1235`). For the next person or AI
agent in a clone of this repo. Read `CLAUDE.md` first, then
`docs/decisions/0048-main-brain-default-everywhere.md`.

## State

- **Decided:** `main-brain` is the resident on 64 GB and 48 GB.
  `coding-brain` is a swap role on 64 GB only. `deep-brain` is unchanged.
  A laptop loads the host's swap roles with `hearth-load` over an ordinary
  SSH login (`HEARTH_SSH_ADMIN`), never the tunnel key.
- **Changed, not committed** when this was written: 22 files plus ADR 0048
  and this file. `git status` shows them.
- **In `git stash` (top entry):** the operator's earlier edits to
  `README.md`, `docs/IDES.md`, `docs/LAPTOP.md` and `docs/MCP.md`. They were
  a broken find-and-replace. Drop the stash when the operator agrees.

## Checked on the laptop

| Check | Result |
|---|---|
| `scripts/preflight.sh` | 38 pass, 4 fail, 1 warn. The `roles.tsv` failures are gone; the 4 are older (below) |
| `HEARTH_RAM_GB=64 scripts/preflight.sh` | resolves `main-brain=resident coding-brain=swap deep-brain=swap` |
| `bash -n` and `zsh -n` on every edited script | clean |
| `scripts/demand-load.sh coding-brain up` on 48 GB | refuses, exit 2 |
| `hearth-load` with a bad role, a bad action, no `HEARTH_SSH_ADMIN` | refuses each |
| `ask` resident lookup in `scripts/aliases.zsh` | fixed. It printed "no resident role" before, because `ROOT` was unset in a shell |

## Not checked

No model was loaded or unloaded. These need the 64 GB Mac:

1. Pull, then `scripts/omlx.sh up`. Expect `resident role main-brain (3 slot(s), ctx 262144)`.
2. `scripts/zed-sync.sh`, then `scripts/healthcheck.sh`. Expect the thinking probe on `main-brain`.
3. `scripts/demand-load.sh coding-brain up`. Expect `loaded`, and 1 slot.
4. `scripts/demand-load.sh coding-brain down`. Expect `restored main-brain`, and 3 slots.
5. `scripts/demand-load.sh deep-brain up` while `coding-brain` is in, then `down`. Expect `restored coding-brain`.

Then on the laptop:

1. Above the hearth block in `~/.zshrc`: `export HEARTH_SSH_ADMIN=<user>@<64 GB Mac>`. Set `HEARTH_REMOTE_ROOT` if the repo there is not `~/dev/hearth`.
2. `client/install-client.sh --dual`. The installed `~/.hearth-client.sh` is from 2026-11-10.
3. In a new shell: `hearth-load coding-brain up`, then `down`. Then `coding-brain-remote` for one aider turn.
4. `scripts/zed-sync.sh`. The laptop's Zed still has `main-brain` at 131072 and a `local-edit` label.

A laptop is a cloud-assistant machine for secrets: never read `~/.hearth-key`,
`~/.hearth-gemini-key` or `~/.ssh/hearth_tunnel` (`CLAUDE.md`).

## Open problems, not part of ADR 0048

| # | Problem | Where |
|---|---|---|
| 1 | The 48 GB row (`262144 × 3`) is not benched on 48 GB hardware. One 200k prompt peaked at 40.0 GB on the 64 GB host, which is the 48 GB ceiling. Bench it and set the row to what fits (rules 5, 7) | `config/roles.tsv`, `docs/MODELS.md` → *Tiers* |
| 2 | Weight pins fail on the laptop. The fast check compares file count and mtime, which differ by download. `main-brain` is also about 490 MB smaller here than recorded: run `scripts/pin-digests.sh --check --deep`. `pins/digests.tsv` holds a stale second `main-brain` row | `scripts/pin-digests.sh`, `pins/digests.tsv` |
| 3 | Docs reference `scripts/batch.sh`, `scripts/nodes.sh` and `scripts/tag-docs.sh`, which do not exist | preflight → *Repo integrity* |
| 4 | `/v1/models` lists every role, loaded or not, and an unloaded name can be answered by the loaded role. Without `HEARTH_SSH_ADMIN` the laptop cannot tell. A loaded-state check for a sub-key would close this | `client/hearth-client.sh` → `_hearth_swap_remote` |
| 5 | `client/hearth-client.ps1` has no `coding-brain` or `hearth-load` command | Windows client |
| 6 | The benches measure cold 30K prompts at 3 slots. A one-person Cline session is one slot with a long cached prefix. A bench of that shape would inform the next role choice | `bench/`, `scripts/concurrency-bench.sh` |
| 7 | Preflight does not check that the docs name the resident that `roles.tsv` resolves to. That check would have caught the broken edit | `scripts/preflight.sh` |
| 8 | `README.md` repeats most of `docs/IDES.md`. `docs/PLAN.md`, `docs/MIGRATION-LMSTUDIO.md`, `docs/COMPARISON.md` and `docs/SUMMARY-EMAIL.md` describe the removed gateway | docs |

Workflow stays as in `CLAUDE.md`: plan, the operator refines and approves, then build.
