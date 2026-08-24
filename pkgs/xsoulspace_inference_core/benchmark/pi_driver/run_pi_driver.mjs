#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import {
  appendFile,
  mkdtemp,
  mkdir,
  readFile,
  rm,
  writeFile,
} from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { tmpdir } from "node:os";
import { parse as parseYaml } from "yaml";
import process from "node:process";
import {
  createAgentSession,
  ModelRuntime,
  SessionManager,
} from "@earendil-works/pi-coding-agent";
import { performance } from "node:perf_hooks";

const PACKAGE_ROOT = new URL(".", import.meta.url).pathname;
const CHECKER_CLI = resolve(
  PACKAGE_ROOT,
  "../coding_suite/check_workspace.dart",
);

const RETRY_BUDGET = 2;

function usage(message) {
  console.error(`run_pi_driver: ${message}`);
  console.error("usage: node run_pi_driver.mjs --tasks <dir> [--out <file>] [--keep-workspaces]");
  process.exit(64);
}

function parseArgs(argv) {
  const parsed = { tasks: undefined, out: undefined, keepWorkspaces: false };
  for (let index = 0; index < argv.length; index++) {
    if (argv[index] === "--tasks") {
      parsed.tasks = argv[++index];
    } else if (argv[index] === "--out") {
      parsed.out = argv[++index];
    } else if (argv[index] === "--keep-workspaces") {
      parsed.keepWorkspaces = true;
    } else {
      usage(`unknown argument: ${argv[index]}`);
    }
  }
  if (!parsed.tasks) usage("--tasks is required");
  return parsed;
}

async function loadTasks(directory) {
  const { readdirSync } = await import("node:fs");
  const names = readdirSync(directory).filter((name) => name.endsWith(".yaml")).sort();
  return Promise.all(
    names.map(async (name) => {
      const path = join(directory, name);
      const source = await readFile(path, "utf8");
      return { path, task: parseYaml(source) };
    }),
  );
}

function assertTaskShape(task, path) {
  for (const field of ["id", "category", "prompt"]) {
    if (typeof task?.[field] !== "string") {
      throw new Error(`invalid task ${path}: missing string field ${field}`);
    }
  }
  if (!Array.isArray(task.fixtures)) task.fixtures = [];
  if (!Array.isArray(task.checkers)) task.checkers = [];
}

async function seedWorkspace(root, task) {
  await mkdir(root, { recursive: true });
  for (const fixture of task.fixtures ?? []) {
    if (!fixture.path || typeof fixture.content !== "string") {
      throw new Error(`invalid fixture in task ${task.id}`);
    }
    const destination = join(root, fixture.path);
    await mkdir(dirname(destination), { recursive: true });
    await writeFile(destination, fixture.content);
  }
}

function addUsage(totals, usage) {
  if (!usage || typeof usage !== "object") {
    throw new Error("pi did not report real token usage");
  }
  totals.input += Number(usage.input ?? 0);
  totals.output += Number(usage.output ?? 0);
  totals.cacheRead += Number(usage.cacheRead ?? 0);
  totals.cacheWrite += Number(usage.cacheWrite ?? 0);
  totals.cost += Number(usage.cost?.total ?? 0);
}

function countToolCalls(totals, event) {
  if (event?.type !== "tool_execution_end") return;
  totals.toolCalls += 1;
}

async function runPiTurn(session, prompt) {
  const turnUsage = {
    input: 0,
    output: 0,
    cacheRead: 0,
    cacheWrite: 0,
    cost: 0,
  };
  const counters = { toolCalls: 0 };
  const listener = (event) => {
    if (event.type === "message_update") {
      const usage = event.usage ?? event.assistantMessageEvent?.usage;
      if (usage) addUsage(turnUsage, usage);
      return;
    }
    if (event.type === "message_end") {
      if (event.message.role === "assistant") {
        addUsage(turnUsage, event.message.usage);
      } else if (event.message.role === "toolResult" && event.message.usage) {
        addUsage(turnUsage, event.message.usage);
      }
      countToolCalls(counters, event);
      return;
    }
    countToolCalls(counters, event);
  };

  const unsubscribe = session.subscribe(listener);
  try {
    await session.prompt(prompt);
  } finally {
    unsubscribe?.();
  }
  if (turnUsage.input + turnUsage.output + turnUsage.cacheRead + turnUsage.cacheWrite === 0) {
    throw new Error("pi completed without real token usage");
  }
  return { ...turnUsage, toolCalls: counters.toolCalls };
}

function runChecker(taskPath, workspace) {
  const result = spawnSync(
    process.execPath.endsWith("/dart") ? process.execPath : "dart",
    ["run", CHECKER_CLI, "--task", taskPath, "--workspace", workspace],
    { encoding: "utf8", timeout: 30_000 },
  );
  if (result.error) throw result.error;
  let parsed;
  try {
    parsed = JSON.parse(result.stdout.trim());
  } catch {
    throw new Error(`checker emitted invalid JSON: ${result.stdout || result.stderr}`);
  }
  return { ...parsed, exitCode: result.status };
}

function failureMode(checker, usage, error) {
  if (error) return "driver_error";
  if (!usage) return "missing_token_usage";
  if (checker.exitCode === 64) return "checker_error";
  return "checker_failed";
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const model = process.env.OPENROUTER_MODEL;
  const apiKey = process.env.OPENROUTER_API_KEY;
  if (!model) throw new Error("OPENROUTER_MODEL is required");
  if (!apiKey) throw new Error("OPENROUTER_API_KEY is required");

  const tasksDirectory = resolve(options.tasks);
  const tasks = await loadTasks(tasksDirectory);
  if (tasks.length === 0) throw new Error(`no task YAML files in ${tasksDirectory}`);
  const output = options.out ? resolve(options.out) : undefined;
  if (output) await writeFile(output, "");

  const runtime = await ModelRuntime.create({ refreshOnCreate: false });
  runtime.setRuntimeApiKey("openrouter", apiKey);
  const modelObject = runtime.getModel("openrouter", model);
  if (!modelObject) {
    throw new Error(
      `OpenRouter model not found in pi runtime: ${model}. ` +
      "Set PI_OFFLINE=0 or provide a pi models.json containing it.",
    );
  }

  for (const { path: taskPath, task } of tasks) {
    assertTaskShape(task, taskPath);
    const workspace = await mkdtemp(join(tmpdir(), "pi-driver-"));
    const started = performance.now();
    let checker;
    let error;
    let session;
    let usage;
    try {
      await seedWorkspace(workspace, task);
      const created = await createAgentSession({
        cwd: workspace,
        model: modelObject,
        modelRuntime: runtime,
        sessionManager: SessionManager.inMemory(workspace),
        tools: ["read", "write", "edit", "bash", "ls"],
      });
      session = created.session;
      usage = await runPiTurn(session, task.prompt);
      checker = runChecker(taskPath, workspace);
      for (let round = 0; round < RETRY_BUDGET && checker.exitCode === 1; round++) {
        const details = checker.results
          .filter((result) => !result.passed)
          .map((result) => `- ${result.detail}`)
          .join("\n");
        const feedback = `The deterministic workspace checker failed. Fix these exact issues:\n${details}`;
        usage = mergeUsage(usage, await runPiTurn(session, feedback));
        checker = runChecker(taskPath, workspace);
      }
    } catch (caught) {
      error = caught;
    } finally {
      const wallClockMs = Math.round(performance.now() - started);
      const row = {
        task_id: task.id,
        passed: error === undefined && checker?.passed === true,
        wall_clock_ms: wallClockMs,
        tool_calls: usage?.toolCalls ?? 0,
        token_usage: error === undefined && usage !== undefined
          ? {
              input: usage.input,
              output: usage.output,
              cache_read: usage.cacheRead,
              cache_write: usage.cacheWrite,
              total:
                usage.input +
                usage.output +
                usage.cacheRead +
                usage.cacheWrite,
              cost: usage.cost,
            }
          : null,
        backend: "pi",
        failure_mode: failureMode(checker, usage, error),
        error: error?.message,
      };
      await appendRow(output, row);
      if (!options.keepWorkspaces) await rm(workspace, { recursive: true, force: true });
    }
  }
}

function mergeUsage(total, next) {
  return {
    input: total.input + next.input,
    output: total.output + next.output,
    cacheRead: total.cacheRead + next.cacheRead,
    cacheWrite: total.cacheWrite + next.cacheWrite,
    cost: total.cost + next.cost,
  };
}

async function appendRow(path, row) {
  const line = `${JSON.stringify(row)}\n`;
  if (path) await appendFile(path, line);
  process.stdout.write(line);
}

main().catch((error) => {
  console.error(error?.stack ?? error);
  process.exit(1);
});
