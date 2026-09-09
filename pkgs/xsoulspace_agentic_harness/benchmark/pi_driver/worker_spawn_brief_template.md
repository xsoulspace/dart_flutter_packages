# Worker spawn brief — TEMPLATE

> The standard brief skeleton for a spawned pi agent in this repo (rung 1:
> the worker is an extension client of the per-workspace harnessd daemon —
> see [multi_actor_workers.md](../../../docs/agent/multi_actor_workers.md)).
> Fill every `{{placeholder}}`; delete nothing. Discipline modeled on the
> 2026-09-08 8-lane parallel wave (lane 8's own brief is this template
> filled in).

---

## Task: {{lane-name}}

You are lane {{N}} of an {{K}}-lane parallel wave in the repo
`{{REPO_ROOT}}` ({{STACK}} monorepo, git branch `{{BRANCH}}`; the tree has
uncommitted work — **NEVER stash/commit/reset/checkout, edit in place**).

### READ FIRST (in order, before any edit)

1. `{{REPO_ROOT}}/AGENTS.md` — repo charter + harness surface routing law.
2. {{read-first-file-1}}
3. {{read-first-file-2}}
4. {{your-template-files}}
5. {{north-star-or-charter-doc}}

### Operational setup (rung 1 — non-negotiable)

- Load the harnessd extension: `pi -e {{EXTENSION_PATH}}` with
  `PI_HARNESSD=1`, cwd = the workspace. Pi's built-in file tools are
  disabled for the session — the daemon surface is the ONLY file surface.
- The extension attaches to the live per-workspace daemon (connect-if-live
  over `<workspace>/.dart_tool/harnessd/harnessd.sock`); never spawn a
  second daemon for the same workspace (single-instance REFUSES it — that
  refusal is the law working, not a bug to work around).
- Work through the daemon verbs: `harness_meaning_program` (reads),
  `harness_edit` (dart/md/yaml/json edits), `harness_fs_write` (review-gated,
  non-Dart only), `harness_run` (allowlisted commands), `harness_verify`.
- Consent is inherited from the workspace plan (`.harnessd/consent.json`);
  prompts outside the plan are answered by the human — do not retry a
  denied mutation.

### OWN (files you may edit/create — nothing else)

- {{own-file-1}}
- {{own-file-2}}

### DO NOT TOUCH

- Everything outside OWN — other lanes edit other files CONCURRENTLY.
  Re-read a file immediately before each edit; never batch blind rewrites
  over shared files.
- Git state: no stash/commit/reset/checkout; no branch operations.
- The daemon: no kill/restart/snapshot-restore games. If the daemon died
  (idle-exit), let the extension recover; if it cannot, report and stop.

### Scope discipline

- {{SCOPED_VALIDATION}} — e.g. "scoped validation only: the driver's
  `--scripted` mode; NEVER the full monorepo suite."
- Never run full analyze/test sweeps over the monorepo; other lanes are
  mid-flight and a root convention sweep measures their half-landed work.

### The honest-escape rule

When the harness surface genuinely does not cover a needed change (new-file
bootstrap, structural Dart shapes, cross-repo, mapless file classes), you
MAY take the raw path — exactly once per gap, honestly:

1. Name what the raw tool did and why the surface could not cover it.
2. Append ONE row to `{{SURFACE_GAPS_DOC}}`
   (`| date | task | what bash did | why the surface didn't cover it | gap (verb/spec to build) |`).
3. Never re-implement a surface verb in bash (drift rejection list in
   `pipeline_coding.md`). A silent escape starves the tiny-model path —
   it is the one dishonesty this repo cannot absorb.

### Final report format (end your lane with exactly this)

- **Files created/edited** — path + one-line purpose each.
- **Validation result** — the exact command(s) run and their outcome
  (e.g. `node run_r7_multi_worker_gate.mjs --scripted` → PASS/FAIL +
  one-line evidence). No validation claim without the command.
- **Counts** — files, LOC, tests, rows appended (whatever the task's
  unit is).
- **Integration hooks** — what other lanes/the orchestrator must wire to
  consume this lane's output (paths, env vars, flags).
- **Non-claims** — what you did NOT prove or build. Every published
  number states backend, decision path, tokens source, tool surface, and n
  (standing rule). Failures are data: report named classes, never drop.
- **Escapes** — the surface_gaps rows you appended (or "none").

Work until done means: OWN complete, scoped validation green (or its
failure class named and reported), report filed. It does NOT mean: expand
scope, touch other lanes' files, or claim readiness the validation
command did not print.
