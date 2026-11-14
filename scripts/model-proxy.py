#!/usr/bin/env python3
"""Proxy for oMLX that enriches /v1/models with display_name from roles.tsv.

Forwards all non-model requests unchanged to the oMLX backend.
Reads role definitions from config/roles.tsv (default: relative to this script's dir).

Usage:
    scripts/model-proxy.py [--port PORT] [--role-config PATH] [--backend URL]
"""

import argparse
import http.client
import http.server
import json
import os
import sys
from pathlib import Path
from urllib.parse import urlparse


def read_api_key() -> str | None:
    """Read oMLX API key from ~/.config/hearth/env (OMLX_HOST_TOKEN)."""
    env_path = Path.home() / ".config" / "hearth" / "env"
    if env_path.exists():
        for line in env_path.read_text().splitlines():
            if line.startswith("OMLX_HOST_TOKEN="):
                return line.split("=", 1)[1]
    return None


def parse_roles(path: Path) -> dict:
    """Parse roles.tsv and return {role_name: model_info}."""
    roles: dict = {}
    with open(path) as f:
        lines = f.readlines()
    data_lines = [
        l for l in lines
        if l.strip() and not l.strip().startswith("#")
    ]
    for line in data_lines:
        parts = line.split("\t")
        if len(parts) < 9:
            continue
        role, backend, model_key, _, _, weights, _, load, min_ram = parts[:9]
        roles[role] = {
            "backend": backend,
            "model_key": model_key,
            "weights": weights,
            "load": load,
            "min_ram": min_ram,
        }
    return roles


def build_display_name(role: str, info: dict) -> str:
    """Build display_name like Zed's config: role — model_key."""
    model_key = info["model_key"]
    name = f"{role} \u2014 {model_key}"
    load = info["load"]
    if load == "swap":
        name += " \u2014 swap (load via demand-load.sh)"
    elif load == "edit":
        name += " \u2014 editor edit prediction (laptop only)"
    elif load == "resident":
        name += " \u2014 resident"
    return name


def read_roles_tsv() -> dict:
    """Find and parse roles.tsv."""
    env_path = os.environ.get("HEARTH_MODEL_PROXY_ROLES")
    if env_path:
        return parse_roles(Path(env_path))

    script_dir = Path(__file__).resolve().parent
    candidates = [
        script_dir / ".." / "config" / "roles.tsv",
        Path("/Users/ouster/dev/hearth/config/roles.tsv"),
    ]
    for candidate in candidates:
        if candidate.exists():
            return parse_roles(candidate)
    return {}


class ProxyHandler(http.server.BaseHTTPRequestHandler):
    # Chat completions forward to oMLX backend. Default is local :1234.
    # Change to http://127.0.0.1:1235 to forward through SSH tunnel (remote oMLX).
    backend_url = "http://127.0.0.1:1234"
    roles = {}

    def log_message(self, format, *args):
        sys.stderr.write(f"[model-proxy] {format % args}\n")
        sys.stderr.flush()

    def _proxy_request(self, path, body=None):
        """Forward a request to the oMLX backend."""
        backend = urlparse(self.backend_url)
        headers = dict(self.headers)
        headers.pop("host", None)
        headers.pop("transfer-encoding", None)
        headers.pop("content-length", None)

        # Forward API key if backend requires it
        api_key = read_api_key()
        if api_key and "Authorization" not in headers:
            headers["Authorization"] = f"Bearer {api_key}"

        conn = http.client.HTTPConnection(backend.hostname, backend.port, timeout=30)
        try:
            conn.request(self.command, path, body=body, headers=headers)
            resp = conn.getresponse()
            resp_body = resp.read()

            self.send_response(resp.status)
            for hdr in resp.getheaders():
                key, val = hdr
                if key.lower() in ("transfer-encoding", "connection"):
                    continue
                self.send_header(key, val)
            self.end_headers()
            self.wfile.write(resp_body)
        finally:
            conn.close()

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        if path == "/v1/models":
            self._handle_models()
        else:
            self._proxy_request(self.path)

    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path
        if path == "/v1/models":
            self._handle_models()
        else:
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length) if content_length > 0 else None
            self._proxy_request(self.path, body)

    def _handle_models(self):
        """Enrich /v1/models with display_name from roles.tsv."""
        backend = urlparse(self.backend_url)
        headers = {}
        api_key = read_api_key()
        if api_key:
            headers["Authorization"] = f"Bearer {api_key}"

        conn = http.client.HTTPConnection(backend.hostname, backend.port, timeout=10)
        try:
            conn.request("GET", "/v1/models", headers=headers)
            resp = conn.getresponse()
            data = resp.read()
            models_resp = json.loads(data)
        finally:
            conn.close()

        if "data" in models_resp:
            for model in models_resp["data"]:
                role_id = model.get("id", "")
                if role_id in self.roles:
                    model["display_name"] = build_display_name(
                        role_id, self.roles[role_id]
                    )

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(models_resp).encode())


def main():
    parser = argparse.ArgumentParser(description="oMLX model display proxy")
    parser.add_argument("--port", type=int, default=1238, help="Listen port")
    parser.add_argument("--role-config", default=None, help="Path to roles.tsv")
    parser.add_argument("--backend", default="http://127.0.0.1:1234", help="oMLX URL")
    args = parser.parse_args()

    if args.role_config:
        roles = parse_roles(Path(args.role_config))
    else:
        roles = read_roles_tsv()

    if not roles:
        print("[model-proxy] WARNING: no roles found, models will not be enriched", file=sys.stderr)

    ProxyHandler.roles = roles
    ProxyHandler.backend_url = args.backend

    server = http.server.HTTPServer(("127.0.0.1", args.port), ProxyHandler)
    print(f"[model-proxy] listening on 127.0.0.1:{args.port}", file=sys.stderr)
    print(f"[model-proxy] forwarding to {args.backend}", file=sys.stderr)
    print(f"[model-proxy] roles loaded: {list(roles.keys())}", file=sys.stderr)
    sys.stderr.flush()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    server.server_close()


if __name__ == "__main__":
    main()
