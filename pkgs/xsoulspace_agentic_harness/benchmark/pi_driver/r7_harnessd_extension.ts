// r7_harnessd_extension.ts — pi extension (TASK 3 + PLAN §NOW #6): the
// INTERACTIVE remote mover. pi's own configured model is the daemon
// session actor's brain; pi NEVER touches files.
//
// Two server-initiated round-trips are answered here, both LAWFUL:
//
// 1. `session/propose_move` (R7 production #4) — the daemon runs the
//    harness loop MODEL-LESS; every decision arrives as a proposal
//    (bounded cut + the closed tool schemas + budgets). This extension
//    answers with pi's configured model: the tool schemas are passed to
//    the model VERBATIM (parameters.root unwrapped defensively — the
//    daemon unwraps server-side since production #2), the model's typed
//    tool calls come back, arguments are jsonDecode'd at the boundary.
//    Proposals land MID-TURN (while a delegated tool's execute is
//    awaiting the daemon turn), so answers are SERIALIZED through a
//    promise chain — one decision at a time, decisionId echoed back.
//
// 2. `session/request_permission` (R7c item 3) — the consent UI: the
//    title + unified diff (details) are surfaced via ctx.ui.confirm; the
//    human allows/rejects; NO UI / no ctx / timeout ⇒ REJECT
//    (deny-by-default is structural). A rejected mutation NEVER lands.
//
// The daemon is spawned with `--remote-mover` by default (pi's model is
// the brain — never a second model inside the loop); HARNESSD_SCRIPTED=1
// keeps the LLM-free gate mover. PI_HARNESSD=1 disables pi's built-in
// file tools: the daemon surface is the ONLY file surface.
//
// Use:
//   PI_HARNESSD=1 HARNESSD_PKG=../../xsoulspace_inference_apple_foundation \
//     pi -e benchmark/pi_driver/r7_harnessd_extension.ts

import { spawn, type ChildProcess } from "node:child_process";
import net from "node:net";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import process from "node:process";

// --- minimal ACP client (newline-delimited JSON-RPC; stdio OR socket) ----

interface PiCtx {
  modelRegistry?: {
    complete: (model: any, context: any, options?: any) => Promise<any>;
  };
  model?: any;
  signal?: AbortSignal;
  ui?: {
    confirm: (title: string, message?: string) => Promise<boolean>;
    notify?: (msg: string, level?: string) => void;
  };
  hasUI?: boolean;
}

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

  // The interactive handlers, wired by the extension below.
  onProposeMove: ((proposal: any) => Promise<any>) | null = null;
  onPermissionRequest: ((params: any) => Promise<any>) | null = null;

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
      // Server-initiated REQUESTS (answered by the extension's handlers —
      // never auto-allowed, never answered empty):
      if (message.method === "session/request_permission" && message.id != null) {
        const handler = this.onPermissionRequest;
        const params = message.params ?? {};
        (handler
          ? handler(params).catch(() => REJECT)
          : Promise.resolve(REJECT)
        ).then((response) =>
          this.wire.write(
            `${JSON.stringify({ jsonrpc: "2.0", id: message.id, result: response })}\n`,
          ),
        );
        continue;
      }
      if (message.method === "session/propose_move" && message.id != null) {
        const handler = this.onProposeMove;
        const proposal = message.params ?? {};
        (handler
          ? handler(proposal).catch(() => EMPTY_MOVE)
          : Promise.resolve(EMPTY_MOVE)
        ).then((response) =>
          this.wire.write(
            `${JSON.stringify({
              jsonrpc: "2.0",
              id: message.id,
              result: { decisionId: proposal.decisionId, ...response },
            })}\n`,
          ),
        );
        continue;
      }
    }
  }

  call(method: string, params: any, timeoutMs = 1800000): Promise<any> {
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
    // KEEP-WARM: the daemon is never killed on session end; it self-idle-exits.
  }
}

const EMPTY_MOVE = { toolCalls: [], text: "" };
const REJECT = { outcome: { outcome: "reject", optionId: "reject" } };

// --- the extension -------------------------------------------------------

let client: HarnessdClient | null = null;

// The latest extension context (set by every tool execute and turn event) —
// the model + UI entry points the handlers need.
let capturedCtx: PiCtx | null = null;

// Serialization: proposals and consent dialogs land MID-TURN. One answer at
// a time, in arrival order (the daemon is one-actor-at-a-time in v1; the
// chains make that ordering structural, not hopeful).
let moveChain: Promise<unknown> = Promise.resolve();
let consentChain: Promise<unknown> = Promise.resolve();

const DAEMON_TOOL_NAMES = [
  "harness_scan",
  "harness_zoom",
  "harness_impact",
  "harness_edit",
  "harness_fs_write",
  "harness_verify",
];

/// Answers ONE proposal with pi's configured model. The cut is the user
/// message; the tool schemas travel VERBATIM (defensive parameters.root
/// unwrap); tool-call arguments are jsonDecode'd at the boundary (some
/// providers deliver them as strings). An empty tool-call set closes the
/// decision model-lessly — the loop's goal gate grades the end state.
async function answerProposal(proposal: any): Promise<any> {
  const ctx = capturedCtx;
  const model = ctx?.model;
  if (!ctx?.modelRegistry || !model) {
    // No model reachable: the decision closes EMPTY (never a guess).
    return { ...EMPTY_MOVE, text: "no model reachable — decision closed empty" };
  }
  const tools = (proposal.toolSchemas ?? []).map((t: any) => ({
    name: t.name,
    description: t.description ?? "",
    parameters: t.parameters?.root ?? t.parameters ?? { type: "object", properties: {} },
  }));
  const messages = [
    {
      role: "user" as const,
      content:
        `You are the harness session actor's brain. The cut below is your ` +
        `entire bounded view — there are no files for you, only this ` +
        `projection. Think BRIEFLY, then submit the next move by calling ` +
        `ONE of the harness tools. If the task in the cut is not yet ` +
        `fully complete you MUST call a tool — reply with NO tool call ` +
        `only when the goal is verifiably done.\n\n` +
        `CUT:\n${String(proposal.prompt ?? "")}`,
      timestamp: Date.now(),
    },
  ];
  // Bounded retry: an upstream provider error (stop=error) kills a
  // decision it lands in, so the answerer retries — never an unbounded
  // loop; after the budget the decision closes EMPTY (the gate grades).
  // ADR 0027 §4: budget + backoff base are configuration (env), not
  // magic numbers: PI_HARNESSD_RETRIES (default 5),
  // PI_HARNESSD_BACKOFF_MS (default 1500, linear ×attempt).
  const maxRetries = parseInt(process.env.PI_HARNESSD_RETRIES ?? "5", 10);
  const backoffMs = parseInt(process.env.PI_HARNESSD_BACKOFF_MS ?? "1500", 10);
  let response: any = null;
  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    response = await ctx.modelRegistry.complete(
      model,
      { messages, tools },
      { maxTokens: 8192, signal: ctx.signal },
    );
    if (response?.stopReason !== "error") break;
    process.stderr.write(
      `[harnessd-ext] model error (attempt ${attempt}): ` +
        `${response?.errorMessage ?? "?"}\n`,
    );
    await new Promise((r) => setTimeout(r, backoffMs * attempt));
  }
  const content: any[] = response?.content ?? [];
  process.stderr.write(
    `[harnessd-ext] model response: stop=${response?.stopReason} ` +
      `content=[${content.map((c: any) => c.type).join(",")}] ` +
      `err=${response?.errorMessage ?? "-"} ` +
      `text=${content
        .filter((c: any) => c.type === "text")
        .map((c: any) => c.text ?? "")
        .join(" ")
        .slice(0, 200)}\n`,
  );
  const toolCalls = content
    .filter((c) => c.type === "toolCall")
    .map((c: any) => {
      let args: any = c.arguments;
      if (typeof args === "string") {
        try {
          args = JSON.parse(args);
        } catch {
          args = {};
        }
      }
      return { name: c.name, arguments: args ?? {} };
    });
  const text = content
    .filter((c) => c.type === "text")
    .map((c: any) => c.text ?? "")
    .join(" ");
  // ADR 0027 §3: the model's reasoning travels with the move so the daemon
  // can record a reasoning beat (measured, never re-projected, reused on
  // escalation). Extracted from the thinking block when present.
  const thinking = content
    .filter((c) => c.type === "thinking")
    .map((c: any) => c.text ?? c.thinking ?? "")
    .join("\n");
  process.stderr.write(
    `[harnessd-ext] move ${proposal.decisionId}: ` +
      `${toolCalls.map((t: any) => t.name).join(",") || "(none)"} ` +
      `(reasoning=${proposal.reasoning ?? "high"}, ` +
      `thinking=${thinking.length} chars)\n`,
  );
  return { toolCalls, text, thinking };
}

/// Surfaces ONE consent request through pi's UI (title + the unified diff
/// carried in `_meta.details`). Deny-by-default: no UI, no ctx, or a
/// timeout all REJECT — and a rejected mutation never lands.
async function answerPermission(params: any): Promise<any> {
  const ctx = capturedCtx;
  const meta = params?._meta ?? {};
  const title = String(meta.title ?? "Allow this mutation?");
  const details = meta.details ? String(meta.details) : "";
  const confirm = ctx?.ui?.confirm;
  if (!confirm) {
    process.stderr.write(
      `[harnessd-ext] consent DENIED (no UI): ${title}\n`,
    );
    return REJECT;
  }
  let confirmed = false;
  try {
    confirmed = await Promise.race([
      confirm(title, details || "Allow this mutation?"),
      new Promise<boolean>((resolve) =>
        setTimeout(() => resolve(false), 300000),
      ),
    ]);
  } catch {
    confirmed = false;
  }
  process.stderr.write(
    `[harnessd-ext] consent ${confirmed ? "ALLOWED" : "DENIED"}: ${title}\n`,
  );
  return confirmed
    ? { outcome: { outcome: "allow", optionId: "allow" } }
    : REJECT;
}

interface PiAPI {
  registerTool(def: any): void;
  setActiveTools?(names: string[]): void;
  on?(event: string, handler: (event: any, ctx: any) => void | Promise<void>): void;
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
  // HARNESSD_SCRIPTED=1 keeps the LLM-free gate mover; DEFAULT is the
  // interactive remote mover (pi's model is the brain — production #4).
  const scripted = process.env.HARNESSD_SCRIPTED === "1";

  // Capture the extension context at every opportunity so the handlers can
  // reach pi's model and UI mid-turn.
  pi.on?.("session_start", (_event, ctx) => {
    capturedCtx = ctx;
  });
  pi.on?.("turn_start", (_event, ctx) => {
    capturedCtx = ctx;
  });

  const ensureClient = async (): Promise<HarnessdClient> => {
    if (client) return client;
    // connect-if-live: a daemon holding this workspace answers the
    // initialize health ping over the socket pointer.
    const pointer = readSocketPointer(workspace);
    if (pointer) {
      try {
        const attached = HarnessdClient.attachSocket(pointer);
        attached.onProposeMove = (proposal) =>
          (moveChain = moveChain.then(() => answerProposal(proposal)));
        attached.onPermissionRequest = (params) =>
          (consentChain = consentChain.then(() => answerPermission(params)));
        await attached.start(workspace);
        client = attached;
        return client;
      } catch {
        // stale pointer (crashed daemon) — fall through to spawn.
      }
    }
    // spawn-if-absent: --remote-mover by default (pi decides), --workspace
    // arms the single-instance lock + socket listener.
    // ADR 0027 §4 — AOT-first: spawn the prebuilt harnessd binary when
    // present (kills the ~10–15s JIT + native-hooks cold start); `dart run`
    // is the fallback. Override the path with HARNESSD_AOT.
    const aotBin =
      process.env.HARNESSD_AOT ?? "/tmp/harnessd_aot/bundle/bin/harnessd";
    const useAot = existsSync(aotBin);
    const daemonArgs = [
      "--profile",
      "meaning",
      ...(scripted ? ["--scripted"] : ["--remote-mover"]),
      "--workspace",
      workspace,
    ];
    const spawned = useAot
      ? HarnessdClient.spawnDaemon(aotBin, daemonArgs, daemonPkg)
      : HarnessdClient.spawnDaemon(
          "dart",
          ["run", "bin/harnessd.dart", ...daemonArgs],
          daemonPkg,
        );
    process.stderr.write(
      `[harnessd-ext] spawning daemon (${useAot ? "AOT" : "dart run"})\n`,
    );
    const socketPath = await waitForPointer(workspace, 300000);
    spawned.wire.end?.(); // the spawned proc's stdio pipe is not used
    client = spawned; // retained so the process is not GC'd/reaped
    const attached = HarnessdClient.attachSocket(socketPath);
    attached.onProposeMove = (proposal) =>
      (moveChain = moveChain.then(() => answerProposal(proposal)));
    attached.onPermissionRequest = (params) =>
      (consentChain = consentChain.then(() => answerPermission(params)));
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
    process.stderr.write(
      `[harnessd-ext] daemon result: ${text.replace(/\s+/g, " ").slice(0, 500)}\n`,
    );
    return {
      content: [{ type: "text", text: text || "(daemon returned no text)" }],
      details: { daemonUpdateCount: updates.length, directive },
    };
  };

  // Each delegated tool serializes its params as a structured payload — in
  // remote-mover mode the payload IS the task sentence pi's model reads in
  // the first cut; in scripted mode the mover executes it verbatim.
  pi.registerTool({
    name: "harness_scan",
    label: "Harness Scan",
    description:
      "Scan this workspace into the harnessd meaning tree (the code graph " +
      "you work through). Call once before zoom/impact/edit. No file " +
      "reads — the tree is the code interface.",
    parameters: { type: "object", properties: {}, required: [] },
    execute: async (_id: string, _params: any, _signal: any, _onUpdate: any, ctx: PiCtx) => {
      capturedCtx = ctx;
      return delegated("Scan the workspace into the meaning tree (repo_etl scan).");
    },
  });

  pi.registerTool({
    name: "harness_zoom",
    label: "Harness Zoom",
    description:
      "Cut a bounded view of the meaning tree by keyword query or focus " +
      "id (zoom: point/local/region/summary; a mapped file's " +
      "section/keypath anchor also yields its text span on point zoom). " +
      "This is how you READ structure — never file reads.",
    parameters: {
      type: "object",
      properties: {
        query: { type: "string" },
        focusId: { type: "string" },
        zoom: { type: "string" },
        budget: { type: "number" },
      },
      required: [],
    },
    execute: async (_id: string, params: any, _signal: any, _onUpdate: any, ctx: PiCtx) => {
      capturedCtx = ctx;
      return delegated(
        `Read the meaning tree: harness_zoom ${JSON.stringify(params ?? {})}`,
      );
    },
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
    execute: async (_id: string, params: any, _signal: any, _onUpdate: any, ctx: PiCtx) => {
      capturedCtx = ctx;
      return delegated(`harness_impact ${JSON.stringify(params)}`);
    },
  });

  pi.registerTool({
    name: "harness_edit",
    label: "Harness Edit",
    description:
      "Edit code through meaning moves — atomic, analyzer-verified, " +
      "auto-reverted on failure. Carries the EXACT edit_symbol args: " +
      "{action: replace_member_body|insert_member|apply_executable, " +
      "symbolId (REQUIRED — for insert_member it is the host class), " +
      "executableId?, name?, returns?, params?, opChain?, " +
      "executableParams?}. There is NO write tool for code — edits move " +
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
      required: ["action", "symbolId"],
    },
    execute: async (_id: string, params: any, _signal: any, _onUpdate: any, ctx: PiCtx) => {
      capturedCtx = ctx;
      return delegated(`harness_edit ${JSON.stringify(params)}`);
    },
  });

  pi.registerTool({
    name: "harness_fs_write",
    label: "Harness FS Write (review)",
    description:
      "Whole-file write through the daemon's review gate (fs-tier ESCAPE " +
      "HATCH for files without a materializer). The human consents via " +
      "the unified diff (session/request_permission); a reject NEVER " +
      "lands. NEVER for Dart — code moves through harness_edit. Args: " +
      "{path (workspace-relative), content (full new file text)}.",
    parameters: {
      type: "object",
      properties: {
        path: { type: "string" },
        content: { type: "string" },
      },
      required: ["path", "content"],
    },
    execute: async (_id: string, params: any, _signal: any, _onUpdate: any, ctx: PiCtx) => {
      capturedCtx = ctx;
      return delegated(`harness_fs_write ${JSON.stringify(params ?? {})}`);
    },
  });

  pi.registerTool({
    name: "harness_verify",
    label: "Harness Verify",
    description:
      "Verify the workspace green through the daemon (dart analyze + the " +
      "workspace convention). Failed moves were already auto-reverted.",
    parameters: { type: "object", properties: {}, required: [] },
    execute: async (_id: string, _params: any, _signal: any, _onUpdate: any, ctx: PiCtx) => {
      capturedCtx = ctx;
      return delegated(
        "Verify the workspace is green (run the workspace convention checks).",
      );
    },
  });

  if (enabled) {
    // PI_HARNESSD=1: the daemon is the ONLY file surface — pi's built-in
    // fs tools are disabled for the whole session. setActiveTools is a
    // RUNTIME action (not allowed during extension loading), so it rides
    // session_start.
    pi.on?.("session_start", () => {
      pi.setActiveTools?.(DAEMON_TOOL_NAMES);
    });
  }
}
