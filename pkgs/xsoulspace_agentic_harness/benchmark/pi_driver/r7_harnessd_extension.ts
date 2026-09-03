// r7_harnessd_extension.ts — pi extension (TASK 3, option a): registers
// daemon-backed tools (scan/zoom/impact/edit/verify) over stdio JSON-RPC to
// `harnessd` and BLOCKS pi's built-in file tools for sessions flagged with
// PI_HARNESSD=1.
//
// Use (from the apple_foundation package, where the daemon lives):
//   dart run bin/harnessd.dart --profile meaning   # in another shell, OR
//   let this extension spawn it (HARNESSD_PKG points at that package)
//   PI_HARNESSD=1 HARNESSD_PKG=../../xsoulspace_inference_apple_foundation \
//     pi -e benchmark/pi_driver/r7_harnessd_extension.ts
//
// The daemon runs `--profile meaning` (R7 surface: repo_etl / meaning_zoom
// / meaning_impact / edit_symbol / run — zero `read`, zero `write`) and
// optionally `--scripted` for LLM-free gates. Every file access pi makes
// goes through the daemon; the daemon tools are the only code surface.

import { spawn } from "node:child_process";
import process from "node:process";

// --- minimal ACP client (newline-delimited JSON-RPC over stdio) ----------

class HarnessdClient {
  proc: any;
  buffer = "";
  pending = new Map<
    number,
    { resolve: (v: any) => void; reject: (e: Error) => void }
  >();
  updates: any[] = [];
  nextId = 1;
  sessionId = "";

  constructor(command: string, args: string[], cwd: string) {
    this.proc = spawn(command, args, { cwd, stdio: ["pipe", "pipe", "pipe"] });
    this.proc.stdout.setEncoding("utf8");
    this.proc.stdout.on("data", (chunk: string) => this.#onData(chunk));
    this.proc.stderr.setEncoding("utf8");
    this.proc.stderr.on("data", (chunk: string) =>
      process.stderr.write(`[harnessd] ${chunk}`),
    );
  }

  #onData(chunk: string) {
    this.buffer += chunk;
    let idx: number;
    while ((idx = this.buffer.indexOf("\n")) >= 0) {
      const line = this.buffer.slice(0, idx).trim();
      this.buffer = this.buffer.slice(idx + 1);
      if (!line) continue;
      let message: any;
      try {
        message = JSON.parse(line);
      } catch {
        continue;
      }
      if (message.id != null && (message.result || message.error)) {
        const pending = this.pending.get(message.id);
        if (pending) {
          this.pending.delete(message.id);
          if (message.error) {
            pending.reject(new Error(JSON.stringify(message.error)));
          } else {
            pending.resolve(message.result);
          }
        }
        return;
      }
      if (message.method === "session/update") {
        // dart_acp_toolkit wraps: params = {sessionId, update}.
        this.updates.push(message.params?.update ?? message.params);
      }
    }
  }

  call(method: string, params: any, timeoutMs = 900000): Promise<any> {
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      setTimeout(() => {
        if (this.pending.has(id)) {
          this.pending.delete(id);
          reject(new Error(`${method} timed out`));
        }
      }, timeoutMs);
      this.proc.stdin.write(
        `${JSON.stringify({ jsonrpc: "2.0", id, method, params })}\n`,
      );
    });
  }

  async start(workspace: string) {
    const init = await this.call("initialize", {
      protocolVersion: 1,
      clientCapabilities: {},
    });
    const created = await this.call("session/new", { cwd: workspace });
    this.sessionId = created.sessionId;
    return init;
  }

  async prompt(text: string): Promise<{ text: string; updates: any[] }> {
    this.updates = [];
    await this.call("session/prompt", {
      sessionId: this.sessionId,
      prompt: [{ type: "text", text }],
    });
    return {
      text: this.updates
        .filter((u: any) => u.sessionUpdate === "agent_message_chunk")
        .map((u: any) => u.content?.text ?? "")
        .join(""),
      updates: this.updates,
    };
  }

  dispose() {
    try {
      this.proc.kill();
    } catch {
      // best effort
    }
  }
}

// --- the extension -------------------------------------------------------

let client: HarnessdClient | null = null;

const DAEMON_TOOL_NAMES = [
  "harness_scan",
  "harness_zoom",
  "harness_impact",
  "harness_edit",
  "harness_verify",
];

interface PiAPI {
  registerTool(def: any): void;
  setActiveTools?(names: string[]): void;
}

export default function (pi: PiAPI) {
  const enabled = process.env.PI_HARNESSD === "1";
  const workspace = process.cwd();
  const daemonPkg = process.env.HARNESSD_PKG ?? ".";
  const scripted = process.env.HARNESSD_SCRIPTED === "1";

  const ensureClient = (): HarnessdClient => {
    if (client) return client;
    client = new HarnessdClient(
      "dart",
      [
        "run",
        "bin/harnessd.dart",
        "--profile",
        "meaning",
        ...(scripted ? ["--scripted"] : []),
      ],
      daemonPkg,
    );
    return client;
  };

  const delegated = async (
    directive: string,
  ): Promise<{ content: any[]; details: Record<string, unknown> }> => {
    const c = ensureClient();
    if (!c.sessionId) await c.start(workspace);
    const { text, updates } = await c.prompt(directive);
    return {
      content: [{ type: "text", text: text || "(daemon returned no text)" }],
      details: { daemonUpdateCount: updates.length, directive },
    };
  };

  pi.registerTool({
    name: "harness_scan",
    label: "Harness Scan",
    description:
      "Scan this workspace into the harnessd meaning tree (the code graph " +
      "you work through). Call once before zoom/impact/edit. No file " +
      "reads — the tree is the code interface.",
    parameters: { type: "object", properties: {}, required: [] },
    execute: async () => delegated("[scan]"),
  });

  pi.registerTool({
    name: "harness_zoom",
    label: "Harness Zoom",
    description:
      "Cut a bounded view of the meaning tree by keyword query. This is " +
      "how you READ structure — never file reads.",
    parameters: {
      type: "object",
      properties: { query: { type: "string" } },
      required: ["query"],
    },
    execute: async (_id: string, params: any) =>
      delegated(`[zoom ${params.query}]`),
  });

  pi.registerTool({
    name: "harness_impact",
    label: "Harness Impact",
    description:
      "Impact frontier of a symbol (reverse-reference closure, " +
      "hard-capped) — the decomposition input for any change.",
    parameters: {
      type: "object",
      properties: { symbol: { type: "string" } },
      required: ["symbol"],
    },
    execute: async (_id: string, params: any) =>
      delegated(`[impact ${params.symbol}]`),
  });

  pi.registerTool({
    name: "harness_edit",
    label: "Harness Edit",
    description:
      "Edit code through the daemon: rename a symbol across its refs " +
      "frontier (atomic, analyzer-verified, auto-reverted on failure). " +
      "There is NO write tool — edits move through meaning.",
    parameters: {
      type: "object",
      properties: { oldName: { type: "string" }, newName: { type: "string" } },
      required: ["oldName", "newName"],
    },
    execute: async (_id: string, params: any) =>
      delegated(`[rename ${params.oldName} ${params.newName}]`),
  });

  pi.registerTool({
    name: "harness_verify",
    label: "Harness Verify",
    description:
      "Verify the workspace green through the daemon (dart analyze + the " +
      "workspace convention). Failed moves were already auto-reverted.",
    parameters: { type: "object", properties: {}, required: [] },
    execute: async () => delegated("[verify]"),
  });

  if (enabled) {
    // PI_HARNESSD=1: the daemon is the ONLY file surface — pi's built-in
    // fs tools are disabled for the whole session.
    pi.setActiveTools?.(DAEMON_TOOL_NAMES);
  }
}