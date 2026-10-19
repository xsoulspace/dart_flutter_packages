# Nursery toolchain (Line I — the un-VM nursery)

Frozen infrastructure for training tiny models under
[TRAIN-GATES.md](../../TRAIN-GATES.md). Phase 1: build the rails, train
nothing. The working lane (datasets, future training scripts, run configs)
lives in `bench/nursery/` (gitignored, like every bench lane); everything
HERE is tracked and gated.

## What is here

| Path | What |
|---|---|
| `pack_at_birth.py` | trained checkpoint (safetensors + config.json) → weights-splat store (`nursery.weights-splat.v1`): content-addressed segments, offset point reads, sha256 digests, semantic role per tensor (expert/router/embed/head/norm/dense). Resumable; repack of an unchanged checkpoint is a byte-identical no-op. `--quantize-experts-bits N --quantize-experts-group G` affine-quantizes EXPERT weights at pack time via `mx.quantize` (routers stay fp32 BY LAW; sets `manifest.quantization` for the Rust runtime; refuses double-quantizing a checkpoint that already declares it, and refuses resuming a store packed with a different quantization setting). |
| `quantize_roundtrip_check.py` | the quantize-at-birth oracle: every expert weight in the store is dequantized via `mx.dequantize` and compared to the original checkpoint; pass bound = 1.05 × max&#124;scale&#124; (one quanta — calibrated on the canonical implementation's own boundary behavior; a convention bug lands many quanta off). Also enforces the fp32-router law. |
| `pack_fixture.py` | regenerates the Rust reader's parity fixture (`native/mlx_native/testdata/nursery/`): synthetic f32/f16/bf16/u32 checkpoint with an fp32 router, packed through the real pipeline; writes `expectations.json` (per-tensor sha256 + bit-exact f32 samples + generator provenance). |
| `gates/` | the four TRAIN-GATES oracles, each with a `--self-test` that must pass before the gate may run on a candidate. `run_gates.py` audits a candidate and stamps a verdict JSON with input sha256s. |
| `export_clause_dataset.py` | exports the provenance-stamped clause-kind dataset. Teacher = the canonical `segmentText` marker tables, imported (never copied) via a shim GENERATED under the teacher's workspace `.dart_tool/` — see the docstring for the final-parameters language-version gotcha that makes this necessary. |
| `slots/perm_gate_1/` | the RUNG-1 acceptance harness (PERM-GATE-1, anchored to ADR 0084) — the canonical usefulness gate before any model exists. |
| `model_def.py` | the RUNG-0 drosophila definition — the ONE contract (tensor names, carry-state linear attention, fp32 router, top-k tie rule) that `native/mlx_native/src/nursery_model.rs` mirrors. Pure-python shape helpers import no mlx, so `scale_decision.py` and the Rust loader agree with this file without mlx. |
| `rung0.json` | RUNG-0 run config: model knobs, training knobs, gate targets (GATE-1/3 still PROVISIONAL — setting them final in TRAIN-GATES.md is the launch checklist item). |
| `train_rung0.py` | Phase-2 item 5: the training loop (lm CE + label CE + router margin hinge + route smoothness) and the eval-split exporter that writes EXACTLY the gate inputs (`traces/routes.jsonl`, `traces/activations.jsonl`, `traces/predictions.jsonl`). It records, it cannot grade. |
| `power_snapshot.py` | POWER.md truth for run records: ioreg AppleSmartBattery Amperage + pmset side by side (the charge-current hole). |
| `scale_decision.py` | Phase-2 item 6: the payload-must-fit-RAM table for the whole rung ladder from shapes alone (back-room 10 GB anchor; 25 MB/token rung-3 binding). |
| `record_run.py` | Phase-2 item 7: stamps RUN-RECORD.md + record.json — code rev, dataset digest, power truth, gate verdicts quoted (never re-graded), predicted-vs-observed (ADR 0032). |

## Run them

```sh
# pack a checkpoint + gate payload at birth
~/.venvs/mlx-ref/bin/python tool/nursery/pack_at_birth.py \
    --checkpoint <ckpt-dir> --store <store-dir>
python3 tool/nursery/gates/gate4_payload.py --manifest <store>/manifest.json \
    --back-room-gb 10 --bytes-per-token-mb 25

# full audit of a candidate (targets from the rung config, never defaults)
python3 tool/nursery/gates/run_gates.py --config rung.json \
    --store <store-dir> [--routes r.jsonl] [--activations a.jsonl] \
    [--predictions p.jsonl --labels l.jsonl] --out gates.json

# training data
~/.venvs/mlx-ref/bin/python tool/nursery/export_clause_dataset.py \
    --out bench/nursery/data/clause_dataset.jsonl

# Rust-side store verification (the runtime load path; also a cargo test)
cd native/mlx_native && cargo test --offline --test nursery_store_parity
```

## Status (2026-10-18, low power)

Phase-2 items 5–7 are CODED, NOT RUN: `model_def.py`, `rung0.json`,
`train_rung0.py`, `scale_decision.py`, `record_run.py` were written under
the operator's no-test instruction (8 W trickle; every measurement law in
POWER.md argues against training now) and have never executed. The Rust
runtime (`native/mlx_native/src/nursery_model.rs` + the
`mlx_native_nursery_model_*` ABI) is likewise coded-not-compiled. First
live session on real power owes: `cargo build` of the crate, a
route-agreement smoke of the Rust forward vs the Python forward on the
fixture store, then the TRAIN-GATES.md launch checklist before the first
RUNG-0 training run.

## Laws encoded here (do not bypass)

- The Rust reader hard-errors on any segment digest mismatch; its fixture
  test walks every pinned tensor digest, so a skipped check cannot hide.
- Routers are fp32 (PORTING-MOE.md); GATE-4 fails a store whose router
  role tensors are not `float32`.
- Gate targets come from the rung config / TRAIN-GATES.md — the gates
  take no defaults, so a missing target is an error, not a silent pass.
- The clause teacher is imported at its canonical path and stamped by
  sha256 into every record and the dataset manifest.
- Correctness gates are never power-conditioned; any timed number stays
  under POWER.md (and today means recording ioreg Amperage — see the
  charge-current hole).
