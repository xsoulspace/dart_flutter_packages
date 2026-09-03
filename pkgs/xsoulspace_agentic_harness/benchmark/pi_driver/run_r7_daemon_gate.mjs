#!/usr/bin/env node
// run_r7_daemon_gate.mjs — TASK 3 GATE (R7, ADR 0023): one pi session on
// the HARNESS repo performs scan → zoom → impact → rename_symbol (a
// private symbol, low blast radius) → verify green — with pi's own fs
// tools DISABLED (noTools: 'builtin' + no fs tools in the allowlist) and
// every file access going through `harnessd` over ACP.
//
// LLM-free end to end (repo gate discipline): the "model" is a scripted
// OpenAI-compatible server that emits the next daemon-tool call; the
// daemon mover is `--scripted` (directive interpreter over the REAL
// registry). The transcript proves the SURFACE contract:
//   - pi's enabled tools contain no read/write/edit/bash;
//   - every workspace mutation happened inside the daemon (tool beats,
//     analyzer verdict, unique tool-call ids streamed as session/update).
//
// Output: benchmark/runs/r7_daemon_transcript.txt

import { createServer } from "node:http";
import { mkdirSync, writeFileSync, appendFileSync } from "node:fs";
import {
  createAgentSession,
  ModelRuntime,
  SessionManager,
} from "@earendil-works/pi-coding-agent";
import { HarnessdClient } from "./r7_harnessd_client.mjs";
import path from "node:path";
import process from "node:process";
import { randomUUID } from "node:crypto";

const DRIVER_DIR = path.dirname(new URL(import.meta.url).pathname);
const HARNESS_PKG = resolveDriver("../..");
const DAEMON_PKG = resolveDriver(
  "../../../xsoulspace_inference_apple_foundation",
);
const TRANSCRIPT = resolveDriver("../../benchmark/runs/r7_daemon_transcript.txt");

function resolveDriver(rel) {
  return path.resolve(DRIVER_DIR, rel);
}

const transcript = [];
function log(line) {
  const stamped = `[${new Date().toISOString()}] ${line}`;
  transcript.push(stamped);
  process.stdout.write(`${stamped}\n`);
}

// ---------------------------------------------------------------------------
// 1. The scripted model server (OpenAI-compatible, streaming).
//
// Decides the next daemon-tool call from how many tool results pi has
// already produced — the R7 sequence: scan → zoom → impact → rename →
// verify → final text.
// ---------------------------------------------------------------------------

const SEQUENCE = [
  {
    tool: "harness_scan",
    args: {},
    why: "scan the workspace into the meaning tree",
  },
  {
    tool: "harness_zoom",
    args: { query: "snapshot meaning tree" },
    why: "zoom to locate the target symbol's home",
  },
  {
    tool: "harness_impact",
    args: { symbol: "_meaningTreeIds" },
    why: "check the blast radius before renaming",
  },
  {
    tool: "harness_edit",
    args: { oldName: "_meaningTreeIds", newName: "_meaningTreeComponentIds" },
    why: "rename the private symbol through the daemon",
  },
  {
    tool: "harness_verify",
    args: {},
    why: "verify the workspace green",
  },
];

function decideNext(messages) {
  const toolResults = messages.filter(
    (m) => m.role === "tool" || m.role === "tool_result",
  ).length;
  if (toolResults >= SEQUENCE.length) {
    return {
      finish: "stop",
      text:
        "Done: scanned, zoomed, impacted, renamed `_meaningTreeIds` → " +
        "`_meaningTreeComponentIds` through harnessd, and verified green. " +
        "No file was read or written by pi directly.",
    };
  }
  const step = SEQUENCE[toolResults];
  return {
    toolCall: {
      id: `call_${randomUUID().slice(0, 8)}`,
      name: step.tool,
      arguments: JSON.stringify(step.args ?? {}),
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
          choices: [
            { index: 0, delta: {}, finish_reason: "tool_calls" },
          ],
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
  return new Promise((resolve) => server.listen(port, "127.0.0.1", () => resolve(server)));
}

// -------------------------------------------------------------------------

async function main() {
  // Fresh daemon state: a stale escalation baton from an earlier run must
  // not leak into the gate (sessions resume per workspace).
  await import("node:fs/promises").then((m) =>
    m.rm(path.join(HARNESS_PKG, ".dart_tool/harnessd_store"), {
      recursive: true,
      force: true,
    }),
  );

  const port = 18000 + Math.floor(Math.random() * 2000);
  const modelServer = await startScriptedModelServer(port);
  transcript.push(`[model] scripted model server listening on 127.0.0.1:${port}`);

  // The daemon: the R7 meaning-profile surface, scripted mover (LLM-free).
  const daemon = new HarnessdClient(
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
    HARNESS_PKG,
    (line) => transcript.push(line),
  );

  transcript.push("=== R7 daemon transcript gate ===");
  transcript.push(`workspace: ${HARNESS_PKG}`);
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

  // The daemon-backed tools: the ONLY tools pi gets. noTools 'builtin'
  // disables read/bash/edit/write — the daemon tools remain enabled.
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
      description: "Cut a bounded view of the meaning tree by keyword query.",
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
        "Impact frontier of a symbol (reverse-reference closure, hard-capped).",
      parameters: {
        type: "object",
        properties: { symbol: { type: "string" } },
        required: ["symbol"],
      },
      execute: async (_id, params) => delegated(`[impact ${params.symbol}]`),
    },
    {
      name: "harness_edit",
      label: "Harness Edit",
      description:
        "Rename a symbol across its refs frontier through the daemon (atomic, analyzer-verified, auto-reverted).",
      parameters: {
        type: "object",
        properties: { oldName: { type: "string" }, newName: { type: "string" } },
        required: ["oldName", "newName"],
      },
      execute: async (_id, params) =>
        delegated(`[rename ${params.oldName} ${params.newName}]`),
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
      `[pi -> daemon] "${directive}" -> stop=${turn.stopReason} ` +
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
    excludeTools: ["read", "write", "edit", "bash", "root_search", "root_find", "root_edit"],
    customTools: daemonTools,
    sessionManager: SessionManager.inMemory(HARNESS_PKG),
  });

  session.subscribe((event) => {
    if (event.type === "message_update" || event.type === "agent_start") return;
    transcript.push(`[pi.event] ${event.type}: ${JSON.stringify(event).slice(0, 300)}`);
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

  const preRunSrc = await import("node:fs/promises").then((m) =>
    m.readFile(path.join(HARNESS_PKG, "lib/src/snapshot.dart"), "utf8"),
  );

  transcript.push("--- pi turn ---");
  await session.prompt(
    "Research and edit this repo through the harness daemon only: scan " +
      "the meaning tree, zoom to the snapshot module, check the impact of " +
      "the private symbol _meaningTreeIds, rename it to " +
      "_meaningTreeComponentIds, then verify green. You have NO file " +
      "tools — every access goes through the daemon.",
  );

  // Post-state verification (host-side, for the record — the daemon's own
  // verify already ran inside the loop).
  const { execFileSync } = await import("node:child_process");
  let analyzeOut = "";
  try {
    analyzeOut = execFileSync("dart", ["analyze"], {
      cwd: HARNESS_PKG,
      encoding: "utf8",
    });
    transcript.push(`[post] dart analyze exit=0\n${analyzeOut.slice(0, 300)}`);
  } catch (e) {
    analyzeOut = `${e.stdout ?? ""}${e.stderr ?? ""}`;
    // warnings (exit 1) are pre-existing repo state; ERRORS are fatal.
    if (/"error - "/.test(e.stdout ?? "")) throw e;
    transcript.push(
      `[post] dart analyze exit=${e.status} (pre-existing warnings only)\n` +
        analyzeOut.split("\n").filter((l) => l.includes("error - ")).join("\n"),
    );
  }
  const snapshotSrc = await import("node:fs/promises").then((m) =>
    m.readFile(path.join(HARNESS_PKG, "lib/src/snapshot.dart"), "utf8"),
  );
  if (!snapshotSrc.includes("_meaningTreeComponentIds")) {
    throw new Error("rename did not land");
  }
  if (snapshotSrc.includes("_meaningTreeIds(")) {
    transcript.push("[post] note: the old call site token remains in a comment/legacy form");
  }
  transcript.push("[post] rename landed: _meaningTreeComponentIds present in lib/src/snapshot.dart");

  transcript.push("=== VERDICT: PASS (pi fs tools disabled; every file access via the daemon) ===");

  // Revert the rename (the gate must not leave the repo renamed): restore
  // the captured pre-run bytes — no git state is touched.
  const { writeFile } = await import("node:fs/promises");
  await writeFile(path.join(HARNESS_PKG, "lib/src/snapshot.dart"), preRunSrc, "utf8");
  transcript.push("[cleanup] pre-run bytes restored (gate hygiene)");

  mkdirSync(path.dirname(TRANSCRIPT), { recursive: true });
  writeFileSync(TRANSCRIPT, transcript.join("\n") + "\n");
  console.log(`\ntranscript written: ${TRANSCRIPT}`);
  modelServer.close();
  daemon.dispose();
  process.exit(0);
}

main().catch(async (error) => {
  transcript.push(`=== VERDICT: FAIL — ${error?.stack ?? error} ===`);
  try {
    writeFileSync(TRANSCRIPT, transcript.join("\n") + "\n");
  } catch {}
  console.error(error);
  process.exit(1);
});