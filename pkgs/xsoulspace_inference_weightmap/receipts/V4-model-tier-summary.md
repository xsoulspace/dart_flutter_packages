# V-4 MODEL TIER — certification evidence under invariance + case variants

PREREG-C §V-4 model tier + addendum 2026-11-05. MEASUREMENT, not a pass bar:
suspects are findings that REOPEN an edit’s certification (recorded, never auto-revoked).
CPU-only rescore of digest-verified archived A3 outputs — NO device generation, fallback NOT run.

- Pre-run registration: `receipts/V4-model-tier.jsonl` seq 0, digest `78b31671cfd5cbe79ef93bf0491ac60aaefa4dac4c4189c00b30e89adb1823ce`
- Certified set (join-table): plants 1,3,4,5,6,7 = arm-002/009/005/015/011/012
- Evidence: `receipts/V4-model-tier-evidence/<label>/battery_{M,R}.jsonl` — copies of
  `$TMPDIR/wm-a3/blind/<label>/…`, triple-verified (file == manifest == join-table digest)
- Frozen inputs verified pre-run: scorers.dart `dfe42d43…`, probes.dart `7236f69e…`,
  cells_frozen_A3.json `84061306…`, sampler_config_frozen.json `cbf0132d…` (A4 keys, match)
- Reproduction gate: naive recomputation == archived join-table aggregates on all 6 edits
  (loop_rate_M/R, task_pass_M/R, full flips lists) — MATCH

## Applicability table (PRE-RUN, from seq 0)

| cells | scorer | frozen four | case variants | reason |
|---|---|---|---|---|
| g0-c2s, g0-ws, g0-rle, g0-kebab-2, g0-s2c, g0-title, g0-acr | string_first_line | APPLIES | NOT_APPLICABLE | golds case-spec’d by their own checker spec (case-SENSITIVE equality); case is task content, not format |
| g0-pal | label_first_line | APPLIES | APPLIES | closed boolean label, case-insensitive gold |
| g0-vowels, g0-clamp | numeric_final | APPLIES | NOT_APPLICABLE | numeric cells keep the frozen four (addendum) |
| g1-perm-01..12 | label_first_line | APPLIES | APPLIES | closed-set labels (allow_once/abstain), case-insensitive golds |
| g2-* (12) | token_limit_cap | IDENTITY_BY_CONSTRUCTION | NOT_APPLICABLE | score consumes exact generated-token counts, not text |

Case-variant application (pre-registered `CASE_VARIANT_APPLICATION`): PRIMARY =
variants applied to the answer surface after the frozen spec’s own think_prefix_strip
(same-answer-different-case semantics, matching the wrapper-free scorer-tier fixtures);
SECONDARY = variants on the raw output, recorded per cell. Raw uppercase_all rewrites
the structural <think> wrapper, defeating the case-sensitive frozen strip and
killing first-line cells in BOTH stages uniformly — non-discriminating, hence secondary.

## Per-edit verdicts

| edit | arm | loop M→R | task naive M→R | task inv4 M→R | task inv-all M→R | certified (invariant) | suspect cells | VERDICT |
|---|---|---|---|---|---|---|---|---|
| a3-plant-1 | arm-002 | 0.6666666666666666 -> 0.3333333333333333 | 1 -> 10 | 1 -> 10 | 1 -> 10 | true | 0 | **SURVIVES** |
| a3-plant-3 | arm-009 | 1.0 -> 0.5 | 1 -> 9 | 1 -> 9 | 1 -> 9 | true | 0 | **SURVIVES** |
| a3-plant-4 | arm-005 | 0.4166666666666667 -> 0.3333333333333333 | 8 -> 10 | 8 -> 10 | 8 -> 10 | true | 0 | **SURVIVES** |
| a3-plant-5 | arm-015 | 0.6666666666666666 -> 0.4166666666666667 | 4 -> 10 | 4 -> 10 | 4 -> 10 | true | 0 | **SURVIVES** |
| a3-plant-6 | arm-011 | 0.5 -> 0.3333333333333333 | 9 -> 10 | 9 -> 10 | 9 -> 10 | true | 0 | **SURVIVES** |
| a3-plant-7 | arm-012 | 0.5 -> 0.3333333333333333 | 9 -> 10 | 9 -> 10 | 9 -> 10 | true | 0 | **SURVIVES** |

Result: 6 of 6 certified edits SURVIVE the invariance
wrapper + applicable case variants; 0 FORMAT_ARTIFACT_SUSPECT.

Secondary raw-case aggregates (task passes under the raw-application min, observation
only — NOT verdict-driving). Mechanism: raw uppercase_all defeats the case-sensitive
think_prefix_strip, so it kills EVERY naive pass on first-line-scored cells in BOTH
stages; numeric-cell passes can survive it (digits are case-invariant). Per-stage
kill counts below; the jsonl rows are authoritative.
- a3-plant-1 (arm-002): raw-min task 1 -> 3; raw uppercase killed naive passes M/R = 1/10
- a3-plant-3 (arm-009): raw-min task 1 -> 2; raw uppercase killed naive passes M/R = 0/9
- a3-plant-4 (arm-005): raw-min task 1 -> 3; raw uppercase killed naive passes M/R = 8/10
- a3-plant-5 (arm-015): raw-min task 2 -> 3; raw uppercase killed naive passes M/R = 4/10
- a3-plant-6 (arm-011): raw-min task 3 -> 3; raw uppercase killed naive passes M/R = 8/10
- a3-plant-7 (arm-012): raw-min task 3 -> 3; raw uppercase killed naive passes M/R = 9/10

## NAMED issues

- EVIDENCE_SOURCE_TMPDIR_DIGEST_VERIFIED (originals sweepable; copies durable)
- CASE_VARIANT_APPLICATION_NOTE (cell-typed primary after frozen think_prefix_strip; raw application recorded secondary)
- RAW_UPPERCASE_UNIFORM_KILL (secondary observation; non-discriminating across M/R)
- FALLBACK_NOT_RUN (per-arm raw outputs archived and digest-verified; no device run)
- V1_HALT_CONTEXT (measurement of archived evidence under the recorded NULL_LEAK halt; no revocation authority)

Rows: `receipts/V4-model-tier.jsonl` (seq 0 prereg + 204 v4-cell + 6 v4-edit + 1 v4-summary).
Runner: `tool/runs/v4_model_tier.dart` (new script; frozen oracles untouched).
