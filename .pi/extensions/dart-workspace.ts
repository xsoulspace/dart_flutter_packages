/**
 * dart-workspace extension for pi — scoped validation gate + test-failure baselines.
 *
 * Built from real workflow friction in the dart_flutter_packages workspace:
 * - Validation must be scoped to one package (`just check|analyze-one|test-one|demo`)
 * - Pre-existing test failures must not be re-investigated every session;
 *   a recorded baseline lets us report ONLY new failures (and fixed ones).
 *
 * Tools registered:
 *   workspace_check     — scoped analyze/test/demo/all for one package
 *   test_baseline_record— record currently failing tests for a package
 *   test_baseline_check — run tests, report new vs baseline failures
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { execFile } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync, existsSync } from "node:fs";
import { join } from "node:path";

const REPO_ROOT = "/Users/antonio/xs/storage_problem/dart_flutter_packages";
const BASELINE_DIR = join(REPO_ROOT, ".pi", "test-baselines");
const DEFAULT_PKG = "xsoulspace_inference_core";

interface TestFailure {
	testId: string;
	name: string;
}

function run(
	cmd: string,
	args: string[],
	opts: { cwd: string; timeoutMs?: number },
): Promise<{ code: number; stdout: string; stderr: string }> {
	return new Promise((resolve) => {
		execFile(
			cmd,
			args,
			{ cwd: opts.cwd, timeout: opts.timeoutMs ?? 900_000, maxBuffer: 64 * 1024 * 1024 },
			(err, stdout, stderr) => {
				resolve({
					code: err && typeof (err as { code?: number }).code === "number" ? (err as { code: number }).code : err ? 1 : 0,
					stdout: stdout?.toString() ?? "",
					stderr: stderr?.toString() ?? "",
				});
			},
		);
	});
}

function pkgDir(pkg: string): string {
	return join(REPO_ROOT, "pkgs", pkg);
}

function assertPkg(pkg: string): void {
	if (!existsSync(pkgDir(pkg))) {
		throw new Error(`Unknown package '${pkg}' — no ${pkgDir(pkg)} directory.`);
	}
}

/** Run `flutter test --reporter json` and extract failing test names. */
async function runTestsJson(pkg: string): Promise<{ failures: TestFailure[]; passedCount: number; rawTail: string }> {
	const res = await run("flutter", ["test", "--reporter", "json"], {
		cwd: pkgDir(pkg),
		timeoutMs: 900_000,
	});
	const names = new Map<string, string>();
	const failures: TestFailure[] = [];
	let passedCount = 0;
	for (const line of res.stdout.split("\n")) {
		if (!line.startsWith("{")) continue;
		let evt: Record<string, unknown>;
		try {
			evt = JSON.parse(line) as Record<string, unknown>;
		} catch {
			continue;
		}
		if (evt.type === "testStart" && typeof evt.test === "object") {
			const test = evt.test as { id?: number; name?: string };
			if (typeof test.id === "number" && typeof test.name === "string") names.set(String(test.id), test.name);
		} else if (evt.type === "testDone" && typeof evt.testID !== "undefined") {
			const id = String(evt.testID);
			if (evt.result === "success") passedCount++;
			else if (evt.result !== "silent" && evt.hidden !== true) failures.push({ testId: id, name: names.get(id) ?? id });
		}
	}
	const tail = `${res.stdout}\n${res.stderr}`.split("\n").slice(-15).join("\n");
	return { failures, passedCount, rawTail: tail };
}

function baselinePath(pkg: string): string {
	return join(BASELINE_DIR, `${pkg}.json`);
}

function readBaseline(pkg: string): Set<string> {
	const p = baselinePath(pkg);
	if (!existsSync(p)) return new Set();
	try {
		const data = JSON.parse(readFileSync(p, "utf8")) as { failures?: { name?: string }[] };
		return new Set((data.failures ?? []).map((f) => f.name ?? "").filter(Boolean));
	} catch {
		return new Set();
	}
}

export default function dartWorkspace(pi: ExtensionAPI) {
	pi.registerTool({
		name: "workspace_check",
		label: "Workspace Check",
		description:
			`Scoped validation gate for one package in the dart_flutter_packages monorepo ` +
			`(default: ${DEFAULT_PKG}). Runs the repo justfile targets instead of full-workspace ` +
			`analyze/test. Actions: 'analyze', 'test', 'demo' (run headless golden examples), 'all'.`,
		parameters: Type.Object({
			pkg: Type.Optional(Type.String({ description: `Package name under pkgs/ (default: ${DEFAULT_PKG})` })),
			action: Type.Optional(Type.Union([
				Type.Literal("analyze"),
				Type.Literal("test"),
				Type.Literal("demo"),
				Type.Literal("all"),
			], { description: "What to run (default: all)" })),
		}),
		async execute(_id, params) {
			const pkg = params.pkg ?? DEFAULT_PKG;
			assertPkg(pkg);
			const action = params.action ?? "all";
			const targets =
				action === "all"
					? ["analyze-one", "test-one"]
					: action === "analyze"
						? ["analyze-one"]
						: action === "test"
							? ["test-one"]
							: ["demo"];
			const parts: string[] = [];
			for (const target of targets) {
				const args = [target];
				if (target !== "demo") args.push(pkg);
				else if (pkg !== DEFAULT_PKG) args.push(pkg);
				const res = await run("just", args, { cwd: REPO_ROOT });
				parts.push(`### just ${args.join(" ")} → exit ${res.code}\n${(res.stdout + res.stderr).trim().split("\n").slice(-60).join("\n")}`);
				if (res.code !== 0) break; // fail fast
			}
			const text = parts.join("\n\n");
			return {
				content: [{ type: "text", text }],
				details: {},
			};
		},
	});

	pi.registerTool({
		name: "test_baseline_record",
		label: "Record Test Baseline",
		description:
			`Run the package's tests and RECORD the currently failing tests as a baseline, so later ` +
			`runs can distinguish pre-existing failures from regressions you introduce. ` +
			`Use when a package has known-failing tests before you start editing.`,
		parameters: Type.Object({
			pkg: Type.Optional(Type.String({ description: `Package name under pkgs/ (default: ${DEFAULT_PKG})` })),
		}),
		async execute(_id, params) {
			const pkg = params.pkg ?? DEFAULT_PKG;
			assertPkg(pkg);
			const { failures, passedCount } = await runTestsJson(pkg);
			mkdirSync(BASELINE_DIR, { recursive: true });
			writeFileSync(
				baselinePath(pkg),
				JSON.stringify({ recordedAt: new Date().toISOString(), failures }, null, 2),
			);
			const list = failures.map((f) => `- ${f.name}`).join("\n");
			return {
				content: [
					{
						type: "text",
						text:
							`Baseline recorded for ${pkg}: ${failures.length} failing / ${passedCount} passing.\n` +
							(failures.length ? `Known failures:\n${list}` : "No failures — clean baseline."),
					},
				],
				details: {},
			};
		},
	});

	pi.registerTool({
		name: "test_baseline_check",
		label: "Check Tests vs Baseline",
		description:
			`Run the package's tests and compare against the recorded baseline: report NEW failures ` +
			`(regressions — must fix), FIXED failures (baseline entries that now pass — consider ` +
			`re-recording), and still-failing known failures (ignorable). Requires a prior ` +
			`test_baseline_record.`,
		parameters: Type.Object({
			pkg: Type.Optional(Type.String({ description: `Package name under pkgs/ (default: ${DEFAULT_PKG})` })),
		}),
		async execute(_id, params) {
			const pkg = params.pkg ?? DEFAULT_PKG;
			assertPkg(pkg);
			const baseline = readBaseline(pkg);
			if (baseline.size === 0 && existsSync(baselinePath(pkg)) === false) {
				return {
					content: [
						{
							type: "text",
							text: `No baseline for ${pkg}. Run test_baseline_record first (or plain 'flutter test' if you expect zero failures).`,
						},
					],
					details: {},
				};
			}
			const { failures, passedCount, rawTail } = await runTestsJson(pkg);
			const current = new Set(failures.map((f) => f.name));
			const newFailures = failures.filter((f) => !baseline.has(f.name));
			const fixed = [...baseline].filter((name) => !current.has(name));
			const stillFailing = failures.filter((f) => baseline.has(f.name));

			const lines = [`Tests vs baseline for ${pkg}: ${passedCount} passed, ${current.size} failed.`];
			if (newFailures.length) {
				lines.push(`❌ NEW FAILURES (${newFailures.length}) — regressions, fix before finishing:`);
				newFailures.forEach((f) => lines.push(`  - ${f.name}`));
			} else {
				lines.push("✅ No new failures.");
			}
			if (fixed.length) {
				lines.push(`🎉 FIXED (${fixed.length}) — no longer failing, consider re-recording baseline:`);
				fixed.forEach((n) => lines.push(`  - ${n}`));
			}
			if (stillFailing.length) {
				lines.push(`⏭️ Known pre-existing failures ignored (${stillFailing.length}).`);
			}
			lines.push("", "--- last output ---", rawTail.trim());
			return {
				content: [{ type: "text", text: lines.join("\n") }],
				details: { newFailures: newFailures.length },
			};
		},
	});

	pi.on("session_start", async (_event, ctx) => {
		const hasBaselines = existsSync(BASELINE_DIR);
		ctx.ui.notify(
			hasBaselines
				? "dart-workspace: tools ready (workspace_check, test_baseline_record/check). Baselines exist in .pi/test-baselines."
				: "dart-workspace: tools ready. Tip: record a test baseline before editing packages with known-failing tests.",
			"info",
		);
	});
}
