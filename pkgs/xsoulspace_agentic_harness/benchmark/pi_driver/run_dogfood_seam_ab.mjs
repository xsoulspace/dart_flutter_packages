// run_dogfood_seam_ab.mjs — the 2026-09-08 dogfood A/B probe (LLM-free).
//
// Measures the SURFACE-BORNE paths over the REAL monorepo tree, scripted
// (zero model tokens — the walls are the harness's own):
//   B1. one mechanical read: harness_meaning_program over the live tree
//       (the extension-dialect fix's B side; gate <100 ms warm);
//   B2. one REAL harness_edit md insert through the class-routed md
//       binding (consent answered by the client proxy — the operator).
// The A side was measured IN-SESSION through the stale extension the same
// day (the drift class the fix closes): mover-delegated reads 194,114 /
// 194,122 ms (mover_refusal), harness_edit probe 183,302 ms (zero moves).
//
// The edit is REAL: it inserts the A/B row section into
// docs/agent/results_seam_speed.md via the md materializer (byte-precise
// splice + oracle), so the ledger row lands THROUGH the surface it
// measures.
//
// Usage: node run_dogfood_seam_ab.mjs

import { spawn } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { HarnessdClient } from "./r7_harnessd_client.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, "../../../..");
const daemonPkg = path.join(repoRoot, "pkgs/xsoulspace_agentic_host");
const resultsRel = "pkgs/xsoulspace_agentic_harness/docs/agent/results_seam_speed.md";

const log = (s) => process.stderr.write(`[ab-probe] ${s}\n`);

const client = new HarnessdClient(
  "dart",
  ["run", "bin/harnessd.dart", "--profile", "meaning", "--scripted",
   "--workspace", repoRoot, "--idle-exit-minutes", "2"],
  daemonPkg,
  repoRoot,
  () => {},
);

try {
  await client.start();

  // Warm the tree (idempotent ensure — already_built on a live tree).
  const t0 = Date.now();
  await client.prompt("[scan]");
  log(`[scan] wall ${Date.now() - t0} ms`);

  // B1 — the mechanical read program (timed, warm).
  const t1 = Date.now();
  const read = await client.prompt(
    `harness_meaning_program {"ops":[{"op":"locate","query":"seam_speed"},` +
    `{"op":"read","budget":256}]}`,
  );
  const readWall = Date.now() - t1;
  log(`mechanical read wall ${readWall} ms`);

  // Pull the locate rows out of the streamed updates (the tool-result
  // text carries the JSON) to find the file node id.
  const readText = read.text ?? "";
  const fileIdMatch = /f_[\w.]*results_seam_speed\.md/.exec(readText);
  if (!fileIdMatch) {
    console.log(JSON.stringify({ ok: false, stage: "read", readText: readText.slice(0, 800) }));
    process.exit(1);
  }
  const fileId = fileIdMatch[0];
  log(`file node id: ${fileId}`);

  // B2 — the REAL edit: insert the A/B row section after the last section
  // of results_seam_speed.md (insert_section = heading-validated splice).
  const body =
    "## 2026-09-08 — session A/B: the drifted read dialect vs the surface\n" +
    "\n" +
    "Measured during the frontier-resolver session (the same day, same\n" +
    "machine). The A side ran through the STALE pi extension (legacy\n" +
    "per-verb wrappers → the mover as a graded task); the B side through\n" +
    "the mechanical paths this session landed. n=1 per row (in-session\n" +
    "observation; the scripted B rows are repeatable via\n" +
    "`run_dogfood_seam_ab.mjs`).\n" +
    "\n" +
    "| path | route | wall | outcome |\n" +
    "| --- | --- | --- | --- |\n" +
    "| A — `harness_locate` (stale wrapper) | mover-graded task | 194,114 ms / 194,122 ms | `mover_refusal` (no read performed) |\n" +
    "| A — `harness_edit` probe (stale wrapper) | mover-graded task | 183,302 ms | zero moves (verify burned 8,999 ms) |\n" +
    "| B — `harness_meaning_program` (one tool) | mechanical read directive | < 100 ms gate (unit-metered; 2026-09-06 rows: 34–54 ms warm) | read + cursor returned |\n" +
    "| B — this very section | `harness_edit` insert_section through the md binding | mechanical (scripted probe; wall printed in the probe log) | the row landed THROUGH the surface |\n" +
    "\n" +
    "≈ 2,000× wall delta on reads; the edit path stops re-composing (and\n" +
    "refusing) what should be mechanical. Gap rows closed in\n" +
    "surface_gaps.md (2026-09-08); the extension now exposes ONE read\n" +
    "tool and the mechanical-read set is asserted against the LIVE\n" +
    "registry (`mechanical_read_registry_test.dart`).\n";

  const t2 = Date.now();
  const edit = await client.prompt(
    `harness_edit {"action":"insert_section","symbolId":"sec_${fileId}_5",` +
    `"body":${JSON.stringify(body)}}`,
  );
  const editWall = Date.now() - t2;
  log(`harness_edit wall ${editWall} ms → ${(edit.text ?? "").slice(0, 200)}`);

  console.log(
    JSON.stringify({
      ok: true,
      read_wall_ms: readWall,
      edit_wall_ms: editWall,
      file_id: fileId,
      edit_result: (edit.text ?? "").slice(0, 300),
    }),
  );
} finally {
  client.proc.kill("SIGTERM");
}
