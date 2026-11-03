# ROADMAP — the adapter/acceleration lane (mlx_native)

**This file is the live queue: what is OPEN, what is deliberately NOT
scheduled, and what is deferred to discussion.** It holds no closed
experiments. The registers it points at:

- [`VERDICTS.md`](VERDICTS.md) — the closed register: every completed or
  retired experiment, ONCE, with its verdict class and evidence pointer
  (F / C / V / O / ✓).
- [`RESULTS-HISTORY.md`](RESULTS-HISTORY.md) — the dated tabulation of every
  recorded measurement (§1–§16; the day-by-day history).
- [`LINES.md`](LINES.md) — the row-level ledger; [`MTP-GATES.md`](MTP-GATES.md)
  — the frozen gates (nothing here moves one);
  [`EXPERIMENT-PLAN.md`](EXPERIMENT-PLAN.md) — the cost model and the plan.

A closed experiment lives ONCE — as a verdict row in VERDICTS.md and a dated
measurement in RESULTS-HISTORY.md. It does not also live here; the queue
below links to them instead of restating them. When documents disagree, the
cited artifact wins.

---

## THE OPEN QUEUE

### 1. Nursery RUNG-1 (PERM-GATE-1) — open at exactly two staged levers

Attempts 4–7 ran and closed with data: the dense line's measured ceiling is
attempt 4's **0.722 agreement (argmax, 3 unsafe)**; every calibrated
operating point (label-head margin, slot-head MLP margin) degenerates to
**all-abstain (0.667 / 0 unsafe)** — representation binds, not calibration;
the readout lever closed with data on 2026-10-28. History:
[`RESULTS-HISTORY.md`](RESULTS-HISTORY.md) §14–§16; RUN-RECORDs under
`bench/nursery/experiments/` (gitignored). Ledger note: the dense-perm
trunks measure **16,006,656 params** (band bottom); "42.8M" was a misnomer
for rung1-scale MoE — annotated in §16, history not rewritten.

Still open — each lever pre-registered with its own `PREDICTION.md`,
battery-gated (the measured 0.5–0.7 %/min drain prices dense-perm-e at
~2.6 h), launch commands in the rung jsons; no recipe decisions remain
open:

- **dense-perm-e** (capacity): hidden 896, **48,655,488 params** (3.04× the
  closed 16M dense line, under the 50M band top); attempt-6 recipe verbatim
  on corpus v3. Line rule: closes if eval argmax < 0.70 AND frozen
  zero-unsafe agreement < 0.722.
- **dense-perm-f** (boundary data): corpus **v4** (v3 + a 600-row balanced
  hard near-miss slice at every measured law boundary; 3600 rows, 0
  frozen-case collisions); curriculum stage 2 from dense-perm-c, lr 5e-4,
  850 steps.

Owed regardless of the levers:

- **The live-slot half of RUNG-1 acceptance** — the live slot is now
  **BUILT** (2026-10-28): `LayaPermGateV1` in the laya product ships the
  measured all-abstain law (the gate never allows — zero-unsafe by
  construction, gate-tested against the tracked frozen 18) and appends
  every real question to an append-only escalation store the host labels
  with `recordOutcome`. What remains owed is the RECORD itself: real
  `permission_gate.v1` answer quality, computed from accumulated labeled
  outcomes once the gate runs in a host — never assumed.
- **Live escalations as data** — the collector above is that mechanism;
  `labeledCount` on the store is the acceptance metric in the making.
  (Git-LFS answer, recorded 2026-10-28: none needed — the artifacts the
  slot needs are tiny (slot harness 212 KB, already tracked; heads ~130 KB;
  adapters ~5.5 MB; corpus JSONLs a few MB — all far under git's 100 MB
  limit). The 61 MB dense-trunk checkpoints fit plain git but bloat it;
  LFS becomes worth considering only if checkpoint versioning multiplies.
  Model snapshots stay runtime-downloaded by design and never enter git.)
- **Parked finding for operator review** — the measured corpus-law hole
  (`dart test && rm -rf /` allows by prefix match; `;` chaining happens to
  fail it); excluded from all training rows; §16.

### 2. CI — live and green at its honest scope; owner decisions block the rest

- The lane gate (`.github/workflows/mlx_native_gate.yml`) is GREEN at its
  clean-clone truth (re-scoped run 40486871329, `native-compile` 30 s): the
  honest compile gate on macos-14. `cargo test` needs machine-local
  MLX/mlxc static libs (build.rs refuses loudly) — the real test gate stays
  local on AC by design; the Dart battery runs green locally (42 pass /
  1 honest skip / 0 fail).
- **Owner decision 1 — dependency pins.** PR #7's git/pub.dev pins retired
  the machine-private-override blocker (`flutter pub get` passes on a
  clone), but `test_core 0.6.21` does not compile against the pinned
  `test_api 0.7.13`, so the repo-wide test workflows fail at compile. Pin
  alignment is owner review (§13, §15).
- ~~Owner decision 2 — the coalescing default~~ **DECIDED 2026-10-28 (by
  the owner), implemented and gated:** the fused-batch coalescing window
  defaults ON (15 ms; `Duration.zero` / `--coalesce-ms=0` is the explicit
  solo escape hatch); the default-flip gate is in the wire-test file.
  Token streaming landed the same day (OpenAI-style SSE at the chat wire,
  token-exact to the completion path — `RESULTS-HISTORY.md` §17).
- One pre-existing battery red was stash-proven non-regression on
  2026-10-28 (`mlx_native_lazy_client_test`: `Isolate.resolvePackageUriSync`
  unsupported in the load path — a toolchain drift since the 10-27 green
  run); its own disposition is owed, unrelated to this session's surfaces.

### 3. Deferred — awaiting owner discussion

- **The reasoning track.** The lane has a capability track (generative
  work: Qwen3-0.6B + one shared untagged adapter, consumed as a ranker) and
  a decision track (laya + the perm head). It has NO reasoning capability,
  and every recorded attempt at the local casts is negative. Directions for
  closing that gap are investigated and recorded — deliberately without
  gates or arms — in [`REASONING-TRACK.md`](REASONING-TRACK.md). Nothing is
  scheduled; the owner discussion decides whether any direction becomes a
  pre-registered arm. (The first direction HAS left that file this way: the
  2026-11-02 intent-first discussion became Line IC, ran the same day, and
  closed **F — no signal cell**; [`VERDICTS.md`](VERDICTS.md),
  [`RESULTS-HISTORY.md`](RESULTS-HISTORY.md) §18. Its reading-3 route — a
  generation-shaped intent arm with a new oracle — is NOT scheduled.)

---

## Deliberately NOT scheduled (and why)

| item                                                | why                                                                                                            |
| --------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| Any MTP-shaped arm on this hardware                  | Line J closed on physics; new hardware requires a NEW registered arm                                            |
| More mechanism arms (tag, option list, task count)   | the attribution is measured at both ends; re-running it is not a new question                                   |
| The veto residual as a standalone cleanup            | not a gate input until ranked(adapter) makes it one (it now has)                                                |
| 4-bit dequant→merge→requant                          | no consumer; requant error ≈ the adapter delta (K-G4)                                                           |
