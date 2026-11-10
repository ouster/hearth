#!/usr/bin/env node
// stdio front for the pinned mcp-searxng (ADR 0045).
//
// Clients that cannot hide individual tools (Cline) would otherwise see
// web_url_read. This process advertises searxng_web_search only, and it
// refuses a call to anything else. It always points the child at
// http://127.0.0.1:8888. A SEARXNG_URL in the environment is ignored, so a
// client config cannot send the query to another machine or a public instance.
//
// Never npx. The child is the pinned install under ~/.local/share/hearth.

import { spawn } from "node:child_process";
import { createInterface } from "node:readline";
import { existsSync } from "node:fs";
import { homedir } from "node:os";

const ALLOWED = "searxng_web_search";
const LOCAL_URL = "http://127.0.0.1:8888";
const nodeBin = "/opt/homebrew/bin/node";
const entry =
  homedir() +
  "/.local/share/hearth/mcp-searxng/node_modules/mcp-searxng/dist/cli.js";

if (!existsSync(nodeBin) || !existsSync(entry)) {
  process.stderr.write(
    "searxng-mcp: pinned server missing at " +
      entry +
      "\nInstall it as docs/MCP.md describes. Do not use npx.\n"
  );
  process.exit(1);
}

const env = { ...process.env };
for (const key of [
  "MCP_HTTP_PORT",
  "MCP_HTTP_HOST",
  "SEARXNG_URL",
  "SEARXNG_FANOUT",
  "SEARXNG_HTML_FALLBACK",
]) {
  delete env[key];
}
env.SEARXNG_URL = LOCAL_URL;
env.SEARXNG_LITE_TOOLS = "true";
env.SEARXNG_MAX_RESULTS = "10";

const child = spawn(nodeBin, [entry], {
  env,
  stdio: ["pipe", "pipe", "inherit"],
});

const pendingList = new Set();

function reply(msg) {
  process.stdout.write(JSON.stringify(msg) + "\n");
}

function forward(line) {
  child.stdin.write(line + "\n");
}

const fromClient = createInterface({ input: process.stdin });
fromClient.on("line", (line) => {
  let msg;
  try {
    msg = JSON.parse(line);
  } catch {
    forward(line);
    return;
  }
  if (msg && msg.method === "tools/call") {
    const name = msg.params && msg.params.name;
    if (name !== ALLOWED) {
      reply({
        jsonrpc: "2.0",
        id: msg.id ?? null,
        error: {
          code: -32601,
          message: "only searxng_web_search is enabled",
        },
      });
      return;
    }
  }
  if (
    msg &&
    msg.method === "tools/list" &&
    Object.prototype.hasOwnProperty.call(msg, "id")
  ) {
    pendingList.add(msg.id);
  }
  forward(line);
});

fromClient.on("close", () => {
  child.stdin.end();
});

const fromChild = createInterface({ input: child.stdout });
fromChild.on("line", (line) => {
  let msg;
  try {
    msg = JSON.parse(line);
  } catch {
    process.stdout.write(line + "\n");
    return;
  }
  if (
    msg &&
    Object.prototype.hasOwnProperty.call(msg, "id") &&
    pendingList.has(msg.id)
  ) {
    pendingList.delete(msg.id);
    if (msg.result && Array.isArray(msg.result.tools)) {
      msg.result.tools = msg.result.tools.filter(
        (tool) => tool && tool.name === ALLOWED
      );
      reply(msg);
      return;
    }
  }
  process.stdout.write(line + "\n");
});

child.on("exit", (code, signal) => {
  if (signal) process.exit(1);
  process.exit(code == null ? 1 : code);
});

child.on("error", (err) => {
  process.stderr.write("searxng-mcp: " + err.message + "\n");
  process.exit(1);
});
