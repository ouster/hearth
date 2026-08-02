---
id: 04-long-context
category: context
auto_check: none
---

You will be given a long file. Answer only from the file — do not use general
knowledge, and say "not in the file" if the answer is not there.

Questions:
1. What is the fallback chain for `cloud-frontier`?
2. Which roles are dormant, and what is each blocked on?
3. What port is Postgres bound to, and why that port specifically?

This task exists to separate models that genuinely use long context from ones
that skim the start and confabulate the rest. Run it with the repo's own docs
concatenated as input — see scripts/bench.sh.
