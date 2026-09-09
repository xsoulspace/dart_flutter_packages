#!/usr/bin/env node
// run_r7_multi_worker_gate.mjs — RUNG-1 MULTI-WORKER GATE (the
// workers-as-extension-clients runway, build order item 5 operational
// half; the contract: docs/agent/multi_actor_workers.md, the spawn brief:
// worker_spawn_brief_template.md).
//
// THE CLAIM UNDER TEST: two workers — two independent agent clients —
// attach to ONE per-workspace harnessd daemon and land DISJOINT edits
// through the same mechanical surface, with the package suite green.
// No worker ever holds raw tools; all work rides the daemon (warm tree,
// shared world, shared consent paths).
//
// Modes:
//   --scripted (default) — LLM-free. The daemon runs `--scripted`
//     (directive interpreter over the REAL registry) and the two
//     "workers" are simulated extension clients over the SAME unix
//     socket, taking the EXACT attach path the pi extension takes
//     (pointer read → connect → initialize → session/new → per-workspace
//     session keying). Validates the gate logic WITHOUT live model creds.
//   --live — real rung-1: the daemon runs `--remote-mover` and TWO real
//     `pi -e r7_harnessd_extension.ts` workers are spawned SEQUENTIALLY
//     (v1 daemon is one-actor-at-a-time; concurrent co-presence is rung-2
//     machinery — the doc's non-claims name this). Requires
//     OPENROUTER_API_KEY (pi's provider); PI_ROW_MODEL overrides the
//     model. NOT run by this lane — the wiring lanes own the live row.
//
// Output: benchmark/runs/r7_multi_worker_transcript.txt

import { spawn, execFileSync } from "node:child_process";
import net from "node:net";
import {
  mkdirSync,
  mkdtempSync,
  writeFileSync,
  readFileSync,
  existsSync,
  rmSync,
} from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import process from "node:process";

const DRIVER_DIR = path.dirname(new URL(import.meta.url).pathname);
// ADR 0027 §4 — JIT `dart run` is the DEFAULT (always current daemon
// code; the stale-AOT-bundle lesson is surface_gaps 2026-09-06). Opt into
// AOT explicitly with HARNESSD_AOT=/path/to/binary.
const AOT_BINARY = process.env.HARNESSD_AOT ?? "";
const DAEMON_PKG = path.resolve(
  DRIVER_DIR,
  "../../../xsoulspace_inference_apple_foundation",
);
const EXTENSION = path.join(DRIVER_DIR, "r7_harnessd_extension.ts");
const TRANSCRIPT = path.resolve(
  DRIVER_DIR,
  "../../benchmark/runs/r7_multi_worker_transcript.txt",
);
const LIVE = process.argv.includes("--live");

const transcript = [];
function log(line) {
  const stamped = `[${new Date().toISOString()}] ${line}`;
  transcript.push(stamped);
  process.stdout.write(`${stamped}\n`);
}

// --- minimal ACP client over a unix socket (newline JSON-RPC) ------------
// The same wire shape the pi extension speaks (r7_harnessd_extension.ts):
// server-initiated request_permission is answered (allow — a consented
// gate fixture; a real worker surfaces it to the human), updates are
// collected per turn.

class SocketAcpClient {
  constructor(socketPath, label) {
    this.label = label;
    this.buffer = "";
    this.pending = new Map();
    this.nextId = 1;
    this.socket = net.createConnection(socketPath);
    this.socket.setEncoding("utf8");
    this.updates = [];
    this.sessionId = "";
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
      if (msg.method != null && msg.id != null) {
        const response =
          msg.method === "session/request_permission"
            ? { outcome: { outcome: "allow", optionId: "allow" } }
            : {};
        this.socket.write(
          `${JSON.stringify({ jsonrpc: "2.0", id: msg.id, result: response })}\n`,
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
        this.updates.push(msg.params?.update ?? msg.params ?? {});
      }
    }
  }

  call(method, params, timeoutMs = 300000) {
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

  // The extension's attach path: initialize (health ping) → session/new.
  // Per-workspace keying returns the SAME session id to every client.
  async start(workspace) {
    await this.call("initialize", { protocolVersion: 1, clientCapabilities: {} });
    const created = await this.call("session/new", { cwd: workspace });
    this.sessionId = created.sessionId;
    return created.sessionId;
  }

  async prompt(text) {
    this.updates = [];
    const result = await this.call("session/prompt", {
      sessionId: this.sessionId,
      prompt: [{ type: "text", text }],
    });
    const texts = this.updates
      .filter((u) => u.sessionUpdate === "agent_message_chunk")
      .map((u) => u.content?.text ?? "");
    return { stopReason: result?.stopReason, text: texts.join("") };
  }

  close() {
    this.socket.end();
  }
}

// --- fixture: one green Dart package, TWO disjoint edit targets ----------

function createFixtureWorkspace() {
  const ws = mkdtempSync(path.join(tmpdir(), "r7_multi_worker_"));
  const put = (rel, content) => {
    const f = path.join(ws, rel);
    mkdirSync(path.dirname(f), { recursive: true });
    writeFileSync(f, content, "utf8");
  };
  put(
    "pubspec.yaml",
    ["name: multi_worker_gate", "environment:", "  sdk: ^3.0.0", "dev_dependencies:", "  test: any", ""].join("\n"),
  );
  // Worker A's disjoint target: geometry.dart / Box.
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
  // Worker B's disjoint target: text_ops.dart / Speaker.
  put(
    "lib/text_ops.dart",
    [
      "String shout(String s) {",
      "  return s.toUpperCase();",
      "}",
      "",
      "class Speaker {",
      "  String name() {",
      "    return 'box';",
      "  }",
      "}",
      "",
    ].join("\n"),
  );
  put(
    "test/geometry_test.dart",
    [
      "import 'package:test/test.dart';",
      "import 'package:multi_worker_gate/geometry.dart';",
      "",
      "void main() {",
      "  test('area', () {",
      "    expect(area(2, 3), 6);",
      "  });",
      "}",
      "",
    ].join("\n"),
  );
  put(
    "test/text_ops_test.dart",
    [
      "import 'package:test/test.dart';",
      "import 'package:multi_worker_gate/text_ops.dart';",
      "",
      "void main() {",
      "  test('shout', () {",
      "    expect(shout('hi'), 'HI');",
      "  });",
      "}",
      "",
    ].join("\n"),
  );
  execFileSync("dart", ["pub", "get"], { cwd: ws, stdio: "pipe" });
  return ws;
}

// --- daemon + socket plumbing (the warm-attach gate's proven paths) ------

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

function socketPointerPath(workspace) {
  return path.join(workspace, ".dart_tool", "harnessd", "harnessd.sock");
}

function spawnDaemon(workspace, live) {
  const useAot = AOT_BINARY.length > 0 && existsSync(AOT_BINARY);
  const mode = live ? "--remote-mover" : "--scripted";
  const cmd = useAot ? AOT_BINARY : "dart";
  const args = useAot
    ? [mode, "--profile", "meaning", "--workspace", workspace]
    : ["run", "bin/harnessd.dart", mode, "--profile", "meaning", "--workspace", workspace];
  log(`daemon spawn: ${cmd} ${args.join(" ")}${useAot ? " (AOT)" : " (JIT dart run)"}`);
  const proc = spawn(cmd, args, { cwd: DAEMON_PKG, stdio: ["pipe", "pipe", "pipe"] });
  proc.stderr.setEncoding("utf8");
  proc.stderr.on("data", (chunk) => log(`[harnessd] ${chunk.trim()}`));
  return proc;
}

// --- scripted mode: two SIMULATED extension clients on one socket --------

function extractSymbolIds(text) {
  return [...text.matchAll(/sym_[A-Za-z0-9_.$]+/g)].map((m) => m[0]);
}

async function scriptedMode(fixture) {
  // THE co-presence claim: worker A attaches, scans (the tree warms),
  // edits Box; worker B attaches to the SAME daemon AFTER A, zooms the
  // WARM tree (zero re-scan) and edits Speaker — disjoint targets, one
  // world, one writer.
  const clientA = new SocketAcpClient(fixture.socketPath, "worker-A");
  const sidA = await clientA.start(fixture.ws);
  log(`worker A: session=${sidA} (attached over the daemon socket)`);

  // Worker A warms the world for everyone (the scan is per-WORKSPACE, not
  // per-client — B must never re-pay it).
  const scanA = await clientA.prompt("[scan]");
  log(`worker A: [scan] → stop=${scanA.stopReason}`);
  if (scanA.stopReason !== "end_turn") {
    throw new Error(`worker A scan failed: ${scanA.text.slice(0, 300)}`);
  }

  // Worker B attaches MID-SESSION (after the scan): per-workspace keying
  // must return the SAME session id — co-presence on one world.
  const clientB = new SocketAcpClient(fixture.socketPath, "worker-B");
  const tAttach = Date.now();
  const sidB = await clientB.start(fixture.ws);
  log(`worker B: session=${sidB} (attach startup: ${Date.now() - tAttach} ms)`);
  if (sidB !== sidA) {
    throw new Error(
      `per-workspace keying broken: worker B got ${sidB}, expected ${sidA} — two worlds, not one`,
    );
  }
  if (Date.now() - tAttach >= 2000) {
    throw new Error("warm attach startup >= 2000ms");
  }

  // Worker A: locate Box (cursor), zoom the cut, read the ids.
  const zoomA = await clientA.prompt(
    `harness_meaning_program ${JSON.stringify({
      ops: [
        { op: "locate", query: "Box" },
        { op: "zoom", budget: 2000 },
      ],
    })}`,
  );
  log(`worker A: locate+zoom Box → stop=${zoomA.stopReason}`);
  if (zoomA.stopReason !== "end_turn") throw new Error("worker A zoom failed");
  const boxId = extractSymbolIds(zoomA.text).find((id) => id.endsWith("_Box"));
  if (!boxId) {
    throw new Error(`worker A could not resolve the Box symbol id from the cut:\n${zoomA.text.slice(0, 800)}`);
  }
  log(`worker A: Box id=${boxId} (read from the cut, never guessed)`);

  // Worker B: WARM read — no [scan], the shared tree already covers it.
  const zoomB = await clientB.prompt(
    `harness_meaning_program ${JSON.stringify({
      ops: [
        { op: "locate", query: "Speaker" },
        { op: "zoom", budget: 2000 },
      ],
    })}`,
  );
  log(`worker B: locate+zoom Speaker (warm tree, zero re-scan) → stop=${zoomB.stopReason}`);
  if (zoomB.stopReason !== "end_turn") throw new Error("worker B zoom failed");
  const speakerId = extractSymbolIds(zoomB.text).find((id) => id.endsWith("_Speaker"));
  if (!speakerId) {
    throw new Error(`worker B could not resolve the Speaker symbol id from the warm cut:\n${zoomB.text.slice(0, 800)}`);
  }
  log(`worker B: Speaker id=${speakerId}`);

  // THE disjoint edits: A inserts on Box (geometry.dart), B inserts on
  // Speaker (text_ops.dart). Same daemon, same consent paths, serialized
  // by the one-actor-at-a-time v1 daemon.
  const editA = await clientA.prompt(
    `harness_edit ${JSON.stringify({
      action: "insert_member",
      symbolId: boxId,
      name: "doubled",
      returns: "int",
      params: ["f:int"],
      opChain: [
        { label: "load_arg", a: "f" },
        { label: "literal", b: "2" },
        { label: "mul" },
        { label: "return" },
      ],
    })}`,
  );
  log(`worker A: harness_edit insert_member doubled → stop=${editA.stopReason} text=${JSON.stringify(editA.text.slice(0, 200))}`);
  if (editA.stopReason !== "end_turn") {
    throw new Error(`worker A edit failed: ${editA.text.slice(0, 400)}`);
  }

  const editB = await clientB.prompt(
    `harness_edit ${JSON.stringify({
      action: "insert_member",
      symbolId: speakerId,
      name: "louder",
      returns: "int",
      params: ["n:int"],
      opChain: [
        { label: "load_arg", a: "n" },
        { label: "literal", b: "3" },
        { label: "mul" },
        { label: "return" },
      ],
    })}`,
  );
  log(`worker B: harness_edit insert_member louder → stop=${editB.stopReason} text=${JSON.stringify(editB.text.slice(0, 200))}`);
  if (editB.stopReason !== "end_turn") {
    throw new Error(`worker B edit failed: ${editB.text.slice(0, 400)}`);
  }

  // The shared mechanical run path: worker A runs the package suite
  // THROUGH the daemon (allowlisted run tool).
  const runA = await clientA.prompt(
    `harness_run ${JSON.stringify({ command: ["dart", "test"] })}`,
  );
  log(`worker A: harness_run dart test → stop=${runA.stopReason} text=${JSON.stringify(runA.text.slice(0, 300))}`);
  if (runA.stopReason !== "end_turn") {
    throw new Error(`harness_run failed: ${runA.text.slice(0, 400)}`);
  }

  clientA.close();
  clientB.close();

  return {
    edits: [
      { worker: "A", file: "lib/geometry.dart", needles: ["int doubled(int f)", "return (f * 2);"] },
      { worker: "B", file: "lib/text_ops.dart", needles: ["int louder(int n)", "return (n * 3);"] },
    ],
  };
}

// --- live mode: two REAL pi -e workers, sequential (rung-1 v1) -----------

function runLivePiWorker(fixture, label, task) {
  return new Promise((resolve, reject) => {
    log(`${label}: spawning real pi worker (${task.model})`);
    const proc = spawn(
      "pi",
      [
        "--print",
        "-e",
        EXTENSION,
        "--no-session",
        "--provider",
        "openrouter",
        "--model",
        task.model,
        "--",
        task.prompt,
      ],
      {
        cwd: fixture.ws,
        env: {
          ...process.env,
          PI_HARNESSD: "1",
          HARNESSD_PKG: DAEMON_PKG,
        },
        stdio: ["ignore", "pipe", "pipe"],
      },
    );
    let out = "";
    proc.stdout.setEncoding("utf8");
    proc.stdout.on("data", (c) => {
      out += c;
    });
    proc.stderr.setEncoding("utf8");
    proc.stderr.on("data", (c) => log(`[${label}.pi] ${c.trim().slice(0, 400)}`));
    const timer = setTimeout(() => {
      proc.kill();
      reject(new Error(`${label} timed out after 25 min`));
    }, 25 * 60 * 1000);
    proc.on("exit", (code) => {
      clearTimeout(timer);
      log(`${label}: pi exit=${code}\n${out.slice(0, 1200)}`);
      if (code !== 0) reject(new Error(`${label} pi exited ${code}`));
      else resolve(out);
    });
  });
}

async function liveMode(fixture) {
  if (!process.env.OPENROUTER_API_KEY) {
    throw new Error(
      "OPENROUTER_API_KEY not set — the --live mode needs a real model " +
        "(run --scripted for the LLM-free gate)",
    );
  }
  const model = process.env.PI_ROW_MODEL ?? "z-ai/glm-5.3-flash";
  const taskFor = (file, cls, member, param) =>
    ({
      model,
      prompt:
        `You are a spawned worker. The daemon surface is your ONLY file ` +
        `surface — never use read/write/edit/bash. Scan the meaning tree, ` +
        `locate the class \`${cls}\` in ${file}, then with harness_edit ` +
        `insert_member add \`${member}(int ${param})\` returning int with ` +
        `an op-chain computing ${param} * ${member === "doubled" ? 2 : 3} ` +
        `(load_arg, literal, mul, return). Then verify. Touch NOTHING else.`,
    });
  // SEQUENTIAL on purpose (v1 daemon is one-actor-at-a-time; concurrent
  // remote-mover proposal routing between two attached clients is a named
  // rung-1 edge — rung-2 machinery, not this gate's claim).
  await runLivePiWorker(fixture, "worker-A", taskFor("lib/geometry.dart", "Box", "doubled", "f"));
  await runLivePiWorker(fixture, "worker-B", taskFor("lib/text_ops.dart", "Speaker", "louder", "n"));
  return {
    edits: [
      { worker: "A", file: "lib/geometry.dart", needles: ["int doubled(int f)", "return (f * 2);"] },
      { worker: "B", file: "lib/text_ops.dart", needles: ["int louder(int n)", "return (n * 3);"] },
    ],
  };
}

// --- the gate ------------------------------------------------------------

let daemon = null;
let secondDaemon = null;
let fixtureDir = null;

async function main() {
  log(`=== rung-1 multi-worker gate (${LIVE ? "LIVE" : "SCRIPTED"}) ===`);
  fixtureDir = createFixtureWorkspace();
  log(`fixture workspace: ${fixtureDir}`);

  daemon = spawnDaemon(fixtureDir, LIVE);
  const pointerFile = socketPointerPath(fixtureDir);
  const socketPath = await waitFor(
    () => (existsSync(pointerFile) ? readFileSync(pointerFile, "utf8").trim() : null),
    180000,
    "daemon socket pointer",
  );
  log(`socket pointer: ${pointerFile} → ${socketPath}`);

  const result = LIVE
    ? await liveMode({ ws: fixtureDir })
    : await scriptedMode({ ws: fixtureDir, socketPath });

  // ONE daemon for BOTH workers: a second daemon for the same workspace
  // is REFUSED (single-instance is mandatory — two daemons = two worlds).
  if (!LIVE) {
    secondDaemon = spawnDaemon(fixtureDir, false);
    const exitCode = await new Promise((resolve) => secondDaemon.on("exit", resolve));
    log(`second daemon exit code: ${exitCode}`);
    if (exitCode !== 2) {
      throw new Error(`second daemon must exit 2, got ${exitCode} — single-instance broken`);
    }
  }

  // Post-state: BOTH disjoint edits landed (host-side record; the daemon's
  // own analyzer + auto-revert already ran inside each edit).
  for (const edit of result.edits) {
    const src = readFileSync(path.join(fixtureDir, edit.file), "utf8");
    for (const needle of edit.needles) {
      if (!src.includes(needle)) {
        throw new Error(`worker ${edit.worker}'s edit did not land: "${needle}" missing from ${edit.file}`);
      }
    }
    log(`[post] worker ${edit.worker}: ${edit.file} carries ${JSON.stringify(edit.needles)}`);
  }

  // The package suite stays green after BOTH workers' edits.
  const testRun = execFileSync("dart", ["test"], { cwd: fixtureDir, encoding: "utf8" });
  log(`[post] dart test exit=0\n${testRun.split("\n").slice(-3).join("\n")}`);

  log(
    "=== VERDICT: PASS (rung 1: two workers as extension clients of ONE " +
      "per-workspace daemon — warm attach, per-workspace session keying, " +
      "disjoint edits landed through the mechanical surface, " +
      "single-instance enforced, package suite green) ===",
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
  daemon?.kill();
  secondDaemon?.kill();
  if (fixtureDir) {
    try {
      rmSync(fixtureDir, { recursive: true, force: true });
    } catch {}
  }
  process.exit(process.exitCode ?? 0);
}
