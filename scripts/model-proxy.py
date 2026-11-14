#!/usr/bin/env python3
"""Proxy for oMLX that enriches /v1/models with display_name from roles.tsv.

Reads oMLX's /v1/models, annotates each entry with an IDE-friendly label
(mirrors zed-sync.sh), and forwards it to the client.  All other paths
(pass-through) are streamed chunk-by-chunk to preserve SSE chat streaming.

Usage:
    # Local proxy (enriched models → local oMLX)
    scripts/model-proxy.py --port 1238 --local

    # Remote proxy (enriched models → SSH tunnel)
    scripts/model-proxy.py --port 1239 --remote --tunnel-port 1235

    # Manual
    scripts/model-proxy.py --port PORT [--root REPO] [--local | --remote --tunnel-port PORT] [--timeout SECS]

The proxy reads resolved roles from `hearth_resolved_roles` via lib.sh, so
the displayed label always matches the model actually loaded on this host.
"""
from __future__ import annotations

import argparse
import http.client
import http.server
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# ── defaults ──────────────────────────────────────────────────────────────

DEFAULT_TIMEOUT = 300  # seconds — long turns (minutes, not seconds)
SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent


# ── helpers ───────────────────────────────────────────────────────────────

def read_api_key() -> Optional[str]:
    """Read oMLX API key from ~/.config/hearth/env (OMLX_HOST_TOKEN)."""
    env_path = Path.home() / ".config" / "hearth" / "env"
    if not env_path.exists():
        return None
    for line in env_path.read_text().splitlines():
        if line.startswith("OMLX_HOST_TOKEN="):
            return line.split("=", 1)[1]
    return None


def resolve_roles(root: Path) -> Dict[str, tuple]:
    """Return {role: (model_key, leaf, ctx_label, slot_n, load)} via hearth_resolved_roles.

    Calls the bash helper so the label always matches the model loaded on
    this host (tier resolved from installed RAM).
    """
    raw = parse_raw_roles(root)
    if not raw:
        return raw

    lib = root / "scripts" / "lib.sh"
    try:
        proc = subprocess.run(
            ["bash", "-c", f'. "{lib}" && echo "$ROOT" && hearth_resolved_roles'],
            capture_output=True, text=True, timeout=30,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return _resolve_fallback(raw)

    lines = proc.stdout.strip().splitlines()
    if len(lines) < 2:
        return _resolve_fallback(raw)

    # First line is ROOT; remaining lines are resolved roles.
    resolved: Dict[str, tuple] = {}
    for line in lines[1:]:
        parts = line.strip().split("\t")
        if len(parts) < 9:
            continue
        role, _, model_key, ctx, slots, weights, _, load = parts[:8]
        leaf = weights.rstrip("/").split("/")[-1] if weights and weights != "-" else ""
        ctx_int = int(ctx)
        ctx_label = f"{ctx_int // 1024}K" if ctx_int >= 1024 else str(ctx)
        slot_n = int(slots) if str(slots).isdigit() else 0
        resolved[role] = (model_key, leaf, ctx_label, slot_n, load)
    return resolved


def parse_raw_roles(root: Path) -> Dict[str, List[dict]]:
    """Parse raw roles.tsv, returning {role: [rows]}."""
    tsv = root / "config" / "roles.tsv"
    if not tsv.exists():
        return {}
    buckets: Dict[str, List[dict]] = {}
    with open(tsv) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) < 9:
                continue
            role, _, model_key, ctx, slots, weights, _, load, min_ram = parts[:9]
            entry = {
                "model_key": model_key,
                "weights": weights,
                "ctx": ctx,
                "slots": slots,
                "load": load,
                "min_ram": min_ram,
            }
            buckets.setdefault(role, []).append(entry)
    return buckets


def _resolve_fallback(raw: Dict[str, List[dict]]) -> Dict[str, tuple]:
    """Pick last row per role (fallback — not ideal, but works for single-tier."""
    result: Dict[str, tuple] = {}
    for role, rows in raw.items():
        best = rows[-1]
        leaf = best["weights"].rstrip("/").split("/")[-1] if best["weights"] and best["weights"] != "-" else ""
        ctx_int = int(best["ctx"])
        ctx_label = f"{ctx_int // 1024}K" if ctx_int >= 1024 else str(best["ctx"])
        slot_n = int(best["slots"]) if str(best["slots"]).isdigit() else 0
        result[role] = (best["model_key"], leaf, ctx_label, slot_n, best["load"])
    return result


def build_display_name(role: str, model_key: str, leaf: str,
                       ctx_label: str, load: str) -> str:
    """Build label matching zed-sync.sh format: role — leaf — ctx_label."""
    # zed-sync.sh uses: "role — leaf — ctx x slots"
    # But we have leaf already extracted, so: "role — leaf — ctx_label"
    label = f"{role} \u2014 {leaf} \u2014 {ctx_label}"
    if load == "swap":
        label += " \u2014 load first: scripts/demand-load.sh " + role + " up"
    elif load == "edit":
        label += " \u2014 editor edit prediction (laptop only)"
    return label


# ── proxy ─────────────────────────────────────────────────────────────────

class ProxyHandler(http.server.BaseHTTPRequestHandler):
    backend_url: str = "http://127.0.0.1:1234"
    # Enrichment map: {role_id: (display_name,)}
    display_names: Dict[str, str] = {}
    timeout_secs: int = DEFAULT_TIMEOUT

    def log_message(self, format: str, *args) -> None:  # type: ignore[override]
        sys.stderr.write(f"[model-proxy] {format % args}\n")
        sys.stderr.flush()

    # ── local / remote backend ────────────────────────────────────────────

    def _is_local_backend(self) -> bool:
        """True when forwarding to local oMLX (:1234)."""
        parsed = self._backend_parsed()
        return parsed.port == 1234

    def _backend_parsed(self) -> "urlparse":
        from urllib.parse import urlparse
        return urlparse(self.backend_url)

    def _inject_auth_if_local(self, headers: dict) -> None:
        """Only inject API key for local backend. Remote clients must send
        their own key through the tunnel."""
        if not self._is_local_backend():
            return
        if "Authorization" in headers:
            return
        key = read_api_key()
        if key:
            headers["Authorization"] = f"Bearer {key}"

    # ── streaming pass-through ────────────────────────────────────────────

    def _proxy_request(self, path: str, body: Optional[bytes] = None) -> None:
        """Forward request, streaming the response body chunk-by-chunk."""
        parsed = self._backend_parsed()
        headers = dict(self.headers)
        headers.pop("host", None)
        headers.pop("transfer-encoding", None)
        headers.pop("content-length", None)

        self._inject_auth_if_local(headers)

        conn = http.client.HTTPConnection(
            parsed.hostname, parsed.port, timeout=self.timeout_secs,
        )
        try:
            conn.request(self.command, path, body=body, headers=headers)
            resp = conn.getresponse()

            # Forward status + headers
            self.send_response(resp.status)
            for hdr in resp.getheaders():
                key, val = hdr
                if key.lower() in ("transfer-encoding", "connection", "content-length"):
                    continue
                self.send_header(key, val)
            self.end_headers()

            # Stream body chunk-by-chunk (preserves SSE for chat completions)
            while True:
                chunk = resp.read(8192)
                if not chunk:
                    break
                self.wfile.write(chunk)
        finally:
            conn.close()

    # ── model enrichment ─────────────────────────────────────────────────

    def _handle_models(self) -> None:
        """Fetch model list from backend, enrich with display_name, send."""
        parsed = self._backend_parsed()
        headers: Dict[str, str] = {}
        self._inject_auth_if_local(headers)

        conn = http.client.HTTPConnection(
            parsed.hostname, parsed.port, timeout=10,
        )
        try:
            conn.request("GET", "/v1/models", headers=headers)
            resp = conn.getresponse()
            data = resp.read()
            models_resp = json.loads(data)
        finally:
            conn.close()

        # Enrich each model entry
        if "data" in models_resp:
            for model in models_resp["data"]:
                role_id = model.get("id", "")
                if role_id in self.display_names:
                    model["display_name"] = self.display_names[role_id]

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(models_resp).encode())

    # ── routing ───────────────────────────────────────────────────────────

    def do_GET(self) -> None:
        if self.path.split("?")[0] == "/v1/models":
            self._handle_models()
        else:
            self._proxy_request(self.path)

    def do_POST(self) -> None:
        if self.path.split("?")[0] == "/v1/models":
            self._handle_models()
        else:
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length) if content_length > 0 else None
            self._proxy_request(self.path, body)


# ── main ──────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="oMLX model display proxy")
    parser.add_argument("--port", type=int, default=1238)
    parser.add_argument("--root", type=str, default=str(REPO_ROOT),
                        help="Hearth repo root (default: script parent)")
    parser.add_argument("--local", action="store_true",
                        help="Forward to local oMLX on :1234")
    parser.add_argument("--remote", action="store_true",
                        help="Forward to SSH tunnel (requires --tunnel-port)")
    parser.add_argument("--tunnel-port", type=int, default=1235,
                        help="SSH tunnel port for remote oMLX (default: 1235)")
    parser.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT,
                        help=f"Backend timeout in seconds (default: {DEFAULT_TIMEOUT})")
    args = parser.parse_args()

    # Validate
    if not args.local and not args.remote:
        parser.error("must specify --local or --remote")
    if args.remote and args.tunnel_port == 1235:
        pass  # default
    root = Path(args.root)

    # Resolve roles
    display_names: Dict[str, str] = {}
    roles = resolve_roles(root)
    for role, (model_key, leaf, ctx_label, load) in roles.items():
        # Skip embeddings and edit-only roles (chat model picker only)
        if "embed" in model_key:
            continue
        display_names[role] = build_display_name(role, model_key, leaf, ctx_label, load)

    if not display_names:
        print("[model-proxy] WARNING: no roles resolved, models unenriched", file=sys.stderr)

    # Backend URL
    if args.local:
        backend = f"http://127.0.0.1:1234"
    else:
        backend = f"http://127.0.0.1:{args.tunnel_port}"

    ProxyHandler.display_names = display_names
    ProxyHandler.backend_url = backend
    ProxyHandler.timeout_secs = args.timeout

    server = http.server.HTTPServer(("127.0.0.1", args.port), ProxyHandler)
    mode = "local" if args.local else "remote"
    print(f"[model-proxy] {mode} listen 127.0.0.1:{args.port} -> {backend}", file=sys.stderr)
    print(f"[model-proxy] roles: {sorted(display_names.keys())}", file=sys.stderr)
    print(f"[model-proxy] timeout: {args.timeout}s", file=sys.stderr)
    sys.stderr.flush()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    server.server_close()


if __name__ == "__main__":
    main()
