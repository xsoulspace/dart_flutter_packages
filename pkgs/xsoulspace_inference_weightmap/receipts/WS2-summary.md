# WS-2 Cross-Engine Agreement — LIVE RUN SUMMARY

Date: 2026-11-06 (UTC) · Phase B (PROGRAM.md) · Cast: `mlx-community/Qwen3-0.6B-bf16`
Verdict: **FAIL** — rust candidate does NOT reproduce the python_mlxlm reference
token-for-token on 39/66 mirror×cell pairs; per-mirror certify: base MISMATCH,
plant_1 MISMATCH, plant_1_removal AGREE (rate-level only). Findings recorded
per cell; NOT retried into agreement (house law).

Python-first law honored: `python_mlxlm` is the REFERENCE, `rust` the
CANDIDATE; every disagreement is attributed to the candidate
(lib/src/cross_engine.dart).

## 1. Mirrors (rebuilt with A3's own builder scripts, unchanged)

Builders: `tool/runs/make_mirror.py` + `tool/eval/apply_delta.py` (frozen A4
digests; run unmodified). Sidecars: A3 arm-002 (= a3-plant-1) blind sidecars
(spec digests `83d4905c…`/`b4614a5b…` verified against
`receipts/A3/truth/arms.json`). Removal sidecars rebuilt from arm-002
`repair_spec.json` (direction digests `4ce958c0…`/`3510af6f…` verified against
`repair_receipt.json` before use).

| mirror | shard sha256 | gate |
|---|---|---|
| base (hub snapshot `42096995…`) | `bfe05e58f5acdecd…` | 9/9 file digests == arm-002 `base_file_digests` OK |
| plant_1 | `22e52d07164ca45f…` | == recorded `mirror_shard_sha256` OK; L15/L19 f32 tensor digests `31342239…`/`dbaee754…` OK; elements_differing 65247/65353 OK; unedited 308/308 OK |
| plant_1_removal | `fadd55fa38e846d8…` | L15/L19 f32 digests == recorded post-repair `7146eb82…`/`b5f47a9d…` OK; scale −4.8 OK; unedited 308/308 OK; base==plant_1 shard OK |

**REBUILD_VERIFIED: 21/21 digest checks OK — no REPLAY_DIGEST_DRIFT.**
Rows: `WS2-cross-engine.jsonl` kind=rebuild (21 rows).

## 2. Prompts / surface (frozen)

- Cells: `tool/runs/cells_frozen_A3.json` sha256
  `8406130623b6e85922eac6cbd92b73dd2282e6fc19538bb3c199f647f518d760`
  (== A4 freeze row in VERDICTS.md). G2 (12 cells, cap 256) + G0 (10 cells,
  cap 64) = 22 cells.
- Template: `apply_chat_template([{role:user, content:prompt+' /no_think'}],
  add_generation_prompt=True, tokenize=False)` rendered ONCE (base tokenizer,
  files identical across mirrors) → `$TMPDIR/wm-ws2/prompts.json` sha256
  `9b8710a71333240020105356429a914071fe622190bd49a4f90be03ac4c95de1`;
  both engines consumed this one rendering.
- Sampler contract (both engines, EOS stop OFF, exactly cap steps):
  python `next = argmax(logits − logsumexp(logits, keepdims))`
  (wm_qwen35_digest.py contract == mlx_lm `generate_step`'s own greedy path,
  verified in mlx_lm 0.32.2 source); rust `Qwen3::generate_greedy(stop=None)`
  (raw-logits GPU argmax; qwen.rs). Prefill ≤2048 chunks over prompt[:-1].
- eos set `{151645}`; content_tokens = first EOS index else cap;
  cap_hit = content_tokens >= cap (A3 semantics under EOS-off streams).

## 3. Engines / scripts (owned this run)

| role | file | sha256 |
|---|---|---|
| python reference | `tool/runs/ws2_py_generate.py` | `3be597969c239f19…` (mlx 0.32.4, mlx-lm 0.32.2, transformers 5.22.1, py 3.12) |
| rust candidate | `pkgs/xsoulspace_inference_mlx_native/native/mlx_native/src/bin/ws2_rust_generate.rs` | `18b421cb7b8526a7…` (crate 0.1.0, release; `Qwen3::load` + `generate_greedy` + `ByteLevelBpe` — the same engine API the FFI/Dart client drives) |
| certifier driver | `tool/runs/ws2_certify_dart.dart` | `b070846c61ffbffc…` (frozen `cross_engine.dart` certify + frozen `scorers.dart` tokenLimitRate; Tolerance abs:0 rel:0; dry-tested on synthetic PASS and FAIL fixtures before the live run) |

Rust bin chosen over the Dart-client path (task-sanctioned alternative):
weightmap's pubspec contract is "imports inference_core only" — adding an
mlx_native dependency would break package isolation. Glue is minimal (one new
bin, zero engine-file changes).

Raw generation jsonl (scratch, `$TMPDIR/wm-ws2/gen/`, digests durable here):
py_base `278934f874cf6bee…` py_plant_1 `0ce92a18a94ccfea…`
py_plant_1_removal `4e2b256707360b26…` rust_base `1be847ec65fbd558…`
rust_plant_1 `1cae61eb39f0f665…` rust_plant_1_removal `e4ae1b607be117b0…`.

## 4. Device lock + power (protocol v3 shape, 60s backoff per task)

Serial −j 1; one lock hold per batch; rmdir + 3s courtesy after each.
Lock waits: rebuild 420s, py_base 720s, all other batches 0s (concurrent
actor: another session's v12/A2-capcurve batches held the lock 04:08–04:45
local). Power: **AC** for every batch (`pmset`); `cpu_limit` empty (no
throttle confession); `Amperage` recorded as-is per batch including 0 mA and
one unsigned-wrapped negative (−32 mA) — POWER.md charge-current hole: "AC"
here is source-flag AC, possibly weak-brick; all wall_ms/tok_s rows are
NON-CLAIMS regardless (contention + power law). Rows: kind=lock (7 rows).

## 5. Results

Per-mirror certify (frozen cross_engine.dart, bundles 24 cells: 22 cap-hit
indicators + frozen tokenLimitRate G2/G0; digests = token-id sequence shas):

| mirror | loop_rate_G2 py → rust | loop_rate_G0 py → rust | certify | ids equal/22 |
|---|---|---|---|---|
| base | 0.4167 → 0.3333 | 0.0 → 0.0 | **MISMATCH** | 11 |
| plant_1 | 0.6667 → 0.5833 | 0.1 → 0.1 | **MISMATCH** | 4 |
| plant_1_removal | 0.3333 → 0.3333 | 0.0 → 0.0 | **AGREE** | 12 |

Token-id identity (tolerance 0): **27/66 equal, 39 TOKEN_ID_MISMATCH** (all
named per cell in `WS2-cross-engine.jsonl` kind=finding with first-divergence
index). Prompt-token ids equal 66/66 (tokenizer surface agrees); model shard
sha equal per mirror×engine pair (inputs identical).

Mismatched cells:
- base (11): g0-ws g0-pal g0-s2c g0-title g0-vowels g0-clamp g2-u-song
  g2-u-robot g2-u-invented g2-u-clock g2-u-downforever
- plant_1 (18): g0-c2s g0-ws g0-rle g0-pal g0-kebab-2 g0-s2c g0-title
  g0-acr g0-clamp g2-u-song g2-u-robot g2-u-sorry g2-u-echoes g2-b-even80
  g2-b-mult3 g2-b-count60 g2-b-count45 g2-u-clock
- plant_1_removal (10): g0-ws g0-title g2-u-song g2-u-robot g2-u-echoes
  g2-u-invented g2-b-count60 g2-b-count45 g2-u-clock g2-u-downforever

Divergence anatomy: 22/39 diverge at/after BOTH content boundaries (post-EOS
padding region — content-irrelevant but still id-mismatch under tolerance 0);
17/39 diverge inside content. Behavior flips (cap_hit py=1, rust=0): **base
g2-u-robot** (content 256 vs 191) and **plant_1 g2-u-echoes** (content 256 vs
161) — these two cells move loop_rate_G2 and drive the two MISMATCH verdicts.

## 6. Attribution and mechanism (interpretation, labeled)

- The python reference reproduces A3's recorded python-side rates EXACTLY on
  all three mirrors (base 0.4167 = A3 base; plant_1 M 0.6667 and removal R
  0.3333 = A3 arm-002 blind-scored `loop_rate_M`/`loop_rate_R`) on
  digest-verified identical weights. The reference leg is therefore
  cross-validated; per the Python-first law the disagreements attribute to
  the rust candidate.
- Observed pattern — long identical greedy prefixes (first divergence at
  steps 4–232, median ≈ 56; 27/66 runs fully identical) — is the signature
  of rare near-tie argmax flips, not systematic drift. Candidate mechanisms
  (not separated in this run): (a) bf16 flattening — rust argmaxes RAW bf16
  logits while python argmaxes `logits − logsumexp(logits)`; the subtraction
  can round two distinct bf16 logits to equal and flip the first-index
  choice; (b) kernel-level logits drift — rust mlx-c fused kernels vs python
  mlx_lm module graph can emit 1-ulp-different bf16 logits rows (recorded
  WS-2 lesson, VERDICTS.md 2026-11-06 "bitwise-findings": parity is
  kernel-verbatim-dependent). Open diagnostic (NOT run here): capture raw
  logits rows at divergence steps in both engines and classify (a) vs (b).

## 7. Non-claims

- LOGITS_DIGEST_NOT_CAPTURED: raw-logits digests are optional identity
  evidence; token-id sequence digests key these bundles instead.
- wall_ms / tok_s rows are non-claims (contention + POWER.md law 2).
- No retry-into-agreement was performed; 6 generation batches ran exactly
  once each (3 mirrors × 2 engines).
- AGREE on plant_1_removal certifies RATES only — 10 of its 22 cell pairs
  still fail token identity; the overall WS-2 verdict is FAIL.
- No edit claim of any kind follows from this run (oracle law; Phase A
  authorizes no production-cast edit claim).

Receipt: `receipts/WS2-cross-engine.jsonl` (kinds: rebuild ×21, lock ×7,
batch_meta ×6, cell ×66, finding ×39, certify ×3, summary ×1).
