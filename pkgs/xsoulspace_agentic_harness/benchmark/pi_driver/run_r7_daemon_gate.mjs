#!/usr/bin/env node
// run_r7_daemon_gate.mjs — R7 PRODUCTION #1 GATE (ADR 0023): the FULL edit
// surface over ACP. One pi session drives the daemon through
//   replace_member_body AND insert_member (the two model-composed moves)
//   plus apply_executable (rename_symbol) — via the STRUCTURED
//   `harness_edit` contract (exact `edit_symbol` args as a JSON payload,
//   no prose directives) — with analyze + the workspace convention green.
//
// The gate workspace is a disposable fixture package (tmp): a covered
// member (`area`, expectation derived from the suite — fence b) inside a
// class plus a free class to receive an insert. The repo itself is never
// mutated (no rename-and-revert dance: the fixture IS the workspace).
//
// LLM-free end to end (repo gate discipline): the "model" is a scripted
// OpenAI-compatible server that reads ids out of the streamed zoom/impact
// results and emits the next structured daemon-tool call; the daemon mover
// is `--scripted` (directive + payload interpreter over the REAL registry).
// The transcript proves the SURFACE contract:
//   - pi's enabled tools contain no read/write/edit/bash;
//   - `harness_edit` carries the EXACT edit_symbol args (the mover never
//     resolves or guesses ids — the caller supplies them from cut data);
//   - every tool result streams MID-TURN (no silent 30–60s tool calls);
//   - every workspace mutation happened inside the daemon (tool beats,
//     analyzer verdict, unique tool-call ids streamed as session/update).
//
// Output: benchmark/runs/r7_edit_surface_transcript.txt

import { createServer } from "node:http";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
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
import { HarnessdClient } from "./r7_harnessd_client.mjs";

const DRIVER_DIR = path.dirname(new URL(import.meta.url).pathname);
const HARNESS_PKG = path.resolve(DRIVER_DIR, "../..");
const DAEMON_PKG = path.resolve(
  DRIVER_DIR,
  "../../../xsoulspace_inference_apple_foundation",
);
const TRANSCRIPT = path.resolve(
  DRIVER_DIR,
  "../../benchmark/runs/r7_edit_surface_transcript.txt",
);

const transcript = [];
let fixtureDir = null;
function log(line) {
  const stamped = `[${new Date().toISOString()}] ${line}`;
  transcript.push(stamped);
  process.stdout.write(`${stamped}\n`);
}

// ---------------------------------------------------------------------------
// 1. The fixture workspace — a green Dart package whose suite covers
// `area` (fence b satisfied) and whose Box class accepts an inserted
// member. The convention (D8): pubspec + tests → `dart test`.
// ---------------------------------------------------------------------------

function createFixtureWorkspace() {
  const ws = mkdtempSync(path.join(tmpdir(), "r7_edit_surface_"));
  fixtureDir = ws;
  function put(rel, content) {
    const f = path.join(ws, rel);
    mkdirSync(path.dirname(f), { recursive: true });
    writeFileSync(f, content, "utf8");
    return f;
  }
  put(
    "pubspec.yaml",
    ["name: span_gate", "environment:", "  sdk: ^3.0.0", "dev_dependencies:", "  test: any", ""].join("\n"),
  );
  put(
    "lib/geometry.dart",
    [
      "int area(int w, int h) {",
      "  return w * h;",
      "}",
      "",
      "class Box {",
      "  int volume(int w, int h, int d) {",
      "    return w * h * d;",
      "  }",
      "}",
      "",
    ].join("\n"),
  );
  put(
    "test/geometry_test.dart",
    [
      "import 'package:test/test.dart';",
      "import 'package:span_gate/geometry.dart';",
      "",
      "void main() {",
      "  test('area', () {",
      "    expect(area(2, 3), 6);",
      "  });",
      "}",
      "",
    ].join("\n"),
  );
  execFileSync("dart", ["pub", "get"], { cwd: ws, stdio: "pipe" });
  return ws;
}

// ---------------------------------------------------------------------------
// 2. The scripted model server (OpenAI-compatible, streaming).
//
// Decides the next daemon-tool call from how many tool results pi has
// produced. ID-BEARING calls carry the STRUCTURED contract: harness_edit
// {action, symbolId/classSymbolId, opChain, executableId, executableParams}
// — the exact `edit_symbol` args — and harness_impact {focusId,...}. Ids
// are READ OUT OF THE STREAMED CUT (what a real model would do); the mover
// never resolves or guesses them.
// ---------------------------------------------------------------------------

const state = {
  boxId: null,
  areaId: null,
};

function extractIds(text) {
  const ids = [...text.matchAll(/sym_[A-Za-z0-9_.$]+/g)].map((m) => m[0]);
  for (const id of ids) {
    if (!state.boxId && id.endsWith("_Box")) state.boxId = id;
    if (!state.areaId && id.endsWith("_area")) state.areaId = id;
  }
}

function requireIds() {
  if (!state.areaId || !state.boxId) {
    throw new Error(
      `ids unresolved from streamed results: box=${state.boxId} area=${state.areaId}`,
    );
  }
}

const SEQUENCE = [
  {
    tool: "harness_scan",
    args: {},
    why: "scan the workspace into the meaning tree",
  },
  {
    tool: "harness_zoom",
    args: { query: "area Box" },
    why: "zoom the cut to locate the class and the covered member",
  },
  {
    tool: "harness_impact",
    structured: () => {
      requireIds();
      return { focusId: state.areaId, depth: 2, maxNodes: 32 };
    },
    why: "check the blast radius of `area` before editing it",
  },
  {
    // MODEL-COMPOSED MOVE 1: replace the covered member's body via an
    // op-chain (fence b: coverage from the suite; fence c: signature).
    tool: "harness_edit",
    structured: () => {
      requireIds();
      return {
        action: "replace_member_body",
        symbolId: state.areaId,
        opChain: [
          { label: "load_arg", a: "w" },
          { label: "load_arg", a: "h" },
          { label: "mul" },
          { label: "return" },
        ],
      };
    },
    why: "replace_member_body through the structured contract",
  },
  {
    // PACK-FED MOVE: apply_executable — rename across the refs frontier.
    tool: "harness_edit",
    structured: () => {
      requireIds();
      return {
        action: "apply_executable",
        executableId: "rename_symbol",
        symbolId: state.areaId,
        executableParams: { newName: "surfaceArea" },
      };
    },
    why: "apply_executable (rename_symbol) through the structured contract",
  },
  {
    // MODEL-COMPOSED MOVE 2: insert a member with an op-chain.
    tool: "harness_edit",
    structured: () => {
      requireIds();
      return {
        action: "insert_member",
        classSymbolId: state.boxId,
        name: "doubled",
        returns: "int",
        params: ["f:int"],
        opChain: [
          { label: "load_arg", a: "f" },
          { label: "literal", b: "2" },
          { label: "mul" },
          { label: "return" },
        ],
      };
    },
    why: "insert_member through the structured contract",
  },
  {
    tool: "harness_verify",
    args: {},
    why: "verify the workspace green",
  },
];

function toolResultText(messages) {
  let text = "";
  for (const m of messages) {
    if (m.role !== "tool" && m.role !== "tool_result") continue;
    const c = m.content;
    text +=
      typeof c === "string"
        ? c
        : Array.isArray(c)
          ? c.map((b) => b?.text ?? "").join("")
          : "";
  }
  return text;
}

function decideNext(messages) {
  const toolResults = messages.filter(
    (m) => m.role === "tool" || m.role === "tool_result",
  );
  extractIds(toolResultText(toolResults));
  if (toolResults.length >= SEQUENCE.length) {
    return {
      finish: "stop",
      text:
        "Done: scanned, zoomed, impacted, then through the STRUCTURED " +
        "harness_edit contract — replace_member_body on the covered " +
        "`area`, rename_symbol to `surfaceArea`, insert_member `doubled` " +
        "on Box — and verified green. No file was read or written by pi " +
        "directly; pi never saw file text.",
      why: "all moves applied and verified — report",
    };
  }
  const step = SEQUENCE[toolResults.length];
  const args = step.structured ? step.structured() : (step.args ?? {});
  return {
    toolCall: {
      id: `call_${randomUUID().slice(0, 8)}`,
      name: step.tool,
      arguments: JSON.stringify(args),
    },
    why: step.why,
  };
}

function startScriptedModelServer(port) {
  const server = createServer((req, res) => {
    transcript.push(`[model.http] ${req.method} ${req.url}`);
    if (req.method !== "POST" || !req.url?.includes("/chat/completions")) {
      res.writeHead(404).end();
      return;
    }
    let body = "";
    req.on("data", (c) => (body += c));
    req.on("end", () => {
      const request = JSON.parse(body || "{}");
      const messages = Array.isArray(request.messages) ? request.messages : [];
      const decision = decideNext(messages);
      transcript.push(
        `[model] decision: ${decision.toolCall
          ? `${decision.toolCall.name}(${decision.toolCall.arguments})`
          : `final text (${decision.text.length} chars)`} — ${decision.why}`,
      );
      res.writeHead(200, {
        "content-type": "text/event-stream",
        "cache-control": "no-cache",
        connection: "keep-alive",
      });
      const id = `chatcmpl_${randomUUID().slice(0, 8)}`;
      const base = {
        id,
        object: "chat.completion.chunk",
        created: Math.floor(Date.now() / 1000),
        model: request.model ?? "scripted",
      };
      const send = (obj) => res.write(`data: ${JSON.stringify(obj)}\n\n`);
      if (decision.toolCall) {
        send({
          ...base,
          choices: [
            {
              index: 0,
              delta: {
                role: "assistant",
                tool_calls: [
                  {
                    index: 0,
                    id: decision.toolCall.id,
                    type: "function",
                    function: {
                      name: decision.toolCall.name,
                      arguments: decision.toolCall.arguments,
                    },
                  },
                ],
              },
              finish_reason: null,
            },
          ],
        });
        send({
          id,
          object: "chat.completion.chunk",
          created: Math.floor(Date.now() / 1000),
          model: request.model ?? "scripted",
          choices: [{ index: 0, delta: {}, finish_reason: "tool_calls" }],
        });
      } else {
        send({
          id,
          object: "chat.completion.chunk",
          created: Math.floor(Date.now() / 1000),
          model: request.model ?? "scripted",
          choices: [
            {
              index: 0,
              delta: { role: "assistant", content: decision.text },
              finish_reason: null,
            },
          ],
        });
        send({
          id,
          object: "chat.completion.chunk",
          created: Math.floor(Date.now() / 1000),
          model: request.model ?? "scripted",
          choices: [{ index: 0, delta: {}, finish_reason: "stop" }],
        });
      }
      res.write("data: [DONE]\n\n");
      res.end();
    });
  });
  return new Promise((resolve) =>
    server.listen(port, "127.0.0.1", () => resolve(server)),
  );
}

// -------------------------------------------------------------------------

let modelServer = null;
let daemon = null;

async function main() {
  const fixture = createFixtureWorkspace();
  transcript.push(`fixture workspace: ${fixture}`);

  const port = 18000 + Math.floor(Math.random() * 2000);
  modelServer = await startScriptedModelServer(port);
  transcript.push(`[model] scripted model server listening on 127.0.0.1:${port}`);

  // The daemon: the R7 meaning-profile surface, scripted mover (LLM-free).
  // The daemon's WORLD is the fixture workspace (per-workspace persistence).
  daemon = new HarnessdClient(
    "dart",
    [
      "run",
      "bin/harnessd.dart",
      "--backend",
      "open_router",
      "--profile",
      "meaning",
      "--scripted",
    ],
    DAEMON_PKG,
    fixture,
    (line) => transcript.push(line),
  );

  transcript.push("=== R7 edit-surface transcript gate (production #1) ===");
  transcript.push(
    `daemon: dart run bin/harnessd.dart --backend open_router --profile meaning --scripted (cwd ${DAEMON_PKG})`,
  );

  const { capabilities, sessionId } = await daemon.start();
  transcript.push(
    `daemon capabilities: ${JSON.stringify(capabilities)} session=${sessionId}`,
  );
  if (capabilities?.loadSession !== true) {
    throw new Error("daemon must advertise loadSession: true (R7c)");
  }

  // The scripted model: an LLM-free mover registered as a provider (the
  // gate measures the SURFACE, not the mover — same discipline as every
  // R7 gate).
  const runtime = await ModelRuntime.create({ refreshOnCreate: false });
  runtime.registerProvider("scripted", {
    name: "Scripted Daemon Actor",
    baseUrl: `http://127.0.0.1:${port}/v1`,
    apiKey: "unused-scripted",
    api: "openai-completions",
    models: [
      {
        id: "scripted-daemon-actor",
        name: "Scripted Daemon Actor",
        reasoning: false,
        input: ["text"],
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
        contextWindow: 128000,
        maxTokens: 4096,
      },
    ],
  });
  await runtime.setRuntimeApiKey("scripted", "unused-scripted");
  const model = runtime.getModel("scripted", "scripted-daemon-actor");
  if (!model) throw new Error("scripted model not registered");

  // The daemon-backed tools: the ONLY tools pi gets. The id-bearing verbs
  // (harness_edit, harness_impact) carry the EXACT registry args as a
  // structured JSON payload — serialized into the session/prompt the
  // daemon mover executes. No prose directives for edits.
  const daemonTools = [
    {
      name: "harness_scan",
      label: "Harness Scan",
      description:
        "Scan this workspace into the harnessd meaning tree (the code graph). Call once before zoom/impact/edit.",
      parameters: { type: "object", properties: {}, required: [] },
      execute: async () => delegated("[scan]"),
    },
    {
      name: "harness_zoom",
      label: "Harness Zoom",
      description:
        "Cut a bounded view of the meaning tree by keyword query. The cut carries node ids — use them for impact/edit.",
      parameters: {
        type: "object",
        properties: { query: { type: "string" } },
        required: ["query"],
      },
      execute: async (_id, params) => delegated(`[zoom ${params.query}]`),
    },
    {
      name: "harness_impact",
      label: "Harness Impact",
      description:
        "Impact frontier of a node (reverse-reference closure, hard-capped). Carries the exact args: {focusId, depth?, maxNodes?}.",
      parameters: {
        type: "object",
        properties: {
          focusId: { type: "string" },
          depth: { type: "number" },
          maxNodes: { type: "number" },
        },
        required: ["focusId"],
      },
      execute: async (_id, params) =>
        delegated(`harness_impact ${JSON.stringify(params)}`),
    },
    {
      name: "harness_edit",
      label: "Harness Edit",
      description:
        "Edit code through meaning moves (atomic, analyzer-verified, auto-reverted on failure). Carries the EXACT edit_symbol args: " +
        "{action: replace_member_body|insert_member|apply_executable, symbolId?, classSymbolId?, executableId?, name?, returns?, params?, opChain?, executableParams?}. " +
        "opChain rows: {label, a?, b?} over the closed pure vocabulary. There is NO write tool — edits move through meaning.",
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
            properties: { newName: { type: "string" }, scope: { type: "string" } },
          },
        },
        required: ["action"],
      },
      execute: async (_id, params) =>
        delegated(`harness_edit ${JSON.stringify(params)}`),
    },
    {
      name: "harness_verify",
      label: "Harness Verify",
      description: "Verify the workspace green through the daemon.",
      parameters: { type: "object", properties: {}, required: [] },
      execute: async () => delegated("[verify]"),
    },
  ];

  async function delegated(directive) {
    const turn = await daemon.prompt(directive);
    transcript.push(
      `[pi -> daemon] "${directive.slice(0, 220)}" -> stop=${turn.stopReason} ` +
        `toolCallIds=${JSON.stringify(turn.toolCallIds)} ` +
        `text=${JSON.stringify(turn.text.slice(0, 300))}`,
    );
    return {
      content: [{ type: "text", text: turn.text || "(no text)" }],
      details: { updates: turn.updates.length },
    };
  }

  const { session } = await createAgentSession({
    cwd: HARNESS_PKG,
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
    customTools: daemonTools,
    sessionManager: SessionManager.inMemory(HARNESS_PKG),
  });

  session.subscribe((event) => {
    if (event.type === "message_update" || event.type === "agent_start") return;
    transcript.push(
      `[pi.event] ${event.type}: ${JSON.stringify(event).slice(0, 300)}`,
    );
  });

  // THE CLAIM UNDER TEST: pi's enabled tool surface carries NO fs tools.
  const enabledTools = session.agent.state.tools.map((t) => t.name);
  transcript.push(`pi enabled tools: ${JSON.stringify(enabledTools)}`);
  const forbidden = ["read", "write", "edit", "bash"];
  for (const t of forbidden) {
    if (enabledTools.includes(t)) {
      throw new Error(`pi fs tool "${t}" is enabled — the gate cannot run`);
    }
  }

  transcript.push("--- pi turn ---");
  await session.prompt(
    "Edit the delegated workspace through the harness daemon only: scan " +
      "the meaning tree, zoom to the geometry module, check the impact of " +
      "`area`, then with harness_edit (1) replace the body of the covered " +
      "member `area` (w*h recomposed as an op-chain), (2) rename it to " +
      "`surfaceArea` via apply_executable, (3) insert `doubled` on Box " +
      "(f*2). Then verify green. You have NO file tools — every access " +
      "goes through the daemon.",
  );

  // Post-state verification (host-side, for the record — the daemon's own
  // verify already ran inside the loop).
  const geometryPath = path.join(fixture, "lib/geometry.dart");
  const geometrySrc = await import("node:fs/promises").then((m) =>
    m.readFile(geometryPath, "utf8"),
  );
  if (!geometrySrc.includes("surfaceArea")) {
    throw new Error("rename did not land");
  }
  for (const needle of [
    "int surfaceArea(int w, int h)",
    "return (w * h);",
    "int doubled(int f)",
    "return (f * 2);",
  ]) {
    if (!geometrySrc.includes(needle)) {
      throw new Error(`post-state missing "${needle}" in geometry.dart`);
    }
  }
  transcript.push("[post] rename + body replacement + insert landed in lib/geometry.dart");
  transcript.push(`[post] geometry.dart:\n${geometrySrc}`);

  const analyze = execFileSync("dart", ["analyze"], {
    cwd: fixture,
    encoding: "utf8",
  });
  transcript.push(`[post] dart analyze exit=0\n${analyze.slice(0, 300)}`);
  const testRun = execFileSync("dart", ["test"], {
    cwd: fixture,
    encoding: "utf8",
  });
  transcript.push(`[post] dart test exit=0\n${testRun.split("\n").slice(-3).join("\n")}`);

  transcript.push(
    "=== VERDICT: PASS (full edit surface over ACP: replace_member_body + " +
      "apply_executable + insert_member through the structured harness_edit " +
      "contract; analyze + workspace convention green; pi fs tools disabled) ===",
  );

  mkdirSync(path.dirname(TRANSCRIPT), { recursive: true });
  writeFileSync(TRANSCRIPT, transcript.join("\n") + "\n");
  console.log(`\ntranscript written: ${TRANSCRIPT}`);
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
  modelServer?.close();
  daemon?.dispose();
  // Gate hygiene: the fixture workspace is disposable — remove it (the
  // transcript carries the post-state record).
  if (fixtureDir) {
    try {
      rmSync(fixtureDir, { recursive: true, force: true });
      console.log(`fixture removed: ${fixtureDir}`);
    } catch {}
  }
  process.exit(process.exitCode ?? 0);
}
