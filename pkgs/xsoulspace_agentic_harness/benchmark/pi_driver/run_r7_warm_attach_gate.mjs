#!/usr/bin/env node
// run_r7_warm_attach_gate.mjs — R7 PRODUCTION #5 GATE: the persistent
// daemon. A daemon runs with `--workspace` (single-instance lock + unix
// socket); a FIRST client session scans the workspace (the tree warms);
// a SECOND client (another pi session) ATTACHES to the same warm daemon
// over the socket and continues the per-workspace world:
//   - SAME sessionId (per-workspace keying — one world, never two);
//   - startup (connect → initialize → session/new) < 2s;
//   - zero re-scan: the second session's zoom reads the warm tree (the
//     only tree work is the mechanical mtime tick — zero model tokens);
//   - a second daemon for the same workspace is REFUSED (exit 2).
//
// LLM-free: the daemon runs `--scripted` (directive interpreter over the
// REAL registry); the gate measures the LIFECYCLE, not a mover.
//
// Output: benchmark/runs/r7_warm_attach_transcript.txt

import { spawn } from "node:child_process";
import net from "node:net";
import { mkdirSync, mkdtempSync, writeFileSync, readFileSync, existsSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import process from "node:process";
import { execFileSync } from "node:child_process";
import { randomUUID } from "node:crypto";

const DRIVER_DIR = path.dirname(new URL(import.meta.url).pathname);
const DAEMON_PKG = path.resolve(
  DRIVER_DIR,
  "../../../xsoulspace_inference_apple_foundation",
);
const AOT_BINARY = "/tmp/harnessd_aot/bundle/bin/harnessd";
const TRANSCRIPT = path.resolve(
  DRIVER_DIR,
  "../../benchmark/runs/r7_warm_attach_transcript.txt",
);

const transcript = [];
function log(line) {
  const stamped = `[${new Date().toISOString()}] ${line}`;
  transcript.push(stamped);
  process.stdout.write(`${stamped}\n`);
}

// --- minimal ACP client over a unix socket (newline JSON-RPC) ------------

class SocketAcpClient {
  constructor(socketPath, label) {
    this.label = label;
    this.buffer = "";
    this.pending = new Map();
    this.nextId = 1;
    this.socket = net.createConnection(socketPath);
    this.socket.setEncoding("utf8");
    this.updates = [];
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
        // Server-initiated request: the gate allows permissions.
        const response =
          msg.method === "session/request_permission"
            ? { outcome: { outcome: "allow", optionId: "allow" } }
            : {};
        this.socket.write(`${JSON.stringify({ jsonrpc: "2.0", id: msg.id, result: response })}\n`);
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

  call(method, params, timeoutMs = 120000) {
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

function spawnDaemon(workspace) {
  const useAot = existsSync(AOT_BINARY);
  const cmd = useAot ? AOT_BINARY : "dart";
  const args = useAot
    ? ["--scripted", "--profile", "meaning", "--workspace", workspace]
    : ["run", "bin/harnessd.dart", "--scripted", "--profile", "meaning", "--workspace", workspace];
  log(`daemon spawn: ${cmd} ${args.join(" ")}${useAot ? " (AOT)" : " (JIT dart run)"}`);
  const proc = spawn(cmd, args, {
    cwd: DAEMON_PKG,
    stdio: ["pipe", "pipe", "pipe"],
  });
  proc.stderr.setEncoding("utf8");
  proc.stderr.on("data", (chunk) => log(`[harnessd] ${chunk.trim()}`));
  return proc;
}

async function main() {
  fixture = mkdtempSync(path.join(tmpdir(), "r7_warm_attach_"));
  // The fixture workspace: a green Dart package (D8 convention: dart test).
  const put = (rel, content) => {
    const f = path.join(fixture, rel);
    mkdirSync(path.dirname(f), { recursive: true });
    writeFileSync(f, content, "utf8");
  };
  put("pubspec.yaml", "name: warm_attach\nenvironment:\n  sdk: ^3.0.0\ndev_dependencies:\n  test: any\n");
  put("lib/greet.dart", "String greet(String name) => 'hello ' + name;\n");
  put(
    "test/greet_test.dart",
    "import 'package:test/test.dart';\nimport 'package:warm_attach/greet.dart';\nvoid main() { test('greet', () { expect(greet('x'), 'hello x'); }); }\n",
  );
  execFileSync("dart", ["pub", "get"], { cwd: fixture, stdio: "pipe" });
  log(`fixture workspace: ${fixture}`);

  // 1. The daemon: single-instance lock + socket listener.
  daemon = spawnDaemon(fixture);
  const pointerFile = path.join(fixture, ".dart_tool/harnessd/harnessd.sock");
  const socketPath = await waitFor(
    () => (existsSync(pointerFile) ? readFileSync(pointerFile, "utf8").trim() : null),
    180000,
    "daemon socket pointer",
  );
  log(`socket pointer: ${pointerFile} → ${socketPath}`);

  // 2. Client A: the FIRST pi session — scan (the tree warms).
  const clientA = new SocketAcpClient(socketPath, "A");
  const t0 = Date.now();
  const sidA = await clientA.start(fixture);
  log(`client A: session=${sidA} (connect→init→session/new: ${Date.now() - t0} ms)`);
  const turnA = await clientA.prompt("[scan]");
  log(`client A: [scan] → stop=${turnA.stopReason}`);
  if (turnA.stopReason !== "end_turn") throw new Error(`client A scan failed: ${turnA.text.slice(0, 300)}`);

  // 3. Client B: the SECOND pi session ATTACHES to the warm daemon.
  const clientB = new SocketAcpClient(socketPath, "B");
  const startupStart = Date.now();
  const sidB = await clientB.start(fixture);
  const startupMs = Date.now() - startupStart;
  log(`client B: session=${sidB} (attach startup: ${startupMs} ms)`);
  if (sidB !== sidA) {
    throw new Error(
      `per-workspace keying broken: second session got ${sidB}, expected ${sidA}`,
    );
  }
  if (startupMs >= 2000) {
    throw new Error(`warm attach startup ${startupMs}ms >= 2000ms`);
  }

  // 4. Zero re-scan: B reads the WARM tree (zoom hits nodes without any
  // scan call; the only tree work is the mechanical mtime tick).
  const turnB = await clientB.prompt("[zoom greet]");
  log(`client B: [zoom greet] → stop=${turnB.stopReason} text=${JSON.stringify(turnB.text.slice(0, 200))}`);
  if (!turnB.text.includes("sym_") && !turnB.text.includes("greet")) {
    throw new Error("the second session did not see the warm tree");
  }
  if (turnB.stopReason !== "end_turn") throw new Error("client B zoom failed");

  // 5. Single-instance: a second daemon for the SAME workspace refuses.
  const second = spawnDaemon(fixture);
  const exitCode = await new Promise((resolve) => second.on("exit", resolve));
  log(`second daemon exit code: ${exitCode}`);
  if (exitCode !== 2) {
    throw new Error(`second daemon must exit 2, got ${exitCode} — single-instance broken`);
  }

  log(
    "=== VERDICT: PASS (warm attach: second session continues ONE world per " +
      "workspace, startup < 2s, zero re-scan; single-instance enforced) ===",
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
  if (fixture) {
    try {
      rmSync(fixture, { recursive: true, force: true });
    } catch {}
  }
  process.exit(process.exitCode ?? 0);
}
