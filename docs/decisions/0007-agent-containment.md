# 0007 — Contain agents by cutting egress, not by detecting injection

Date: 2026-08-02
Status: accepted

## Context

Comparing this stack against other people's setups (`docs/COMPARISON.md`)
surfaced one genuine hole: **we govern where data goes on purpose, and not at
all what a compromised agent does.** aider and Zed agents run with full user
permissions. The gateway's virtual keys have no jurisdiction over a process
that calls `curl` directly.

Research on the current state of the field (2026):

- The strongest published prompt-injection defences still miss roughly one in
  ten optimisation-based attacks, and adaptive attacks bypass essentially every
  recommended defence. **Detection is not a viable control.**
- OWASP's 2026 data has prompt injection as the leading agentic-AI security
  failure in production, with coding agents driving most of the new volume.
  **aider is named specifically**, and it is used here daily.
- `sandbox-exec` on macOS remains deprecated with no replacement — Apple's
  suggested App Sandbox requires code signing and an Xcode project, which does
  not apply to CLI tools. Community consensus is to use it regardless.

## Decision

**Restrict capability. Do not attempt detection.**

`scripts/sandboxed.sh` runs an agent under an SBPL profile with two controls,
in order of importance:

1. **Egress is denied except to `127.0.0.1:4000`.** This is the load-bearing
   control. It composes with the existing architecture rather than fighting it:
   the gateway is already the only thing an agent legitimately needs to reach.
2. **Writes are confined to the working directory** (plus temp, plus announced
   per-agent state directories).

**Reads are deliberately left unrestricted.** Restricting them breaks dylib
loading and every language runtime, and read confinement is not what stops the
attack. A sandboxed agent can still read `~/.ssh/id_rsa`; it has no channel to
send it anywhere.

`scripts/sandbox-probe.sh` verifies the controls actually hold. It follows the
two-part discipline established by the leak test: an allowed action must
**succeed** before any denial is believed, because a profile that fails to
compile blocks everything and would otherwise look like perfect security.

Verified on macOS 26.4, 2026-08-02: 10 passed, 0 failed.

## Consequences

**Good**

- The exfiltration channel is closed, verified against a live external host.
  Observed in the wild within minutes: aider's startup call to pypi.org was
  refused by the sandbox.
- The control is structural, matching how the privacy boundary already works —
  not a rule anyone has to remember.
- The profile is auditable off-host via `--print-profile`, and the audited
  bytes are the applied bytes.

**Bad**

- `pip install`, `npm install` and `git push` fail inside a sandboxed session.
  Deliberate. Run them in a normal shell.
- Tools that keep state outside the working directory crash until a preset is
  added. aider needed `~/.aider` writable and `--no-check-update`.
- `sandbox-exec` is deprecated. Apple may remove it. `sandbox-probe.sh` must be
  re-run after macOS updates — the probe is how we learn that deliberately
  rather than by being breached.

**Accepted, unmitigated**

- An injected agent can still read any file the user can, and can still corrupt
  the repo it was invited into. The second is mitigated by git hygiene, not by
  this decision.
- Claude Code continues to run unsandboxed under the exception in ADR 0001.
- `auslaw-mcp` is unaudited and is now the largest unknown on the list.

## Alternatives rejected

- **Injection detection / prompt hardening.** Does not work; see Context.
- **Filesystem-only sandboxing, no egress block.** Leaves the channel that
  turns a compromise into a loss.
- **Allowing package registries through.** GitHub allows pushing and a gist is
  a perfectly good place to send a stolen key. A partial egress block is not a
  weaker version of this control; it is the absence of it.
- **Lima VM or separate user account.** Stronger and correct if the threat
  model ever includes an attacker specifically targeting this machine. Too much
  friction for the current one.
