#!/usr/bin/env python3
"""Concurrency bench: N simultaneous agent turns against one role.

Stdlib only. Run with `python3 -I`. Normally invoked by
scripts/concurrency-bench.sh — see docs/MIGRATION-LMSTUDIO.md phase 0.

Each request is a realistic Zed-style agent turn: system prompt, six tool
schemas, an earlier tool result padded with real repo files to ~T prompt
tokens, `stream: true`, and an instruction that should produce a `read_file`
tool call. A nonce at the top of every request defeats prefix caching, so
every request pays a full prefill — the worst case, measured the same way on
every backend.

A round fires N requests at once and waits for all of them. A request that
exceeds the client timeout is closed and recorded as a failure; it never
crashes the run.

Exit codes: 0 every request returned a valid tool call, 1 at least one
failure (expected at baseline), 2 could not run.
"""

import argparse
import json
import math
import os
import re
import socket
import subprocess
import sys
import threading
import time
import uuid
import http.client
from urllib.parse import urlparse

TOOLS = [
    ("read_file", "Read a file from the project.",
     {"path": {"type": "string", "description": "Path relative to the project root."}}, ["path"]),
    ("write_file", "Create or overwrite a file.",
     {"path": {"type": "string"}, "content": {"type": "string"}}, ["path", "content"]),
    ("edit_file", "Replace an exact string in a file.",
     {"path": {"type": "string"}, "old_text": {"type": "string"}, "new_text": {"type": "string"}},
     ["path", "old_text", "new_text"]),
    ("list_directory", "List entries in a directory.",
     {"path": {"type": "string"}}, ["path"]),
    ("grep", "Search files for a regular expression.",
     {"pattern": {"type": "string"}, "path": {"type": "string"}}, ["pattern"]),
    ("run_command", "Run a shell command in the project root.",
     {"command": {"type": "string"}}, ["command"]),
]

SYSTEM = (
    "You are a coding agent working in a user's repository. Use the provided "
    "tools to inspect and change files. Never guess file contents: read a file "
    "before editing it. Call exactly one tool per turn unless told otherwise."
)

TARGET_PATH = "scripts/lib.sh"
CHARS_PER_TOKEN = 3.2  # rough for code + English; actual prompt_tokens is recorded


def tool_schemas():
    out = []
    for name, desc, props, req in TOOLS:
        out.append({"type": "function", "function": {
            "name": name, "description": desc,
            "parameters": {"type": "object", "properties": props, "required": req}}})
    return out


def load_filler(root, chars):
    """Concatenate real repo files until `chars` is reached."""
    files = []
    for sub in ("docs", "scripts", "docs/decisions", "bench/tasks"):
        d = os.path.join(root, sub)
        if not os.path.isdir(d):
            continue
        for n in sorted(os.listdir(d)):
            p = os.path.join(d, n)
            if os.path.isfile(p) and n.endswith((".md", ".sh", ".zsh", ".py")):
                files.append(p)
    if not files:
        raise RuntimeError("no filler files under " + root)
    parts, total, i = [], 0, 0
    while total < chars:
        p = files[i % len(files)]
        with open(p, encoding="utf-8", errors="replace") as fh:
            body = fh.read()
        chunk = "==> %s <==\n%s\n" % (os.path.relpath(p, root), body)
        parts.append(chunk)
        total += len(chunk)
        i += 1
    return "".join(parts)[:chars]


def build_body(model, filler):
    nonce = uuid.uuid4().hex
    return {
        "model": model,
        "stream": True,
        "stream_options": {"include_usage": True},
        "temperature": 0.2,
        "max_tokens": 1024,
        "tools": tool_schemas(),
        "messages": [
            {"role": "system", "content": "session %s\n%s" % (nonce, SYSTEM)},
            {"role": "user", "content": "Find where the gateway readiness check lives "
                                        "and explain how it decides the gateway is ready."},
            {"role": "assistant", "content": None, "tool_calls": [{
                "id": "call_1", "type": "function",
                "function": {"name": "grep",
                             "arguments": json.dumps({"pattern": "readiness", "path": "."})}}]},
            {"role": "tool", "tool_call_id": "call_1",
             "content": "Matches (with surrounding files for context):\n" + filler},
            {"role": "user", "content": "Now read %s with the read_file tool. "
                                        "Respond only with the tool call." % TARGET_PATH},
        ],
    }


def one_request(url, token, body, timeout):
    """Returns a dict of per-request measurements. Never raises."""
    r = {"status": "", "ttfb": "", "ttft": "", "total": "", "tool_ok": 0,
         "tool_name": "", "finish": "", "prompt_tokens": "", "completion_tokens": "",
         "error": ""}
    u = urlparse(url)
    path = u.path.rstrip("/") + "/chat/completions"
    t0 = time.monotonic()
    deadline = t0 + timeout
    conn = None
    calls = {}
    try:
        cls = http.client.HTTPSConnection if u.scheme == "https" else http.client.HTTPConnection
        conn = cls(u.hostname, u.port or (443 if u.scheme == "https" else 80), timeout=timeout)
        headers = {"Content-Type": "application/json", "Accept": "text/event-stream"}
        if token:
            headers["Authorization"] = "Bearer " + token
        conn.request("POST", path, body=json.dumps(body).encode(), headers=headers)
        resp = conn.getresponse()
        r["status"] = resp.status
        if resp.status != 200:
            r["error"] = resp.read(400).decode("utf-8", "replace").replace("\n", " ")
            return r
        first = True
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise socket.timeout("client deadline")
            conn.sock.settimeout(remaining)
            line = resp.readline()
            if not line:
                break
            if first:
                r["ttfb"] = round(time.monotonic() - t0, 3)
                first = False
            line = line.strip()
            if not line.startswith(b"data:"):
                continue
            data = line[5:].strip()
            if data == b"[DONE]":
                break
            try:
                ev = json.loads(data)
            except ValueError:
                continue
            if ev.get("error"):
                r["error"] = json.dumps(ev["error"])[:300]
            usage = ev.get("usage") or {}
            if usage:
                r["prompt_tokens"] = usage.get("prompt_tokens", "")
                r["completion_tokens"] = usage.get("completion_tokens", "")
            for ch in ev.get("choices") or []:
                d = ch.get("delta") or {}
                got = bool(d.get("content") or d.get("reasoning_content")
                           or d.get("reasoning") or d.get("tool_calls"))
                if got and r["ttft"] == "":
                    r["ttft"] = round(time.monotonic() - t0, 3)
                for tc in d.get("tool_calls") or []:
                    idx = tc.get("index", 0)
                    c = calls.setdefault(idx, {"name": "", "args": ""})
                    fn = tc.get("function") or {}
                    if fn.get("name"):
                        c["name"] = fn["name"]
                    if fn.get("arguments"):
                        c["args"] += fn["arguments"]
                if ch.get("finish_reason"):
                    r["finish"] = ch["finish_reason"]
    except (socket.timeout, TimeoutError):
        r["error"] = "timeout after %ss" % timeout
        r["finish"] = r["finish"] or "timeout"
    except Exception as e:  # recorded, not raised
        r["error"] = "%s: %s" % (type(e).__name__, str(e)[:200])
    finally:
        r["total"] = round(time.monotonic() - t0, 3)
        if conn is not None:
            try:
                conn.close()
            except Exception:
                pass
    if calls:
        c = calls[sorted(calls)[0]]
        r["tool_name"] = c["name"]
        try:
            args = json.loads(c["args"] or "{}")
            r["tool_ok"] = int(c["name"] == "read_file" and isinstance(args, dict)
                               and bool(args.get("path")))
        except ValueError:
            r["error"] = r["error"] or "tool args not JSON"
    if not r["error"] and not r["tool_ok"]:
        r["error"] = "no valid read_file call"
    return r


class FootprintSampler(threading.Thread):
    """Every `interval` s, sum footprint(1) of processes matching a regex.

    The Ollama runner is spawned per load, so the pid is re-resolved each
    sample rather than fixed at start.
    """

    def __init__(self, pattern, interval):
        super().__init__(daemon=True)
        self.pattern = pattern
        self.interval = interval
        self.samples = []  # (t, gb, pids)
        self.stop_ev = threading.Event()
        self.error = ""

    def pids(self):
        try:
            out = subprocess.run(["pgrep", "-f", self.pattern], capture_output=True,
                                 text=True, timeout=5).stdout
        except Exception as e:
            self.error = str(e)
            return []
        me = str(os.getpid())
        return [p for p in out.split() if p and p != me]

    @staticmethod
    def footprint_gb(pid):
        try:
            out = subprocess.run(["footprint", "-p", pid], capture_output=True,
                                 text=True, timeout=10).stdout
        except Exception:
            return None
        m = re.search(r"Footprint:\s+([\d.]+)\s+([KMG]B)", out)
        if not m:
            return None
        n, unit = float(m.group(1)), m.group(2)
        return n / {"KB": 1024 * 1024, "MB": 1024, "GB": 1}[unit]

    def run(self):
        t0 = time.monotonic()
        while not self.stop_ev.is_set():
            pids = self.pids()
            total = 0.0
            for p in pids:
                gb = self.footprint_gb(p)
                if gb is not None:
                    total += gb
            self.samples.append((round(time.monotonic() - t0, 1), round(total, 2), ",".join(pids)))
            self.stop_ev.wait(self.interval)

    def peak(self):
        return max((s[1] for s in self.samples), default=0.0)


def pct(vals, p):
    vals = sorted(v for v in vals if v != "")
    if not vals:
        return None
    k = max(0, min(len(vals) - 1, math.ceil(p / 100.0 * len(vals)) - 1))  # nearest rank
    return vals[k]


def fmt(v):
    return "—" if v is None else "%.1f s" % v


COLS = ["round", "slot", "status", "ttfb", "ttft", "total", "tool_ok", "tool_name",
        "finish", "prompt_tokens", "completion_tokens", "error"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-url", required=True)
    ap.add_argument("--token-env", default="", help="name of env var holding the bearer token")
    ap.add_argument("--model", required=True, help="role name, never a concrete model")
    ap.add_argument("--concurrency", type=int, default=3)
    ap.add_argument("--rounds", type=int, default=10)
    ap.add_argument("--prompt-tokens", type=int, default=30000)
    ap.add_argument("--timeout", type=int, default=180)
    ap.add_argument("--proc-match", default="ollama (runner|serve)",
                    help="pgrep -f regex for the inference process(es) to footprint")
    ap.add_argument("--sample-interval", type=float, default=2.0)
    ap.add_argument("--note-log", action="append", default=[],
                    help="log file; lines stamped during the run go in the report")
    ap.add_argument("--label", default="")
    ap.add_argument("--root", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    token = ""
    if a.token_env:
        token = os.environ.get(a.token_env, "")
        if not token:
            print("could not run: %s is not set" % a.token_env, file=sys.stderr)
            return 2
    try:
        filler = load_filler(a.root, int(a.prompt_tokens * CHARS_PER_TOKEN))
    except Exception as e:
        print("could not run: %s" % e, file=sys.stderr)
        return 2
    os.makedirs(a.out, exist_ok=True)

    started_wall = time.strftime("%Y-%m-%dT%H:%M:%S")
    sampler = FootprintSampler(a.proc_match, a.sample_interval)
    sampler.start()
    rows = []
    url = a.base_url
    t_run = time.monotonic()
    for rnd in range(1, a.rounds + 1):
        results = [None] * a.concurrency
        threads = []
        for slot in range(a.concurrency):
            body = build_body(a.model, filler)

            def go(s=slot, b=body):
                results[s] = one_request(url, token, b, a.timeout)
            th = threading.Thread(target=go)
            threads.append(th)
            th.start()
        for th in threads:
            th.join()
        for slot, r in enumerate(results):
            r["round"], r["slot"] = rnd, slot
            rows.append(r)
            print("round %d slot %d: status=%s ttft=%s total=%s tool_ok=%s finish=%s %s" % (
                rnd, slot, r["status"], r["ttft"], r["total"], r["tool_ok"], r["finish"],
                r["error"][:80]), flush=True)
    wall = time.monotonic() - t_run
    sampler.stop_ev.set()
    sampler.join(timeout=15)
    ended_wall = time.strftime("%Y-%m-%dT%H:%M:%S")

    with open(os.path.join(a.out, "raw.tsv"), "w") as fh:
        fh.write("\t".join(COLS) + "\n")
        for r in rows:
            fh.write("\t".join(str(r[c]).replace("\t", " ") for c in COLS) + "\n")
    with open(os.path.join(a.out, "footprint.tsv"), "w") as fh:
        fh.write("t_s\tfootprint_gb\tpids\n")
        for s in sampler.samples:
            fh.write("%s\t%s\t%s\n" % s)

    ok = [r for r in rows if r["tool_ok"]]
    timeouts = [r for r in rows if r["finish"] == "timeout"]
    http_err = [r for r in rows if r["status"] not in (200, "")]
    other = [r for r in rows if not r["tool_ok"] and r not in timeouts and r not in http_err]
    ttfts = [r["ttft"] for r in rows if r["ttft"] != ""]
    ttfbs = [r["ttfb"] for r in rows if r["ttfb"] != ""]
    totals = [r["total"] for r in ok]
    ptoks = [r["prompt_tokens"] for r in rows if isinstance(r["prompt_tokens"], int)]

    notes = []
    for path in a.note_log:
        try:
            with open(os.path.expanduser(path), errors="replace") as fh:
                for line in fh:
                    stamp = line[:19]
                    if started_wall <= stamp <= ended_wall + "~":
                        notes.append("%s: %s" % (os.path.basename(path), line.rstrip()))
        except OSError:
            notes.append("%s: not readable" % path)

    L = []
    L.append("# Concurrency bench%s" % (" — " + a.label if a.label else ""))
    L.append("")
    L.append("| | |")
    L.append("|---|---|")
    L.append("| Base URL | `%s` |" % a.base_url)
    L.append("| Role | `%s` |" % a.model)
    L.append("| Concurrency × rounds | %d × %d = %d requests |" % (a.concurrency, a.rounds, len(rows)))
    L.append("| Target prompt tokens | %d (actual median %s) |" % (
        a.prompt_tokens, pct(ptoks, 50) if ptoks else "not reported"))
    L.append("| Client timeout | %d s |" % a.timeout)
    L.append("| Run | %s → %s (%.0f s wall) |" % (started_wall, ended_wall, wall))
    L.append("| Footprint process match | `%s` |" % a.proc_match)
    L.append("")
    L.append("## Result")
    L.append("")
    L.append("| Metric | Value |")
    L.append("|---|---|")
    L.append("| Valid `read_file` tool calls | %d / %d |" % (len(ok), len(rows)))
    L.append("| Timeouts (client, %d s) | %d |" % (a.timeout, len(timeouts)))
    L.append("| HTTP errors | %d |" % len(http_err))
    L.append("| Other failures (bad/no tool call, stream error) | %d |" % len(other))
    L.append("| TTFB p50 / p95 | %s / %s |" % (fmt(pct(ttfbs, 50)), fmt(pct(ttfbs, 95))))
    L.append("| TTFT p50 / p95 (requests that produced a token) | %s / %s |" % (
        fmt(pct(ttfts, 50)), fmt(pct(ttfts, 95))))
    L.append("| Total time p50 / p95 (successful) | %s / %s |" % (fmt(pct(totals, 50)), fmt(pct(totals, 95))))
    L.append("| Peak footprint (sum of matched processes) | %.1f GB |" % sampler.peak())
    L.append("")
    fails = [r for r in rows if not r["tool_ok"]]
    if fails:
        L.append("## Failures")
        L.append("")
        L.append("| Round | Slot | HTTP | TTFT | Total | Finish | Error |")
        L.append("|---|---|---|---|---|---|---|")
        for r in fails:
            L.append("| %s | %s | %s | %s | %s | %s | %s |" % (
                r["round"], r["slot"], r["status"] or "—", r["ttft"] or "—", r["total"],
                r["finish"] or "—", (r["error"] or "").replace("|", "\\|")[:160]))
        L.append("")
    if a.note_log:
        L.append("## Log lines during the run")
        L.append("")
        if notes:
            L.append("```")
            L.extend(notes[:50])
            L.append("```")
        else:
            L.append("None.")
        L.append("")
    if sampler.error:
        L.append("Footprint sampler error: %s" % sampler.error)
        L.append("")
    L.append("Raw: `raw.tsv`, `footprint.tsv`.")
    with open(os.path.join(a.out, "report.md"), "w") as fh:
        fh.write("\n".join(L) + "\n")
    print("\n".join(L))
    return 0 if len(ok) == len(rows) else 1


if __name__ == "__main__":
    sys.exit(main())
