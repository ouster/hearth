# oMLX trial bench — same ~30k prompt twice

| | |
|---|---|
| Base URL | `http://127.0.0.1:1234/v1` |
| Role | `local-main` |
| Run | `scripts/omlx-try.sh bench` |
| Prompt | one body, sent twice (no per-request prefix) |
| Prompt tokens | 30244 |
| Footprint process | Python pid 69036, the listener on port 1234 |

## Checks

| Check | Result |
|---|---|
| Thinking probe | 200, reasoning present, no thinking markers in the answer |
| Tool smoke | pass — `read_file`, then `write_file` |

## Cache

| Turn | TTFT | Prompt tokens | Cache |
|---|---|---|---|
| 1 | 26.1 s | 30244 | cold |
| 2 | 4.6 s | 30244 | restored 30241, suffix 3, reconstruct 650 ms |

## Footprint

Peak 26.0 GB during the run. 24.0 GB at the last sample, after the second turn.

Raw: `bench.log`, `footprint.tsv`.
