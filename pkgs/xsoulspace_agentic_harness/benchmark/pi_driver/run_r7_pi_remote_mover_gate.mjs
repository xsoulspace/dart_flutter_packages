#!/usr/bin/env node
// run_r7_pi_remote_mover_gate.mjs — R7 PRODUCTION #7 GATE: the real-model
// pi row through the MODEL-LESS daemon (SCOPE FIXED in PLAN.md: pi's own
// model is the session actor's brain — the daemon runs `--remote-mover`,
// NO open_router/AFM mover; wiring a mover model while pi calls it would
// put a second, worse model inside the loop).
//
// Flow:
//   1. daemon: `--profile meaning --remote-mover --workspace <fixture>` —
//      every harness decision round-trips to THIS client as
//      `session/propose_move` (bounded cut + tool schemas out);
//   2. the client answers each proposal by prompting a REAL pi session
//      (its own model via the configured provider) whose ONLY tools are
//      the harness surface — the tool "execution" is a PASSTHROUGH that
//      resolves the pending proposal with the typed tool call; the daemon
//      executes it for real (host validates, materializes, verifies);
//   3. the fixture task is the R7e pack path: fix the off-by-one bound of
//      `inBounds` through the pack executable `dart/fix_loop_bound`.
//
// The row is PUBLISHED EVEN ON FAIL — the failure class (schema size?
// slot ambiguity? cut composition?) is the data. Requires
// OPENROUTER_API_KEY (pi's provider); PI_ROW_MODEL overrides the model
// (default: z-ai/glm-5.3-flash, the successor of pi's default stealth/ox-alpha).
//
// Output: benchmark/runs/r7_pi_remote_mover_transcript.txt

import { spawn } from "node:child_process";
import net from "node:net";
import { mkdirSync, mkdtempSync, writeFileSync, readFileSync, existsSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import process from "node:process";
import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import {
  createAgentSession,
  ModelRuntime,
  SessionManager,
} from "@earendil-works/pi-coding-agent";

const DRIVER_DIR = path.dirname(new URL(import.meta.url).pathname);
const DAEMON_PKG = path.resolve(
  DRIVER_DIR,
  "../../../xsoulspace_inference_apple_foundation",
);
const TRANSCRIPT = path.resolve(
  DRIVER_DIR,
  "../../benchmark/runs/r7_pi_remote_mover_transcript.txt",
);

const transcript = [];
function log(line) {
  const stamped = `[${new Date().toISOString()}] ${line}`;
  transcript.push(stamped);
  process.stdout.write(`${stamped}\n`);
}

// --- the daemon client (unix socket, newline JSON-RPC) -------------------

class DaemonClient {
  constructor(socketPath) {
    this.buffer = "";
    this.pending = new Map();
    this.nextId = 1;
    this.updates = [];
    this.onProposeMove = null; // async (proposal) => response object
    this.socket = net.createConnection(socketPath);
    this.socket.setEncoding("utf8");
    this.socket.on("data", (chunk) => this.#onData(chunk));
  }

  #onData(chunk) {
    this.buffer += chunk;
    let idx;
    while ((idx = this.buffer.indexOf("\n")) >= 0) {
      const line = this.buffer.slice(0, idx).trim();
      this.buffer = this.buffer.slice(idx + 1);
      if (!line) continue;
      let msg;
      try {
        msg = JSON.parse(line);
      } catch {
        continue;
      }
      if (msg.method === "session/propose_move" && msg.id != null) {
        // THE REMOTE MOVER ROUND-TRIP: the daemon's decision asks pi.
        const proposal = msg.params ?? {};
        void (this.onProposeMove
          ? this.onProposeMove(proposal)
          : Promise.resolve({ toolCalls: [], text: "" })
        ).then(
          (response) => {
            this.socket.write(
              `${JSON.stringify({
                jsonrpc: "2.0",
                id: msg.id,
                result: { ...response, decisionId: proposal.decisionId },
              })}\n`,
            );
          },
          (error) => {
            this.socket.write(
              `${JSON.stringify({
                jsonrpc: "2.0",
                id: msg.id,
                result: { toolCalls: [], text: `error: ${error}` },
              })}\n`,
            );
          },
        );
        continue;
      }
      if (msg.method === "session/request_permission" && msg.id != null) {
        this.socket.write(
          `${JSON.stringify({
            jsonrpc: "2.0",
            id: msg.id,
            result: { outcome: { outcome: "allow", optionId: "allow" } },
          })}\n`,
        );
        continue;
      }
      if (msg.id != null && (msg.result !== undefined || msg.error !== undefined)) {
        const pending = this.pending.get(msg.id);
        if (pending) {
          this.pending.delete(msg.id);
          if (msg.error) pending.reject(new Error(JSON.stringify(msg.error)));
          else pending.resolve(msg.result);
        }
        continue;
      }
      if (msg.method === "session/update") {
        const update = msg.params?.update ?? msg.params ?? {};
        this.updates.push(update);
        if (update.sessionUpdate === "agent_message_chunk") {
          log(`[daemon] ${update.content?.text?.trim().slice(0, 160) ?? ""}`);
        }
      }
    }
  }

  call(method, params, timeoutMs = 900000) {
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      setTimeout(() => {
        if (this.pending.has(id)) {
          this.pending.delete(id);
          reject(new Error(`${method} timed out`));
        }
      }, timeoutMs);
      this.socket.write(
        `${JSON.stringify({ jsonrpc: "2.0", id, method, params })}\n`,
      );
    });
  }

  close() {
    this.socket.end();
  }
}

// --- the pi-side answering (REAL model, passthrough tools) ---------------

let currentResolve = null; // set while pi's prompt serves one decision
let roundTrips = 0;

// The pi-side tools are built VERBATIM from the proposal's toolSchemas
// (the remote-mover contract: the daemon sends the closed surface it is
// willing to execute; the client renders exactly that to its model). The
// tool "execution" is a passthrough that submits the typed call back —
// the daemon validates, materializes and verifies every move.


function piToolsFromSchemas(toolSchemas) {
  return toolSchemas.map((t) => ({
    name: t.name,
    label: t.name,
    description:
      `${t.description}\n\nCalling this SUBMITS the move to the harness ` +
      "daemon, which executes and verifies it. Submit exactly one move " +
      "per decision, then stop and wait for the next cut.",
    // The Dart schema bundle wraps the properties in a `root` key —
    // unwrap so the model fills the tool's own args (measured: with the
    // wrapper, every call arrived as {root: {...}} and the registry read
    // the defaults instead of the model's intent).
    parameters: t.parameters?.root ?? t.parameters ?? { type: "object", properties: {} },
    execute: async (_id, params) => {
      if (!currentResolve) {
        return {
          content: [{ type: "text", text: "no pending decision — stop and wait." }],
        };
      }
      const resolve = currentResolve;
      currentResolve = null;
      const args =
        params && typeof params.args === "string"
          ? JSON.parse(params.args)
          : (params ?? {});
      resolve({ toolCalls: [{ name: t.name, arguments: args }] });
      roundTrips++;
      log(`[pi -> daemon] submitted ${t.name}(${JSON.stringify(args).slice(0, 160)})`);
      return {
        content: [
          {
            type: "text",
            text:
              "Move submitted. The harness executes it; the next decision " +
              "cut will arrive as a new message. Do not call more tools now.",
          },
        ],
      };
    },
  }));
}

// --- the gate ------------------------------------------------------------

let daemon = null;
let fixture = null;

function waitFor(predicate, timeoutMs, what) {
  return new Promise((resolve, reject) => {
    const started = Date.now();
    const t = setInterval(() => {
      try {
        const v = predicate();
        if (v) {
          clearInterval(t);
          resolve(v);
        }
      } catch {
        // keep waiting
      }
      if (Date.now() - started > timeoutMs) {
        clearInterval(t);
        reject(new Error(`${what} timed out after ${timeoutMs}ms`));
      }
    }, 100);
  });
}

async function main() {
  const apiKey = process.env.OPENROUTER_API_KEY;
  if (!apiKey) {
    throw new Error("OPENROUTER_API_KEY not set — the pi row needs a real model");
  }
  const modelId = process.env.PI_ROW_MODEL ?? "z-ai/glm-5.3-flash";

  // The R7e fixture: the off-by-one `inBounds` + the pack executable.
  fixture = mkdtempSync(path.join(tmpdir(), "r7_pi_remote_"));
  const put = (rel, content) => {
    const f = path.join(fixture, rel);
    mkdirSync(path.dirname(f), { recursive: true });
    writeFileSync(f, content, "utf8");
  };
  put("pubspec.yaml", "name: r7_pi_remote\nenvironment:\n  sdk: ^3.0.0\ndev_dependencies:\n  test: any\n");
  put("lib/loop.dart", "bool inBounds(int i, int n) {\n  return i < n;\n}\n");
  put(
    "test/loop_test.dart",
    "import 'package:test/test.dart';\nimport 'package:r7_pi_remote/loop.dart';\nvoid main() {\n  test('inBounds is inclusive', () { expect(inBounds(3, 3), isTrue); });\n  test('inBounds rejects beyond', () { expect(inBounds(5, 4), isFalse); });\n}\n",
  );
  put(
    ".dart_tool/harnessd/edit_pack.json",
    JSON.stringify(
      {
        packId: "edit_capture",
        executables: [
          {
            id: "dart/fix_loop_bound",
            kind: "replace_member_body",
            params: ["symbolId"],
            verification: ["analyze", "test"],
            scope: "lexical",
            description:
              "Fix an off-by-one inclusive bound: the member body becomes the inclusive form over its declared params (i, n).",
            opChain: [
              { label: "load_arg", a: "i" },
              { label: "load_arg", a: "n" },
              { label: "gt" },
              { label: "not" },
              { label: "return" },
            ],
          },
        ],
      },
      null,
      2,
    ),
  );
  execFileSync("dart", ["pub", "get"], { cwd: fixture, stdio: "pipe" });
  log(`fixture workspace: ${fixture}`);

  // 1. The MODEL-LESS daemon.
  daemon = spawn(
    "dart",
    [
      "run",
      "bin/harnessd.dart",
      "--profile",
      "meaning",
      "--remote-mover",
      "--workspace",
      fixture,
    ],
    { cwd: DAEMON_PKG, stdio: ["pipe", "pipe", "pipe"] },
  );
  daemon.stderr.setEncoding("utf8");
  daemon.stderr.on("data", (chunk) => log(`[harnessd] ${chunk.trim()}`));
  const pointerFile = path.join(fixture, ".dart_tool/harnessd/harnessd.sock");
  const socketPath = await waitFor(
    () => (existsSync(pointerFile) ? readFileSync(pointerFile, "utf8").trim() : null),
    180000,
    "daemon socket pointer",
  );
  log(`daemon up: ${socketPath}`);

  // 2. The REAL pi session — its model decides through the passthrough tools.
  const runtime = await ModelRuntime.create({ refreshOnCreate: false });
  runtime.registerProvider("openrouter-pi-row", {
    name: "OpenRouter (pi row)",
    baseUrl: "https://openrouter.ai/api/v1",
    apiKey,
    api: "openai-completions",
    models: [
      {
        id: modelId,
        name: modelId,
        reasoning: false,
        input: ["text"],
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
        contextWindow: 128000,
        maxTokens: 4096,
      },
    ],
  });
  await runtime.setRuntimeApiKey("openrouter-pi-row", apiKey);
  const model = runtime.getModel("openrouter-pi-row", modelId);
  if (!model) throw new Error("pi row model not registered");

  // The pi session is created LAZILY from the FIRST proposal's
  // toolSchemas — the client renders the daemon's own surface, not a copy.
  let session = null;
  async function ensurePiSession(toolSchemas) {
    if (session) return session;
    const { createAgentSession } = await import(
      "@earendil-works/pi-coding-agent"
    );
    const created = await createAgentSession({
      cwd: fixture,
      model,
      modelRuntime: runtime,
      noTools: "builtin",
      excludeTools: [
        "read",
        "write",
        "edit",
        "bash",
        "root_search",
        "root_find",
        "root_edit",
      ],
      customTools: piToolsFromSchemas(toolSchemas),
      sessionManager: SessionManager.inMemory(fixture),
    });
    session = created.session;
    session.subscribe((event) => {
      if (event.type === "message_update") return;
      log(`[pi.event] ${event.type}`);
    });
    log(
      `pi session up (model ${modelId}) — tools built verbatim from the ` +
        `daemon's propose_move schemas: ` +
        `${toolSchemas.map((t) => t.name).join(", ")}`,
    );
    return session;
  }

  // 3. Each daemon decision → prompt pi with the bounded cut.
  const daemonClient = new DaemonClient(socketPath);
  // Each daemon decision → prompt pi with the bounded cut. Proposals can
  // arrive while pi is still closing its previous turn (the daemon's ReAct
  // continuation opens the next decision right after a submission), so the
  // answers are SERIALIZED through a queue — one prompt at a time; the
  // proposal resolves when pi's model calls a passthrough tool (the daemon
  // then executes it for real) or when the prompt ends without one.
  const proposalQueue = [];
  let piDraining = false;
  async function drainPi() {
    if (piDraining) return;
    piDraining = true;
    while (proposalQueue.length > 0) {
      const { proposal, resolve } = proposalQueue.shift();
      currentResolve = resolve;
      await ensurePiSession(proposal.toolSchemas ?? []);
      const cut = proposal.prompt ?? "";
      const instruction =
        "You are the harness actor's brain. The cut below is your entire " +
        "view of the workspace (there are no files — only this graph). " +
        "Submit exactly ONE move by calling one harness tool, then stop.\n\n" +
        `CUT:\n${cut}`;
      try {
        await session.prompt(instruction);
      } catch (e) {
        log(`[pi] prompt error: ${e}`);
      }
      if (currentResolve) {
        const resolveEmpty = currentResolve;
        currentResolve = null;
        resolveEmpty({ toolCalls: [], text: "no move proposed" });
      }
    }
    piDraining = false;
  }
  daemonClient.onProposeMove = (proposal) =>
    new Promise((resolve) => {
      proposalQueue.push({ proposal, resolve });
      log(
        `[daemon -> pi] propose_move ${proposal.decisionId}: cut ` +
          `${(proposal.prompt ?? "").length} chars, ` +
          `${(proposal.toolSchemas ?? []).length} tools, budgets ` +
          `${JSON.stringify(proposal.budgets ?? {})}`,
      );
      void drainPi();
    });

  await daemonClient.call("initialize", { protocolVersion: 1, clientCapabilities: {} });
  const created = await daemonClient.call("session/new", { cwd: fixture });
  daemonClient.sessionId = created.sessionId;
  log(`session=${created.sessionId} — task: fix inBounds via the pack executable`);

  const turn = await daemonClient.call("session/prompt", {
    sessionId: created.sessionId,
    prompt: [
      {
        type: "text",
        text:
          "lib/loop.dart has an off-by-one bug: inBounds must be INCLUSIVE " +
          "(inBounds(3, 3) is true). The pack executable dart/fix_loop_bound " +
          "repairs it. Scan, zoom to find inBounds's symbol id, apply the " +
          "executable to it, verify.",
      },
    ],
  });
  log(`daemon turn: stop=${turn.stopReason}`);
  const text = daemonClient.updates
    .filter((u) => u.sessionUpdate === "agent_message_chunk")
    .map((u) => u.content?.text ?? "")
    .join("");
  const passed = turn.stopReason === "end_turn" && text.includes("verdict: PASS");
  log(
    `=== VERDICT: ${passed ? "PASS" : "FAIL"} (round-trips: ${roundTrips}) ===\n` +
      text.slice(-600),
  );

  mkdirSync(path.dirname(TRANSCRIPT), { recursive: true });
  writeFileSync(TRANSCRIPT, transcript.join("\n") + "\n");
  console.log(`\ntranscript written: ${TRANSCRIPT}`);
  if (!passed) process.exitCode = 1;
}

try {
  await main();
} catch (error) {
  transcript.push(`=== VERDICT: FAIL — ${error?.stack ?? error} ===`);
  try {
    mkdirSync(path.dirname(TRANSCRIPT), { recursive: true });
    writeFileSync(TRANSCRIPT, transcript.join("\n") + "\n");
  } catch {}
  console.error(error);
  process.exitCode = 1;
} finally {
  daemon?.kill();
  if (fixture) {
    try {
      rmSync(fixture, { recursive: true, force: true });
    } catch {}
  }
  process.exit(process.exitCode ?? 0);
}
