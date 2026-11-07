# Edit-prediction bench — host 64 GB

| | |
|---|---|
| Endpoint | `http://127.0.0.1:1234/v1/completions` |
| Model | `local-edit` |
| Requests | 30 (0 errors) |
| Mode | 6 rounds |
| Latency p50 / p95 | 252 ms / 281 ms |
| Expected text present | 24 / 30 |
| Pass (p95 ≤ 500 ms, no errors) | yes |

## First prediction per task

### 01-rename-param — 127 ms, expected text present

```
def total(lines):
    return sum(i.price for i in lines)
```

### 02-add-field — 262 ms, **expected text missing**

```
@dataclass
class Matter:
    ref: str
    client: str
    settlement: str
    status: str

def label(m: Matter) -> str:
    return f"{m.ref} {m.client}"
```

### 03-bash-guard — 283 ms, expected text present

```
#!/bin/bash
set -uo pipefail
[ $# -gt 0 ] || { echo "usage: $0 file..." >&2; exit 2; }
for f in "$@"; do
  wc -l "$f"
done
```

### 04-next-case — 206 ms, expected text present

```
func label(s Status) string {
	switch s {
	case Open:
		return "open"
	case Settled:
		return "settled"
	}
	return "unknown"
}
```

### 05-greet-example — 252 ms, expected text present

```
from utils import get_time_of_day

def greet(name):
    time_of_day = get_time_of_day()
    print(f"Hello, {name}! Good {time_of_day}.")

greet("Alice")
```
