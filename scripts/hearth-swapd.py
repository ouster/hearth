#!/usr/bin/env python3
# Sub-key-scoped swap sidecar on 127.0.0.1:HEARTH_SWAP_PORT (ADR 0049).
# Auth: Bearer must get 200 from oMLX GET /v1/models. Then runs demand-load.sh,
# which reads the host token itself. Bind loopback only.
#
# The host token is never in this process's environment: host_token() reads
# ~/.config/hearth/env when GET /v1/hearth/agent needs the admin API, the
# same parse as ai_load_env in scripts/lib.sh.
import json
import os
import subprocess
import sys
import threading
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = "127.0.0.1"
OMLX_PORT = os.environ.get("HEARTH_PORT", "1234")
SWAP_PORT = int(os.environ.get("HEARTH_SWAP_PORT", "1236"))
ROOT = os.environ.get("HEARTH_ROOT") or os.environ.get("ROOT") or ""
ENV_FILE = os.environ.get("HEARTH_ENV") or os.path.expanduser("~/.config/hearth/env")
ROLES_TSV = os.environ.get("HEARTH_ROLES_TSV") or ""
DEMAND = os.path.join(ROOT, "scripts", "demand-load.sh") if ROOT else ""

# One swap at a time. Status requests do not take it.
_swap_lock = threading.Lock()
MAX_BODY = 4096
# Seconds a client may take to send its request. Without it one idle
# connection would hold a thread for ever.
SOCKET_TIMEOUT = 30


def host_token():
    try:
        with open(ENV_FILE) as fh:
            lines = fh.read().splitlines()
    except OSError:
        return ""
    val = ""
    for line in lines:
        t = line.strip()
        if t.startswith("export "):
            t = t[7:].lstrip()
        if t.startswith("OMLX_HOST_TOKEN="):
            val = t.split("=", 1)[1]
    for q in ('"', "'"):
        if val.endswith(q):
            val = val[:-1]
        if val.startswith(q):
            val = val[1:]
    if not val or val.endswith("...") or "CHANGEME" in val:
        return ""
    return val


def _http_status(url, bearer, timeout=8):
    req = urllib.request.Request(url)
    req.add_header("Authorization", "Bearer " + bearer)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status
    except urllib.error.HTTPError as e:
        return e.code
    except Exception:
        return 0


def auth_ok(bearer):
    if not bearer:
        return False
    return _http_status(
        "http://127.0.0.1:%s/v1/models" % OMLX_PORT, bearer
    ) == 200


def parse_roles():
    role_to_leaf = {}
    for line in ROLES_TSV.splitlines():
        f = line.split("\t")
        if len(f) < 8 or f[1] != "omlx" or f[5] in ("", "-"):
            continue
        leaf = f[5].rstrip("/").split("/")[-1]
        role_to_leaf[f[0]] = leaf
    return role_to_leaf


def admin_listing():
    import http.cookiejar

    token = host_token()
    if not token:
        raise RuntimeError("host token missing")
    jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
    base = "http://127.0.0.1:%s" % OMLX_PORT

    def call(method, path, body=None, timeout=30):
        data = None if body is None else json.dumps(body).encode()
        req = urllib.request.Request(base + path, data=data, method=method)
        req.add_header("Content-Type", "application/json")
        req.add_header("Authorization", "Bearer " + token)
        try:
            with opener.open(req, timeout=timeout) as resp:
                raw = resp.read().decode()
                return resp.status, (json.loads(raw) if raw else {})
        except urllib.error.HTTPError as e:
            raw = e.read().decode(errors="replace")
            try:
                parsed = json.loads(raw)
            except ValueError:
                parsed = {"detail": raw[:300]}
            return e.code, parsed

    code, _ = call("POST", "/admin/api/login", {"api_key": token})
    if code != 200:
        raise RuntimeError("admin login failed (%s)" % code)
    code, body = call("GET", "/admin/api/models")
    if code != 200:
        raise RuntimeError("admin models failed (%s)" % code)
    return {m.get("id"): m for m in body.get("models") or []}


def current_agent():
    role_to_leaf = parse_roles()
    models = admin_listing()
    for name in ("deep-brain", "coding-brain", "main-brain"):
        leaf = role_to_leaf.get(name)
        if leaf and (models.get(leaf) or {}).get("loaded"):
            return name
    return None


def run_demand(role, action):
    if not DEMAND or not os.path.isfile(DEMAND):
        return 2, "", "demand-load.sh missing"
    # demand-load.sh loads the host token from the env file itself.
    env = os.environ.copy()
    env.pop("OMLX_HOST_TOKEN", None)
    proc = subprocess.Popen(
        ["/bin/bash", DEMAND, role, action],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        cwd=ROOT or None,
    )
    out, err = proc.communicate()
    return (
        proc.returncode,
        out.decode(errors="replace").strip(),
        err.decode(errors="replace").strip(),
    )


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    timeout = SOCKET_TIMEOUT

    def log_message(self, fmt, *args):
        sys.stderr.write("hearth-swapd: %s\n" % (fmt % args))

    def _bearer(self):
        h = self.headers.get("Authorization") or ""
        if h.lower().startswith("bearer "):
            return h[7:].strip()
        return ""

    def _send(self, code, body, content_type="text/plain; charset=utf-8"):
        data = body.encode("utf-8") if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(data)

    def _send_json(self, code, obj):
        self._send(code, json.dumps(obj) + "\n", "application/json")

    def _require_auth(self):
        if not auth_ok(self._bearer()):
            self._send(401, "unauthorized\n")
            return False
        return True

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path != "/v1/hearth/agent":
            self._send(404, "not found\n")
            return
        if not self._require_auth():
            return
        if not ROLES_TSV.strip():
            self._send(503, "roles not resolved on this host\n")
            return
        try:
            self._send_json(200, {"agent": current_agent()})
        except Exception as e:
            self._send(502, "agent check failed: %s\n" % e)

    def do_POST(self):
        path = self.path.split("?", 1)[0]
        if path != "/v1/hearth/load":
            self._send(404, "not found\n")
            return
        if not self._require_auth():
            return
        try:
            length = int(self.headers.get("Content-Length") or "0")
        except ValueError:
            length = -1
        if length < 0 or length > MAX_BODY:
            self._send(400, "bad Content-Length\n")
            return
        raw = self.rfile.read(length) if length > 0 else b"{}"
        try:
            body = json.loads(raw.decode("utf-8") or "{}")
        except ValueError:
            self._send(400, "bad json\n")
            return
        if not isinstance(body, dict):
            self._send(400, "bad json\n")
            return
        role = body.get("role") or ""
        action = body.get("action") or ""
        if role not in ("coding-brain", "deep-brain"):
            self._send(400, "role must be coding-brain or deep-brain\n")
            return
        if action not in ("up", "down"):
            self._send(400, "action must be up or down\n")
            return
        with _swap_lock:
            code, out, err = run_demand(role, action)
        if code == 0:
            self._send(200, (out or "ok") + "\n")
            return
        if code == 2:
            self._send(422, (err or out or "refused") + "\n")
            return
        self._send(502, (err or out or "demand-load failed") + "\n")


def main():
    if not ROOT:
        sys.stderr.write("hearth-swapd: HEARTH_ROOT not set\n")
        return 2
    if not host_token():
        sys.stderr.write("hearth-swapd: OMLX_HOST_TOKEN not set in %s\n" % ENV_FILE)
        return 2
    if not os.path.isfile(DEMAND):
        sys.stderr.write("hearth-swapd: missing %s\n" % DEMAND)
        return 2
    ThreadingHTTPServer.daemon_threads = True
    server = ThreadingHTTPServer((HOST, SWAP_PORT), Handler)
    sys.stderr.write(
        "hearth-swapd: listening on %s:%s (oMLX :%s)\n" % (HOST, SWAP_PORT, OMLX_PORT)
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
