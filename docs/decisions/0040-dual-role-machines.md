# ADR 0040 — One machine can be a host and a client

**Date:** 2026-11-08
**Status:** accepted by the operator 2026-11-08.

## Context

Hearth split machines into one host (oMLX on `127.0.0.1:1234`) and laptops
(an SSH tunnel to that host on their own `127.0.0.1:1234`). A laptop with
enough RAM can run its own brain too. This 48 GB laptop already ran oMLX
for `edit-brain` on another port. Under the old split, the two cannot share
1234.

## Decision

- **A machine's own oMLX is always on `127.0.0.1:1234`.** The sandbox
  (`sandboxed.sh`), the host scripts, the editor configs and the docs all
  mean "this machine's brain" when they say 1234. Nothing there changes.
- **On a dual machine the tunnel moves:** oMLX → `127.0.0.1:1235`, WebUI →
  3001, SearXNG → 8889 (`HEARTH_DUAL=1` in the client). Laptop-only
  machines keep the tunnel on 1234; existing laptops change nothing.
- **Command names:** on a dual machine, `ask`, `main-brain`, `ask-arch`,
  `ask-deep` and `deep-brain` come from `scripts/aliases.zsh` (its own
  brain). The client's versions get a `-remote` suffix. The client's
  `HEARTH_URL` is renamed `HEARTH_TUNNEL_URL`, so sourcing both files in
  one shell cannot cross them.
- **Two installers.** `scripts/install-host.sh [--check]` runs the host
  steps in order:
  1. stops if a client tunnel holds 1234
  2. checks the benched RAM tier, oMLX, weights and the token's file mode
  3. runs `omlx.sh up`, autostart and the aliases line
  4. prints the `iogpu` step, which needs sudo
  5. checks pins, then runs preflight and healthcheck

  `client/install-client.sh [--host u@h] [--dual|--laptop] [--check]` does
  the client plumbing: the client copy, `Host hearth`, one marked rc block
  (loose older lines are commented out, with a backup), and the tunnel port
  by mode. It lists the secret and host-side steps for the person. Neither
  installer reads a key.
- **Editors** on a dual machine get two providers: `hearth` (1234) and
  `hearth-remote` (1235), both calling `main-brain`.
- **Sizes.** The 48 GB tier row is benched. 32 GB and 24 GB get candidates
  only (README, `docs/MODELS.md`), with no `roles.tsv` row until benched
  (rule 5). `install-host.sh` stops on a machine without a benched row.

## Consequences

- To make this laptop dual:
  1. `client/install-client.sh --dual`
  2. in a new shell, `ai-tunnel-stop && ai-tunnel-install`, which moves the
     tunnel to 1235
  3. `brew services stop omlx` (it serves on 8000 today)
  4. `scripts/install-host.sh`
  5. `client/edit-model.sh laptop-up`, so `edit-brain` is served on 1234
- **RAM on a dual laptop.** `main-brain` peaks at 34.0 GB at 128K × 3
  (rule 7). On a 48 GB laptop that leaves about 14 GB for macOS and apps.
  That is fine for a dedicated host but tight for daily use. A 1-slot
  laptop tier would need its own bench before it gets a row. This is open.
- The sandbox on a dual machine reaches only its own brain (1234), not the
  tunnel. That is unchanged from today, and it is still private.
- Windows clients (`hearth-client.ps1`) have no dual mode: oMLX is
  macOS-only.
