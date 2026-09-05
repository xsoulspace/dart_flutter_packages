#!/usr/bin/env node
// run_r7_pi_interactive_consent_gate.mjs — PLAN §NOW #6 GATE: ONE
// real-model interactive session, pi → daemon, CONSENT EXERCISED.
//
// This gate runs pi THE CLI in RPC mode with the r7_harnessd_extension
// loaded — the REAL surface pi works through (not the SDK-embedded gate
// artifact of production #7, which auto-allowed permissions and answered
// proposals model-less). Assertions:
//   1. pi's configured model answers session/propose_move (the interactive
//      remote mover — the daemon is model-less; pi is the brain);
//   2. consent rides session/request_permission surfaced through pi's
//      extension-UI protocol: ALLOW ONCE → the write_review mutation
//      LANDS; DENY ONCE → the mutation NEVER lands (deny-by-default is
//      structural — the extension's handler defaults to reject, and the
//      no-UI fallback rejects too);
//   3. the file surface is the daemon's only surface (pi built-ins are
//      disabled by the extension's setActiveTools).
//
// Output: benchmark/runs/r7_pi_interactive_consent_transcript.txt
// Requires OPENROUTER_API_KEY; PI_ROW_MODEL overrides (default
// z-ai/glm-5.3-flash).

import { spawn } from "node:child_process";
import { mkdirSync, mkdtempSync, writeFileSync, readFileSync, existsSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import process from "node:process";
import { execFileSync } from "node:child_process";

const DRIVER_DIR = path.dirname(new URL(import.meta.url).pathname);
const REPO_ROOT = path.resolve(DRIVER_DIR, "../../..");
const DAEMON_PKG = path.resolve(DRIVER_DIR, "../../../xsoulspace_inference_apple_foundation");
const EXTENSION = path.resolve(DRIVER_DIR, "r7_harnessd_extension.ts");
const TRANSCRIPT = path.resolve(
  DRIVER_DIR,
  "../../benchmark/runs/r7_pi_interactive_consent_transcript.txt",
);

const transcript = [];
function log(line) {
  const stamped = `[${new Date().toISOString()}] ${line}`;
  transcript.push(stamped);
  process.stdout.write(`${stamped}\n`);
}

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

// --- the pi RPC client (JSONL over stdio; LF framing per docs/rpc.md) ----

class PiRpcClient {
  constructor(proc) {
    this.proc = proc;
    this.buffer = "";
    this.pending = new Map();
    this.nextId = 1;
    this.events = [];
    this.onExtensionUi = null; // async (request) => response payload
    this.agentEndWaiters = [];
    proc.stdout.setEncoding("utf8");
    proc.stdout.on("data", (chunk) => this.#onData(chunk));
    proc.stderr.setEncoding("utf8");
    proc.stderr.on("data", (chunk) => {
      const line = chunk.trim();
      if (line) log(`[pi.stderr] ${line}`);
    });
  }

  #onData(chunk) {
    this.buffer += chunk;
    let idx;
    while ((idx = this.buffer.indexOf("\n")) >= 0) {
      const line = this.buffer.slice(0, idx).replace(/\r$/, "").trim();
      this.buffer = this.buffer.slice(idx + 1);
      if (!line) continue;
      let msg;
      try {
        msg = JSON.parse(line);
      } catch {
        continue;
      }
      if (msg.type === "extension_ui_request" && msg.id != null) {
        const handler = this.onExtensionUi;
        log(
          `[pi.ui] ${msg.method}: ${msg.title ?? ""}` +
            (msg.message ? ` — ${String(msg.message).slice(0, 200)}` : ""),
        );
        (handler
          ? handler(msg).catch(() => ({ confirmed: false }))
          : Promise.resolve({ confirmed: false })
        ).then((response) =>
          this.proc.stdin.write(
            `${JSON.stringify({ type: "extension_ui_response", id: msg.id, ...response })}\n`,
          ),
        );
        continue;
      }
      if (msg.type === "response" && msg.id != null) {
        const pending = this.pending.get(msg.id);
        if (pending) {
          this.pending.delete(msg.id);
          if (msg.success === false) pending.reject(new Error(JSON.stringify(msg)));
          else pending.resolve(msg);
        }
        continue;
      }
      if (msg.type && msg.type !== "response") {
        this.events.push(msg);
        if (msg.type === "agent_end") {
          for (const w of this.agentEndWaiters.splice(0)) w();
        }
      }
    }
  }

  command(payload, timeoutMs = 120000) {
    const id = payload.id ?? `cmd-${this.nextId++}`;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      setTimeout(() => {
        if (this.pending.has(id)) {
          this.pending.delete(id);
          reject(new Error(`${payload.type} timed out`));
        }
      }, timeoutMs);
      this.proc.stdin.write(`${JSON.stringify({ ...payload, id })}\n`);
    });
  }

  async prompt(message) {
    this.agentEndWaiters.length = 0;
    const ended = new Promise((resolve) => this.agentEndWaiters.push(resolve));
    await this.command({ type: "prompt", message }, 120000);
    await Promise.race([
      ended,
      new Promise((resolve) => setTimeout(resolve, 600000)),
    ]);
  }

  kill() {
    this.proc.kill();
  }
}

// --- the gate ------------------------------------------------------------

let pi = null;
let fixture = null;

async function main() {
  const apiKey = process.env.OPENROUTER_API_KEY;
  if (!apiKey) throw new Error("OPENROUTER_API_KEY not set — the gate needs a real model");
  const modelId = process.env.PI_ROW_MODEL ?? "z-ai/glm-5.3-flash";

  // The fixture: green convention (D8) + two review-write targets.
  fixture = mkdtempSync(path.join(tmpdir(), "r7_pi_consent_"));
  const put = (rel, content) => {
    const f = path.join(fixture, rel);
    mkdirSync(path.dirname(f), { recursive: true });
    writeFileSync(f, content, "utf8");
  };
  put("pubspec.yaml", "name: r7_pi_consent\nenvironment:\n  sdk: ^3.0.0\ndev_dependencies:\n  test: any\n");
  put("lib/greet.dart", "String greet(String name) => 'hello ' + name;\n");
  put(
    "test/greet_test.dart",
    "import 'package:test/test.dart';\nimport 'package:r7_pi_consent/greet.dart';\nvoid main() { test('greet', () { expect(greet('x'), 'hello x'); }); }\n",
  );
  put("notes.md", "# Notes\n\noriginal\n");
  put("report.md", "# Report\n\noriginal\n");
  execFileSync("dart", ["pub", "get"], { cwd: fixture, stdio: "pipe" });
  log(`fixture workspace: ${fixture}`);

  // pi THE CLI, RPC mode, the extension loaded, cwd = the fixture. The
  // extension spawns/attaches the daemon (--remote-mover) on the first
  // harness tool call and disables pi's built-in file tools.
  pi = new PiRpcClient(
    spawn(
      "pi",
      [
        "--mode", "rpc",
        "--no-session",
        "--no-extensions",
        "--no-skills",
        "--no-prompt-templates",
        "-e", EXTENSION,
        "--provider", "openrouter",
        "--model", modelId,
      ],
      {
        cwd: fixture,
        env: {
          ...process.env,
          OPENROUTER_API_KEY: apiKey,
          PI_HARNESSD: "1",
          HARNESSD_PKG: DAEMON_PKG,
        },
        stdio: ["pipe", "pipe", "pipe"],
      },
    ),
  );

  // THE CONSENT PLAN: allow the FIRST dialog, deny every later one.
  const consents = { allowed: 0, denied: 0 };
  pi.onExtensionUi = async (request) => {
    if (request.method !== "confirm") return { confirmed: false };
    if (consents.allowed === 0) {
      consents.allowed++;
      log("[consent] ALLOW (first request — the human said yes)");
      return { confirmed: true };
    }
    consents.denied++;
    log("[consent] DENY (a later request — the human said no)");
    return { confirmed: false };
  };

  // Phase A — the ALLOWED write must LAND (pi's model drives the daemon;
  // the daemon's write_review asks consent; the human allows).
  const notesBefore = readFileSync(path.join(fixture, "notes.md"), "utf8");
  log(`--- phase A: consented write_review on notes.md (allow once) ---`);
  await pi.prompt(
    "Use the harness_fs_write tool to update notes.md so its full content " +
      "becomes exactly:\n# Notes\n\nconsent round-trip works\n" +
      "Then report what the daemon replied.",
  );
  const notesAfter = existsSync(path.join(fixture, "notes.md"))
    ? readFileSync(path.join(fixture, "notes.md"), "utf8")
    : "";
  const allowedLanded = notesAfter !== notesBefore && notesAfter.includes("consent round-trip works");
  log(`phase A: notes.md ${allowedLanded ? "UPDATED (consented write landed)" : "NOT updated"}`);

  // Phase B — the DENIED write must NEVER land.
  log(`--- phase B: denied write_review on report.md (deny once) ---`);
  await pi.prompt(
    "Use the harness_fs_write tool to update report.md so its full content " +
      "becomes exactly:\n# Report\n\nthis must never land\n" +
      "If the daemon rejects it, say so and finish.",
  );
  const reportAfter = existsSync(path.join(fixture, "report.md"))
    ? readFileSync(path.join(fixture, "report.md"), "utf8")
    : "";
  const denyHeld = reportAfter === "# Report\n\noriginal\n";
  log(`phase B: report.md ${denyHeld ? "UNTOUCHED (the reject never landed)" : "CHANGED — LAW VIOLATION"}`);

  const passed = allowedLanded && denyHeld && consents.allowed >= 1 && consents.denied >= 1;
  log(
    `=== VERDICT: ${passed ? "PASS" : "FAIL"} — consents: ` +
      `${consents.allowed} allowed, ${consents.denied} denied; ` +
      `allow landed: ${allowedLanded}; deny held: ${denyHeld} ===`,
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
  pi?.kill();
  if (fixture) {
    try {
      rmSync(fixture, { recursive: true, force: true });
    } catch {}
  }
  process.exit(process.exitCode ?? 0);
}
