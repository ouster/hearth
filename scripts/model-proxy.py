#!/usr/bin/env python3
"""Loopback proxy that adds display_name to oMLX's /v1/models (ADR 0051).

    scripts/model-proxy.py [--port 1238] [--root REPO] [--timeout SECS]

Listens on 127.0.0.1:PORT and forwards everything to this machine's oMLX on
127.0.0.1:HEARTH_PORT (1234). GET /v1/models gains a display_name per role,
in the shape scripts/zed-sync.sh writes: "role — leaf — ctx × slots". Every
other request passes through untouched and streams as it arrives.

It holds no key. The client's own Authorization header is forwarded as sent,
so a request without a key gets oMLX's 401, exactly as on :1234. It never
reads ~/.config/hearth/env.

Local oMLX only. A dual machine's hearth-remote provider stays on the tunnel
(:1235): the labels here come from this machine's roles.tsv and RAM tier.

Exit 0 stopped, 2 could not start (roles unresolved, port in use).
"""
from __future__ import annotations

import argparse
import http.client
import json
import os
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Dict, Optional

DEFAULT_PORT = 1238
# A long prompt can prefill for minutes before the first byte.
DEFAULT_TIMEOUT = 1800
BACKEND_HOST = "127.0.0.1"
BACKEND_PORT = int(os.environ.get("HEARTH_PORT") or "1234")
REPO_ROOT = Path(__file__).resolve().parent.parent

# Not forwarded in either direction. http.client sets Host and Content-Length
# itself and decodes chunked bodies, so the originals would be wrong.
HOP_HEADERS = frozenset((
    "host", "connection", "keep-alive", "proxy-authenticate",
    "proxy-authorization", "proxy-connection", "te", "trailer",
    "transfer-encoding", "upgrade", "content-length",
))


def log(msg: str) -> None:
    sys.stderr.write("[model-proxy] %s\n" % msg)
    sys.stderr.flush()


# ── labels ────────────────────────────────────────────────────────────────

def resolved_rows(root: Path) -> list:
    """This host's rows from lib.sh's hearth_resolved_roles (RAM tier applied).

    Eight tab-separated columns: role backend key ctx slots weights draft load.
    Raises RuntimeError when the helper cannot run or prints nothing.
    """
    script = 'ROOT="$1"; . "$ROOT/scripts/lib.sh" && hearth_resolved_roles'
    try:
        proc = subprocess.run(
            ["/bin/bash", "-c", script, "model-proxy", str(root)],
            capture_output=True, text=True, timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired) as e:
        raise RuntimeError("hearth_resolved_roles could not run: %s" % e)
    if proc.returncode != 0:
        raise RuntimeError("hearth_resolved_roles exit %d: %s"
                           % (proc.returncode, proc.stderr.strip()))
    rows = [l.split("\t") for l in proc.stdout.splitlines() if l.strip()]
    rows = [r for r in rows if len(r) >= 8]
    if not rows:
        raise RuntimeError("hearth_resolved_roles printed no rows")
    return rows


def build_labels(rows: list) -> Dict[str, str]:
    """{role: display_name}, same rules and wording as scripts/zed-sync.sh."""
    labels: Dict[str, str] = {}
    for role, backend, key, ctx, slots, weights, _draft, load in (r[:8] for r in rows):
        # Chat model picker only: no cloud rows, embeddings or edit prediction.
        if backend != "omlx" or "embed" in key or load == "edit":
            continue
        leaf = weights.rstrip("/").split("/")[-1] if weights and weights != "-" else ""
        try:
            ctx_n = int(ctx)
            slot_n = int(slots) if slots.isdigit() else 0
        except ValueError:
            ctx_n, slot_n = 0, 0
        ctx_label = "%dK" % (ctx_n // 1024) if ctx_n >= 1024 else ctx
        if leaf and slot_n:
            label = "%s — %s — %s × %s" % (role, leaf, ctx_label, slot_n)
        elif leaf:
            label = "%s — %s" % (role, leaf)
        else:
            label = role
        if load in ("beside", "swap"):
            label += " — load first: scripts/demand-load.sh " + role + " up"
        labels[role] = label
    return labels


class Labels:
    """Labels, rebuilt when config/roles.tsv changes on disk."""

    def __init__(self, root: Path) -> None:
        self.root = root
        self.tsv = root / "config" / "roles.tsv"
        self.mtime = self._mtime()
        self.current = build_labels(resolved_rows(root))  # raises at startup

    def _mtime(self) -> float:
        try:
            return self.tsv.stat().st_mtime
        except OSError:
            return 0.0

    def get(self) -> Dict[str, str]:
        m = self._mtime()
        if m != self.mtime:
            self.mtime = m
            try:
                self.current = build_labels(resolved_rows(self.root))
                log("roles.tsv changed; labels rebuilt: %s" % sorted(self.current))
            except RuntimeError as e:
                log("roles.tsv changed but labels not rebuilt, keeping old: %s" % e)
        return self.current


# ── proxy ─────────────────────────────────────────────────────────────────

class ProxyHandler(BaseHTTPRequestHandler):
    # HTTP/1.0 on the client side: no Content-Length means the body ends when
    # the connection closes, which is valid framing for an SSE stream.
    labels: Labels
    timeout_secs: int = DEFAULT_TIMEOUT

    def log_message(self, format: str, *args) -> None:  # noqa: A002
        log(format % args)

    def _forward_headers(self) -> Dict[str, str]:
        return {k: v for k, v in self.headers.items() if k.lower() not in HOP_HEADERS}

    def _read_body(self) -> Optional[bytes]:
        if "chunked" in (self.headers.get("Transfer-Encoding") or "").lower():
            raise ValueError("chunked request bodies are not supported")
        length = int(self.headers.get("Content-Length") or "0")
        if length < 0:
            raise ValueError("bad Content-Length")
        return self.rfile.read(length) if length else None

    def _send_error_json(self, status: int, message: str) -> None:
        data = json.dumps({"error": {"message": message, "type": "model_proxy"}}).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _handle(self) -> None:
        try:
            body = self._read_body()
        except ValueError as e:
            self._send_error_json(400, str(e))
            return
        headers = self._forward_headers()
        is_models = self.command == "GET" and self.path.split("?")[0].rstrip("/") == "/v1/models"
        if is_models:
            # The body is parsed below, so ask for it uncompressed.
            headers = {k: v for k, v in headers.items() if k.lower() != "accept-encoding"}

        conn = http.client.HTTPConnection(BACKEND_HOST, BACKEND_PORT, timeout=self.timeout_secs)
        sent = False
        try:
            try:
                conn.request(self.command, self.path, body=body, headers=headers)
                resp = conn.getresponse()
            except (OSError, http.client.HTTPException) as e:
                self._send_error_json(
                    502, "oMLX on %s:%d did not answer: %s" % (BACKEND_HOST, BACKEND_PORT, e))
                return

            if is_models:
                sent = True
                self._send_models(resp)
                return

            self.send_response(resp.status)
            for key, val in resp.getheaders():
                # Content-Length survives only when the body is not re-framed.
                low = key.lower()
                if low in HOP_HEADERS and low != "content-length":
                    continue
                if low == "content-length" and resp.chunked:
                    continue
                self.send_header(key, val)
            self.end_headers()
            sent = True
            if self.command == "HEAD":
                return
            # read1 returns what has arrived, so each SSE event goes out at
            # once. read(n) would wait for n bytes or the end of the body.
            while True:
                chunk = resp.read1(65536)
                if not chunk:
                    break
                self.wfile.write(chunk)
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass  # the client went away; closing the backend cancels the turn
        except (OSError, http.client.HTTPException) as e:
            log("backend failed mid-response: %s" % e)
            if not sent:
                self._send_error_json(502, "oMLX failed mid-response: %s" % e)
        finally:
            conn.close()

    def _send_models(self, resp: http.client.HTTPResponse) -> None:
        """Add display_name on a 200 JSON list. Anything else passes as is."""
        data = resp.read()
        ctype = resp.getheader("Content-Type") or "application/json"
        if resp.status == 200:
            try:
                doc = json.loads(data)
                labels = self.labels.get()
                for model in doc.get("data") or []:
                    label = labels.get(model.get("id", ""))
                    if label:
                        model["display_name"] = label
                data = json.dumps(doc, ensure_ascii=False).encode("utf-8")
                ctype = "application/json; charset=utf-8"
            except (ValueError, AttributeError, TypeError):
                pass  # not the shape we know: send oMLX's bytes unchanged
        self.send_response(resp.status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = do_OPTIONS = do_HEAD = _handle


def main() -> int:
    parser = argparse.ArgumentParser(description="oMLX model display proxy (ADR 0051)")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--root", default=str(REPO_ROOT),
                        help="Hearth repo root (default: this script's parent)")
    parser.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT,
                        help="seconds to wait on oMLX (default: %d)" % DEFAULT_TIMEOUT)
    args = parser.parse_args()

    # No fallback: a guessed label is worse than none (wrong tier, wrong model).
    try:
        labels = Labels(Path(args.root).resolve())
    except RuntimeError as e:
        log("cannot resolve roles: %s" % e)
        return 2

    ProxyHandler.labels = labels
    ProxyHandler.timeout_secs = args.timeout
    ThreadingHTTPServer.daemon_threads = True
    try:
        server = ThreadingHTTPServer(("127.0.0.1", args.port), ProxyHandler)
    except OSError as e:
        log("cannot listen on 127.0.0.1:%d: %s" % (args.port, e))
        return 2
    log("listen 127.0.0.1:%d -> %s:%d, timeout %ds" % (args.port, BACKEND_HOST, BACKEND_PORT, args.timeout))
    log("roles: %s" % sorted(labels.current))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    server.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
