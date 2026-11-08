#!/usr/bin/env python3
"""Zed-like multi-turn tool smoke — read then write with angle brackets in content.

Usage:
  OPENAI_API_KEY=<token> bench/tool-smoke.py --model main-brain    # oMLX :1234
  bench/tool-smoke.py --url <openai-compatible base> --model <id>

Exit 0 on successful write tool call in turn 2; 1 on failure.
"""
from __future__ import annotations

import argparse
import os
import json
import sys
import urllib.error
import urllib.request


def tools():
    specs = [
        ("list_directory", {"path": {"type": "string"}}, ["path"]),
        ("read_file", {"path": {"type": "string"}}, ["path"]),
        ("grep", {"regex": {"type": "string"}, "path": {"type": "string"}}, ["regex"]),
        ("write_file", {"path": {"type": "string"}, "content": {"type": "string"}}, ["path", "content"]),
        ("edit_file", {"path": {"type": "string"}, "old_string": {"type": "string"}, "new_string": {"type": "string"}}, ["path", "old_string", "new_string"]),
        ("terminal", {"command": {"type": "string"}}, ["command"]),
        ("web_search", {"query": {"type": "string"}}, ["query"]),
    ]
    out = []
    for name, props, req in specs:
        out.append({
            "type": "function",
            "function": {
                "name": name,
                "description": f"Tool {name}",
                "parameters": {"type": "object", "properties": props, "required": req},
            },
        })
    return out


def post_json(url: str, payload: dict, headers: dict, timeout: int) -> dict:
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode(),
        headers={**headers, "Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())


def chat_ollama(base: str, model: str, messages: list, timeout: int) -> tuple[dict | None, str | None]:
    payload = {
        "model": model,
        "stream": False,
        "messages": messages,
        "tools": tools(),
        "options": {"num_ctx": 16384, "num_predict": 2048},
    }
    try:
        d = post_json(f"{base.rstrip('/')}/api/chat", payload, {}, timeout)
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors="replace")[:500]
        return None, f"HTTP {e.code}: {body}"
    except Exception as e:
        return None, str(e)
    if "error" in d:
        return None, str(d["error"])[:400]
    return d.get("message") or {}, None


def chat_openai(base: str, model: str, messages: list, api_key: str, timeout: int) -> tuple[dict | None, str | None]:
    url = f"{base.rstrip('/')}/chat/completions"
    payload = {"model": model, "stream": False, "messages": messages, "tools": tools()}
    headers = {}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"
    try:
        d = post_json(url, payload, headers, timeout)
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors="replace")[:500]
        return None, f"HTTP {e.code}: {body}"
    except Exception as e:
        return None, str(e)
    if "error" in d:
        err = d["error"]
        return None, (err.get("message") if isinstance(err, dict) else str(err))[:400]
    choices = d.get("choices") or []
    if not choices:
        return None, "no choices"
    return choices[0].get("message") or {}, None


def normalize_tool_calls(msg: dict) -> list:
    tcs = msg.get("tool_calls") or []
    out = []
    for tc in tcs:
        fn = tc.get("function") or {}
        name = fn.get("name")
        args = fn.get("arguments")
        if isinstance(args, str):
            try:
                args = json.loads(args)
            except json.JSONDecodeError:
                pass
        out.append({
            "id": tc.get("id") or name,
            "name": name,
            "arguments": args,
        })
    return out


def tool_result_content(name: str) -> str:
    if name == "read_file":
        return "# Model registry\n\nlocal-code role\n"
    if name == "list_directory":
        return "docs/\nscripts/\n"
    return "ok"


def append_tool_results(messages: list, assistant_msg: dict, backend: str) -> None:
    messages.append(assistant_msg)
    for tc in assistant_msg.get("tool_calls") or []:
        fn = tc.get("function") or {}
        name = fn.get("name") or ""
        content = tool_result_content(name)
        if backend == "ollama":
            messages.append({"role": "tool", "tool_name": name, "content": content})
        else:
            tc_id = tc.get("id")
            if not tc_id:
                print(f"WARN: tool_call missing id for {name}")
                tc_id = name
            messages.append({"role": "tool", "tool_call_id": tc_id, "content": content})


def summarize_turn(label: str, msg: dict | None, err: str | None) -> list:
    if err:
        print(f"{label}: FAIL {err}")
        return []
    tcs = normalize_tool_calls(msg or {})
    content = (msg or {}).get("content") or ""
    print(f"{label}: tool_calls={len(tcs)} content_len={len(content)}")
    for tc in tcs:
        print(f"  {tc['name']}")
    return tcs


def run_smoke(backend: str, base: str, model: str, api_key: str, timeout: int) -> int:
    print(f"=== tool-smoke {backend} model={model} ===")
    messages = [{
        "role": "user",
        "content": (
            "Read docs/MODELS.md then update scripts/healthcheck.sh. Use tools."
        ),
    }]

    if backend == "ollama":
        msg1, err1 = chat_ollama(base, model, messages, timeout)
    else:
        msg1, err1 = chat_openai(base, model, messages, api_key, timeout)
    tcs1 = summarize_turn("turn1", msg1, err1)
    if err1:
        return 1

    append_tool_results(messages, msg1, backend)
    messages.append({
        "role": "user",
        "content": (
            "Now call write_file on scripts/healthcheck.sh. content must start with "
            "'# hearth tool smoke\\n' then a bash shebang and a function containing "
            "the exact line: if [[ $x < 1 ]]; then echo hi; fi"
        ),
    })

    if backend == "ollama":
        msg2, err2 = chat_ollama(base, model, messages, timeout)
    else:
        msg2, err2 = chat_openai(base, model, messages, api_key, timeout)
    tcs2 = summarize_turn("turn2", msg2, err2)
    if err2:
        return 1

    wrote = False
    for tc in tcs2:
        if tc["name"] in ("write_file", "edit_file"):
            wrote = True
            args = tc.get("arguments") or {}
            if isinstance(args, dict):
                c = str(args.get("content") or args.get("new_string") or "")
                print(f"  has_lt={'<' in c} head={c[:80]!r}")

    if wrote:
        print("PASS — write/edit tool in turn 2")
        return 0
    print("FAIL — no write/edit in turn 2 (agent loop would stall)")
    return 1


def main() -> int:
    p = argparse.ArgumentParser(description="Zed-like tool smoke test")
    p.add_argument("--backend", choices=("ollama", "openai"), default="openai")
    p.add_argument("--url", default="http://127.0.0.1:1234/v1")
    p.add_argument("--model", required=True)
    # Default from the environment so the token never appears in argv / ps.
    p.add_argument("--api-key", default=os.environ.get("OPENAI_API_KEY", ""))
    p.add_argument("--timeout", type=int, default=300)
    args = p.parse_args()
    return run_smoke(args.backend, args.url, args.model, args.api_key, args.timeout)


if __name__ == "__main__":
    sys.exit(main())
