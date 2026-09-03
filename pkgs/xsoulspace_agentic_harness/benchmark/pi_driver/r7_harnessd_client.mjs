// r7_harnessd_client.mjs — minimal ACP client over stdio for `harnessd`.
//
// Newline-delimited JSON-RPC (dart_acp_toolkit framing). Used by both the
// pi extension (r7_harnessd_extension.ts imports this module) and the R7
// daemon transcript gate (run_r7_daemon_gate.mjs). The daemon learns no
// transport; this client is transport + policy only (D5).

import { spawn } from "node:child_process";

export class HarnessdClient {
  /**
   * @param {string} daemonCommand e.g. "dart"
   * @param {string[]} daemonArgs e.g. ["run","bin/harnessd.dart","--profile","meaning","--scripted"]
   * @param {string} daemonCwd the package dir harnessd runs from
   * @param {string} workspaceCwd the workspace the daemon delegates into
   * @param {(line: string) => void} [log] transcript sink
   */
  constructor(daemonCommand, daemonArgs, daemonCwd, workspace, log) {
    this.workspace = workspace;
    this.log = log ?? (() => {});
    this.proc = spawn(daemonCommand, daemonArgs, {
      cwd: daemonCwd,
      stdio: ["pipe", "pipe", "pipe"],
    });
    this.buffer = "";
    this.pending = new Map(); // id -> {resolve, reject}
    this.updates = []; // session/update notifications (last turn)
    this.stderr = "";
    this.nextId = 1;
    this.ready = false;
    this.proc.stdout.setEncoding("utf8");
    this.proc.stdout.on("data", (chunk) => this.#onData(chunk));
    this.proc.stderr.setEncoding("utf8");
    this.proc.stderr.on("data", (chunk) => {
      this.stderr += chunk;
      this.log?.(`[harnessd.stderr] ${chunk.trim()}`);
    });
    this.proc.on("exit", (code) => {
      for (const p of this.pending.values()) {
        p.reject(new Error(`harnessd exited (${code})`));
      }
    });
  }

  #onData(chunk) {
    this.buffer += chunk;
    let idx;
    while ((idx = this.buffer.indexOf("\n")) >= 0) {
      const line = this.buffer.slice(0, idx).trim();
      this.buffer = this.buffer.slice(idx + 1);
      if (!line) continue;
      let message;
      try {
        message = JSON.parse(line);
      } catch {
        this.log?.(`[harnessd.nonjson] ${line}`);
        continue;
      }
      this.#onMessage(message);
    }
  }

  #onMessage(message) {
    if (message.id != null && (message.result !== undefined || message.error !== undefined)) {
      const pending = this.pending.get(message.id);
      if (pending) {
        this.pending.delete(message.id);
        if (message.error) p_reject(pending, new Error(JSON.stringify(message.error)));
        else pending.resolve(message.result);
      }
      return;
    }
    if (message.method === "session/update") {
      // dart_acp_toolkit wraps the update: params = {sessionId, update}.
      const update = message.params?.update ?? message.params ?? {};
      this.updates.push(update);
      this.log?.(
        `[harnessd.update] ${JSON.stringify(update).slice(0, 400)}`,
      );
    }
  }

  call(method, params, timeoutMs = 600000) {
    const id = this.nextId++;
    const promise = new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      setTimeout(() => {
        if (this.pending.has(id)) {
          this.pending.delete(id);
          reject(new Error(`${method} timed out`));
        }
      }, timeoutMs);
    });
    const line = JSON.stringify({ jsonrpc: "2.0", id, method, params });
    this.log?.(`[acp ->] ${method} ${JSON.stringify(params ?? {}).slice(0, 300)}`);
    this.proc.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id, method, params })}\n`);
    return promise;
  }

  async start() {
    const init = await this.call("initialize", {
      protocolVersion: 1,
      clientCapabilities: {},
    });
    this.log?.(`[acp initialize] ${JSON.stringify(init)}`);
    const created = await this.call("session/new", { cwd: this.workspace });
    this.sessionId = created.sessionId;
    this.log?.(`[acp session/new] ${JSON.stringify(created)}`);
    return { capabilities: init.agentCapabilities, sessionId: this.sessionId };
  }

  /**
   * One delegated daemon turn. Resolves with the streamed text chunks.
   * @param {string} text
   * @returns {Promise<{stopReason: string, text: string, updates: object[]}>}
   */
  async prompt(text) {
    this.updates = [];
    const chunks = [];
    const result = await this.call("session/prompt", {
      sessionId: this.sessionId,
      prompt: [{ type: "text", text }],
    });
    const texts = this.updates
      .filter((u) => u.sessionUpdate === "agent_message_chunk")
      .map((u) => u.content?.text ?? "");
    const toolUpdates = this.updates.filter(
      (u) => u.sessionUpdate === "tool_call_update",
    );
    this.log?.(`[acp <- stopReason] ${result?.stopReason}`);
    return {
      stopReason: result?.stopReason ?? "?",
      text: texts.join(""),
      updates: this.updates.slice(),
      toolCallIds: toolUpdates.map((u) => u.toolCallId),
    };
  }

  dispose() {
    try {
      this.proc.kill();
    } catch {}
  }
}

function p_reject(p, error) {
  p.reject(error);
}