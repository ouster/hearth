#!/usr/bin/env python3
"""Edit-prediction latency bench (ADR 0033).

Sends the fixed prompts in bench/edit/ to /v1/completions, one at a time,
the way an editor does between keystrokes. Reports latency p50/p95 and
whether each prediction contains its expected text. With --duration it
keeps going for that many seconds, so it can run beside
scripts/concurrency-bench.sh to see whether predictions slow agent turns.

The API key comes from the environment variable named by --key-env, never
the command line. Standard library only.
"""
import argparse, glob, json, os, statistics, sys, time, urllib.error, urllib.request

ap = argparse.ArgumentParser()
ap.add_argument("--base-url", required=True)
ap.add_argument("--key-env", required=True)
ap.add_argument("--model", default="local-edit")
ap.add_argument("--rounds", type=int, default=6)
ap.add_argument("--duration", type=float, default=0.0)
ap.add_argument("--tasks", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "edit"))
ap.add_argument("--out", required=True)
ap.add_argument("--label", default="")
a = ap.parse_args()

key = os.environ.get(a.key_env, "")
if not key:
    sys.exit("could not run: %s is empty" % a.key_env)
tasks = []
for p in sorted(glob.glob(os.path.join(a.tasks, "*.prompt"))):
    name = os.path.basename(p)[: -len(".prompt")]
    exp = open(p[: -len(".prompt")] + ".expect").read().strip()
    tasks.append((name, open(p).read(), exp))
if not tasks:
    sys.exit("could not run: no prompts in %s" % a.tasks)

url = a.base_url.rstrip("/") + "/completions"

def one(prompt):
    body = {"model": a.model, "prompt": prompt, "max_tokens": 512, "temperature": 0,
            "stop": ["<|file_sep|>", "</s>"]}
    req = urllib.request.Request(url, data=json.dumps(body).encode())
    req.add_header("Content-Type", "application/json")
    req.add_header("Authorization", "Bearer " + key)
    t = time.time()
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            d = json.load(r)
        return (time.time() - t) * 1000, d["choices"][0].get("text", ""), d.get("usage") or {}, ""
    except (urllib.error.URLError, OSError, ValueError, KeyError) as e:
        return (time.time() - t) * 1000, "", {}, str(e)[:120]

rows = []
start = time.time()
rnd = 0
while True:
    rnd += 1
    for name, prompt, exp in tasks:
        ms, text, usage, err = one(prompt)
        rows.append({"round": rnd, "task": name, "ms": round(ms, 1), "hit": exp in text,
                     "completion_tokens": usage.get("completion_tokens"), "error": err,
                     "text": text})
    if a.duration:
        if time.time() - start >= a.duration:
            break
    elif rnd >= a.rounds:
        break

os.makedirs(a.out, exist_ok=True)
with open(os.path.join(a.out, "raw.jsonl"), "w") as f:
    for r in rows:
        f.write(json.dumps(r) + "\n")

ok = [r for r in rows if not r["error"]]
lat = sorted(r["ms"] for r in ok)
def pct(p):
    if not lat:
        return float("nan")
    return lat[min(len(lat) - 1, int(round(p * (len(lat) - 1))))]
first = {}
for r in rows:
    first.setdefault(r["task"], r)
p95 = pct(0.95)
lines = [
    "# Edit-prediction bench%s" % (" — " + a.label if a.label else ""),
    "",
    "| | |", "|---|---|",
    "| Endpoint | `%s` |" % url,
    "| Model | `%s` |" % a.model,
    "| Requests | %d (%d errors) |" % (len(rows), len(rows) - len(ok)),
    "| Mode | %s |" % ("%.0f s loop" % a.duration if a.duration else "%d rounds" % a.rounds),
    "| Latency p50 / p95 | %.0f ms / %.0f ms |" % (pct(0.5), p95),
    "| Expected text present | %d / %d |" % (sum(r["hit"] for r in ok), len(ok)),
    "| Pass (p95 ≤ 500 ms, no errors) | %s |" % ("yes" if ok and len(ok) == len(rows) and p95 <= 500 else "**no**"),
    "",
    "## First prediction per task",
    "",
]
for name, r in first.items():
    lines += ["### %s — %.0f ms, %s" % (name, r["ms"], "expected text present" if r["hit"] else "**expected text missing**"),
              "", "```", (r["text"] or r["error"]).rstrip()[:1500], "```", ""]
open(os.path.join(a.out, "report.md"), "w").write("\n".join(lines))
print("\n".join(lines[:12]))
print("report: %s" % os.path.join(a.out, "report.md"))
sys.exit(0 if ok and len(ok) == len(rows) else 1)
