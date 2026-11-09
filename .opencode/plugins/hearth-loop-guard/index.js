// Hearth loop guard for OpenCode (ADR 0043). Shells out to scripts/loop-guard.sh.
// Fails open if the guard is missing or errors. Throw refuses the tool call.
// Load shapes: OpenCode 1.x named export / server(), and 2.x setup()+hook.

import { spawnSync } from "node:child_process"
import { fileURLToPath } from "node:url"
import path from "node:path"

const MARK = "hearth loop guard"
const here = path.dirname(fileURLToPath(import.meta.url))
const GUARD =
  process.env.HEARTH_LOOP_GUARD ||
  path.resolve(here, "../../../scripts/loop-guard.sh")

function check(tool, args, sessionID) {
  if (!tool) return
  const input = JSON.stringify({
    session_id: sessionID || "opencode",
    tool_name: tool,
    tool_input: args && typeof args === "object" ? args : {},
  })
  const r = spawnSync(
    GUARD,
    ["--format", "opencode", "--workspace"],
    {
      input,
      encoding: "utf8",
      timeout: 5000,
      env: {
        ...process.env,
        PATH: `/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:${process.env.PATH || ""}`,
      },
    },
  )
  if (r.error || r.status !== 0) return
  let out
  try {
    out = JSON.parse((r.stdout || "").trim() || "{}")
  } catch {
    return
  }
  if (out.allow === false) {
    throw new Error(out.errorMessage || `${MARK}: denied`)
  }
}

function before(input, output) {
  const tool = input?.tool || input?.toolName || ""
  const args = output?.args ?? input?.args ?? input?.tool_input ?? {}
  const sid = input?.sessionID || input?.sessionId || input?.session_id || ""
  check(tool, args, sid)
}

export const HearthLoopGuard = async () => ({
  "tool.execute.before": before,
})

export default {
  id: "hearth-loop-guard",
  name: MARK,
  server() {
    return { "tool.execute.before": before }
  },
  async setup(ctx) {
    if (!ctx?.tool?.hook) return
    await ctx.tool.hook("execute.before", (event) => {
      check(event?.tool, event?.input ?? event?.args, event?.sessionID)
    })
  },
}
