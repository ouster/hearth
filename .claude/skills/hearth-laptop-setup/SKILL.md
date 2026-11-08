---
name: hearth-laptop-setup
description: Set up, repair or re-check a LAPTOP's access to the Hearth host. Covers the SSH tunnel key, ~/.ssh/config, the client script, the launchd tunnel, the token file, and proving that ai-ping and ai-models work and that the key is tunnel-only. Use when the person says "set up this laptop", "connect to hearth", "ai-ping fails", "tunnel is down" or "BAD TOKEN". Never on the host; use hearth-host-setup there.
---

# Hearth laptop setup

You are probably a cloud model. Anything you read or print goes to your
vendor. That is why every secret rule below exists. The full procedure is
`docs/LAPTOP.md` → *AI-assisted setup*. Read it, and follow it in order.
This skill adds the stops and the checks.

## 0. Confirm this is a laptop

| Signal | Means |
|---|---|
| `~/.config/hearth/env` exists | a host. If it is also a client of another host: **both** (ADR 0040), so use `client/install-client.sh --dual` here. Otherwise stop and use `hearth-host-setup` |
| `~/.hearth-key` or `~/.ssh/hearth_tunnel` exists | laptop, already set up once ("Already registered" path) |
| neither | fresh laptop, or a fresh host: **ask** |

A laptop running `edit-brain` also has `~/.omlx` (ADR 0033), so `~/.omlx`
alone proves nothing.

## Never

- Read, print, grep, copy or edit `~/.hearth-key`, `~/.hearth-gemini-key`
  or `~/.ssh/hearth_tunnel`. `ls -l` on them is fine. Showing
  `~/.ssh/hearth_tunnel.pub` is fine, because it is public.
- Ask the person to paste a token or key into the chat.
- Run host scripts in `scripts/`. The only laptop-safe ones are
  `scripts/loop-guard.sh`, `scripts/install-loop-guard.sh` and
  `scripts/vscode-check.sh` (editor tools, ADR 0036).
- Add a router port-forward, turn on "Serve on Local Network", or make
  hearth a Cursor model provider.

## 1. Ask first

- Is it a new machine or already registered? What is its short name (for
  example `m5-air`)?
- What is the host, as `user@host.local`?
- What shell: zsh, bash or PowerShell?

`client/install-client.sh` writes `HEARTH_CLOUD_MODEL` from the
`cloud-cheap` row of `config/roles.tsv`. Do not append that id to the rc
by hand.

## 2. You may run

`client/install-client.sh --check`, then `client/install-client.sh --host
user@host.local`. It does the plumbing in one go: client copy, `Host
hearth`, one marked rc block, and tunnel port by mode. It lists what is
left for the person. Do not append loose `HEARTH_*` lines to the rc.

`ssh-keygen` is still separate: only for a new tunnel key, interactive, so
the person may need to run it. Follow *AI-assisted setup* step 2.

**Stale client check.** Even when already set up, re-run the installer
(it refreshes `~/.hearth-client.sh` and the rc block). An old copy's
`ai-tunnel-stop` cannot see the launchd tunnel (`com.hearth.tunnel`). It
reports "none running" while the tunnel is up.

## 3. Stop and hand over

Wait at each of these until the person says it is done:

1. **On the host:** `scripts/omlx.sh sub-key add laptop-<short-name>` for a
   new machine, or `sub-key list` to confirm the name for a registered one.
2. **On the host:** `scripts/client-setup.sh <short-name> --authorize hearth_tunnel.pub`.
3. **In their own terminal, not through you:** the `read -rs` lines from
   *AI-assisted setup* step 3, which write `~/.hearth-key` (and optionally
   `~/.hearth-gemini-key`). Afterwards, check `ls -l` shows `-rw-------` and
   a non-zero size.

## 4. Prove it, in a new shell

| Command | Expect |
|---|---|
| `ai-tunnel` | `tunnel: up` |
| `ai-tunnel-install` (macOS) | `tunnel: installed com.hearth.tunnel` |
| `ai-ping` | `up` |
| `ai-models` | `main-brain`, plus `deep-brain` only while the host has it loaded |
| `ai-ask "say ok"` | a short reply |
| `ssh hearth true; echo $?` | **non-zero**, because the key is tunnel-only |

| `ai-ping` says | Fix |
|---|---|
| `BAD TOKEN` | the person re-runs the `read -rs` step with the right token |
| `NO ANSWER` | the host is asleep or oMLX is down; fix it on the host |
| `DOWN` | no tunnel; run `ai-tunnel` |

If `ssh hearth true` succeeds, **stop**. The key was authorized without
restrictions. Tell the person, and do not continue.

You can check the tunnel yourself without a key:
`curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:1234/v1/models`
should print `401`.

## Done when

Every row in step 4 matches. For editors, hand over to `hearth-editor-setup`.
