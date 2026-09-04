// r7_harnessd_extension.ts — pi extension (TASK 3, option a): registers
// daemon-backed tools (scan/zoom/impact/edit/verify) over JSON-RPC to
// `harnessd` and BLOCKS pi's built-in file tools for sessions flagged with
// PI_HARNESSD=1.
//
// R7 production #1: the id-bearing verbs (harness_impact, harness_edit)
// carry the STRUCTURED contract — the exact registry args (focusId /
// action, symbolId, classSymbolId, opChain, executableId,
// executableParams) serialized into the session/prompt as a JSON payload
// the daemon mover executes verbatim. No prose directives for edits.
//
// R7 production #5 — the PERSISTENT daemon lifecycle:
//   - connect-if-live: a daemon holding the workspace is reachable
//     through the socket pointer at
//     `<workspace>/.dart_tool/harnessd/harnessd.sock` (health ping =
//     initialize); a second pi session ATTACHES to the warm daemon — one
//     world per workspace, zero re-scan;
//   - spawn-if-absent: no live daemon → spawn one with --workspace (the
//     single-instance lock refuses racing spawns with exit 2) and attach
//     through the SAME socket (one transport, one code path);
//   - keep-warm: the daemon is NEVER killed on session end — it
//     self-idle-exits after 10 minutes without activity.
//
// Use:
//   PI_HARNESSD=1 HARNESSD_PKG=../../xsoulspace_inference_apple_foundation \
//     pi -e benchmark/pi_driver/r7_harnessd_extension.ts
//   (HARNESSD_SCRIPTED=1 runs the LLM-free scripted mover for gates.)
//
// The daemon runs `--profile meaning` (R7 surface: repo_etl / meaning_zoom
// / meaning_impact / edit_symbol / run — zero `read`, zero `write`). Every
// file access pi makes goes through the daemon; the daemon tools are the
// only code surface.

import { spawn, type ChildProcess } from "node:child_process";
import net from "node:net";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import process from "node:process";

// --- minimal ACP client (newline-delimited JSON-RPC; stdio OR socket) ----

class HarnessdClient {
  // stdio (spawned daemon) or net.Socket (attached to the warm daemon).
  wire: any;
  proc: ChildProcess | null = null;
  buffer = "";
  pending = new Map<
    number,
    { resolve: (v: any) => void; reject: (e: Error) => void }
  >();
  updates: any[] = [];
  nextId = 1;
  sessionId = "";

  static spawnDaemon(command: string, args: string[], cwd: string) {
    const client = new HarnessdClient();
    client.proc = spawn(command, args, { cwd, stdio: ["pipe", "pipe", "pipe"] });
    client.proc.stdout!.setEncoding("utf8");
    client.proc.stdout!.on("data", (chunk: string) => client.#onData(chunk));
    client.proc.stderr!.setEncoding("utf8");
    client.proc.stderr!.on("data", (chunk: string) =>
      process.stderr.write(`[harnessd] ${chunk}`),
    );
    client.wire = {
      write: (s: string) => client.proc!.stdin!.write(s),
    };
    return client;
  }

  static attachSocket(socketPath: string) {
    const client = new HarnessdClient();
    client.wire = net.createConnection(socketPath);
    client.wire.setEncoding("utf8");
    client.wire.on("data", (chunk: string) => client.#onData(chunk));
    return client;
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
        continue;
      }
      if (message.method === "session/update") {
        // dart_acp_toolkit wraps: params = {sessionId, update}.
        this.updates.push(message.params?.update ?? message.params);
        continue;
      }
      // Server-initiated REQUESTS:
      //   session/request_permission — the R7c edit approver; deny-by-
      //     default means an unanswering client DENIES the move. The
      //     extension answers allow (a real deployment renders the
      //     consent UI here).
      //   session/propose_move — the R7 production #4 remote-mover
      //     round-trip: the daemon's decision asks for typed tool calls.
      //     Answering it with a real model needs the pi model bridge; the
      //     scripted extension answers empty (the loop closes the
      //     decision) — use the gate drivers for remote-mover runs.
      if (message.method != null && message.id != null) {
        const response =
          message.method === "session/request_permission"
            ? { outcome: { outcome: "allow", optionId: "allow" } }
            : {};
        this.wire.write(
          `${JSON.stringify({ jsonrpc: "2.0", id: message.id, result: response })}\n`,
        );
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
      this.wire.write(
        `${JSON.stringify({ jsonrpc: "2.0", id, method, params })}\n`,
      );
    });
  }

  async start(workspace: string) {
    // The initialize doubles as the health ping (connect-if-live).
    const init = await this.call(
      "initialize",
      { protocolVersion: 1, clientCapabilities: {} },
      10000,
    );
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
    // R7 production #5 — KEEP-WARM: the daemon is never killed on session
    // end; it self-idle-exits (10 minutes without activity). A second pi
    // session attaches to the same world through the socket.
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

function socketPointerPath(workspace: string): string {
  return path.join(workspace, ".dart_tool", "harnessd", "harnessd.sock");
}

function readSocketPointer(workspace: string): string | null {
  const p = socketPointerPath(workspace);
  if (!existsSync(p)) return null;
  const real = readFileSync(p, "utf8").trim();
  return real || null;
}

function waitForPointer(workspace: string, timeoutMs: number): Promise<string> {
  return new Promise((resolve, reject) => {
    const started = Date.now();
    const t = setInterval(() => {
      const real = readSocketPointer(workspace);
      if (real) {
        clearInterval(t);
        resolve(real);
      } else if (Date.now() - started > timeoutMs) {
        clearInterval(t);
        reject(new Error("daemon socket pointer never appeared"));
      }
    }, 200);
  });
}

export default function (pi: PiAPI) {
  const enabled = process.env.PI_HARNESSD === "1";
  const workspace = process.cwd();
  const daemonPkg = process.env.HARNESSD_PKG ?? ".";
  const scripted = process.env.HARNESSD_SCRIPTED === "1";

  const ensureClient = async (): Promise<HarnessdClient> => {
    if (client) return client;
    // connect-if-live: a daemon holding this workspace answers the
    // initialize health ping over the socket pointer.
    const pointer = readSocketPointer(workspace);
    if (pointer) {
      try {
        const attached = HarnessdClient.attachSocket(pointer);
        await attached.start(workspace);
        client = attached;
        return client;
      } catch {
        // stale pointer (crashed daemon) — fall through to spawn.
      }
    }
    // spawn-if-absent: --workspace arms the single-instance lock + socket
    // listener; the extension attaches through the socket (uniform).
    const spawned = HarnessdClient.spawnDaemon(
      "dart",
      [
        "run",
        "bin/harnessd.dart",
        "--profile",
        "meaning",
        ...(scripted ? ["--scripted"] : []),
        "--workspace",
        workspace,
      ],
      daemonPkg,
    );
    const socketPath = await waitForPointer(workspace, 180000);
    spawned.wire.end?.(); // the spawned proc's stdio pipe is not used
    client = spawned; // retained so the process is not GC'd/reaped
    const attached = HarnessdClient.attachSocket(socketPath);
    await attached.start(workspace);
    client = attached;
    return client;
  };

  const delegated = async (
    directive: string,
  ): Promise<{ content: any[]; details: Record<string, unknown> }> => {
    const c = await ensureClient();
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
      "Cut a bounded view of the meaning tree by keyword query. The cut " +
      "carries node ids — use them for impact/edit. This is how you READ " +
      "structure — never file reads.",
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
      "Impact frontier of a node (reverse-reference closure, " +
      "hard-capped) — the decomposition input for any change. Carries the " +
      "exact args: {focusId, depth?, maxNodes?} — focusId comes from the " +
      "zoom cut, never a guessed name.",
    parameters: {
      type: "object",
      properties: {
        focusId: { type: "string" },
        depth: { type: "number" },
        maxNodes: { type: "number" },
      },
      required: ["focusId"],
    },
    execute: async (_id: string, params: any) =>
      delegated(`harness_impact ${JSON.stringify(params)}`),
  });

  pi.registerTool({
    name: "harness_edit",
    label: "Harness Edit",
    description:
      "Edit code through meaning moves — atomic, analyzer-verified, " +
      "auto-reverted on failure. Carries the EXACT edit_symbol args: " +
      "{action: replace_member_body|insert_member|apply_executable, " +
      "symbolId?, classSymbolId?, executableId?, name?, returns?, params?, " +
      "opChain?, executableParams?}. opChain rows: {label, a?, b?} over " +
      "the closed pure vocabulary (load_arg, literal, add, sub, mul, lt, " +
      "gt, eq, not, starts_with, list_len, get_item, call, " +
      "jump_if_false, return). replace_member_body requires suite " +
      "coverage for the member. There is NO write tool — edits move " +
      "through meaning; ids come from the zoom/impact cuts, never a " +
      "guessed name.",
    parameters: {
      type: "object",
      properties: {
        action: {
          type: "string",
          enum: ["replace_member_body", "insert_member", "apply_executable"],
        },
        symbolId: { type: "string" },
        classSymbolId: { type: "string" },
        executableId: { type: "string" },
        name: { type: "string" },
        returns: { type: "string" },
        params: { type: "array", items: { type: "string" } },
        opChain: {
          type: "array",
          items: {
            type: "object",
            properties: {
              label: { type: "string" },
              a: { type: "string" },
              b: { type: "string" },
            },
            required: ["label"],
          },
        },
        executableParams: {
          type: "object",
          properties: {
            newName: { type: "string" },
            scope: { type: "string" },
          },
        },
      },
      required: ["action"],
    },
    execute: async (_id: string, params: any) =>
      delegated(`harness_edit ${JSON.stringify(params)}`),
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
