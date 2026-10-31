# Phase 5 — gate after a clean reboot

**Date:** 2026-10-31. Host rebooted 14:33:31; nothing started by hand.

`com.hearth.boot` (scripts/boot.sh) ran once at login, exit 0:

```
14:35:06 LM Studio running
14:35:07 server started on 127.0.0.1:1234
14:35:07 auth on (no token → 401)
14:35:37 roles loaded per config/roles.tsv
14:35:37 starting podman machine
14:35:50 hearth-searxng: started
14:35:50 hearth-webui: started
14:35:50 up
```

| Check | Result |
|---|---|
| `scripts/healthcheck.sh` | exit 0 — 10 pass, 1 warning (unknown model names served by `local-big`; nothing loads) |
| `scripts/preflight.sh` | exit 0 — 29 pass, 0 warnings |
| Old-stack ports 4000 / 5433 / 11434 | free |
| `grep -rn '4000\|11434\|litellm\|ollama'` over scripts/ client/ docs/*.md | only intentional historical / deny-check / rollback mentions |

**Gate: passed.**
