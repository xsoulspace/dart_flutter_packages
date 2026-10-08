# 0054 — The composition API: declared forward plans, binding tables, and the L5 optimization ladder

Date: 2026-10-08
Status: Accepted (implementation gated by the ladder below; observed numbers are
appended per rung, ADR 0032 protocol)

## Context

ADR 0051 landed L0–L4: the Rust/mlx-c engine serves laya decisions behind the
five `laya_native_*` symbols at 63/63 golden parity, and the evidence ladder
holds the latency reality — ~90 ms compute-bound decisions at B=1..20, text-lane
TTFT@4k retired as mis-calibrated (60–300 tok/s prefill on M1), decode
26.6–66 tok/s power-state-dependent, harness-shaped 2k–8k-prompt text workloads
routed mesh-peer/remote on this hardware.

L5's ambition (owner, 2026-10-08): sub-10 ms laya decisions via a quantized or
distilled encoder, the Qwen decode lane inside the same crate, custom Metal
kernels where they actually pay, and UI coexistence on one GPU.

What blocks that today is the shape of the forward pass: `model.rs` is a
hand-written imperative op chain (~900 submitted GPU ops per decision across 28
encoder layers + decision head). Concretely:

1. **Fusion, quantization, and kernel swaps are edits to proven code**, not new
   rows in a table. Every optimization rung would otherwise fork or rewrite the
   one function the golden gate protects.
2. **There is no reviewable artifact of what the GPU runs.** The op chain lives
   only in Rust source; nothing serializes, diffs, or reviews it.
3. **µbenches are hand-written** (`op_profiles` test enumerates shapes by hand)
   instead of derived from the same structure the forward uses.
4. **Chip families are unaddressable.** M1/M2/M3/M4 differ in bandwidth, tile
   shapes, and scheduler behavior; a tuned kernel is tuned *for* a family, and
   today's code has no place to record that scoping.

oka's composition law (declared units, binding tables, artifacts riding
content-addressed keys) is the proven pattern in this fleet for exactly this
shape of problem.

## Decision

### 1. Forward passes are declared plan trees

The forward pass becomes a **plan**: a DAG of typed op nodes, each with a
contract (input/output shapes and dtypes), composed by builder functions into
layers and models. Execution walks the tree and submits the same op sequence in
the same dtype chains as today — the golden gate (63/63 argmax, prob error
≤ 0.005, `tool/test_fresh.sh`) verifies the walk is numerics-identical.

The plan serializes to JSON (`LAYA_PLAN_DUMP=<dir>`): reviewable, diffable,
the review artifact for every rung's structural claim. Nodes carry a group tag
(`enc.layer07`, `head.1`, `scorer`, `act`) so profiles and plans read like the
model.

### 2. Every node dispatches through a binding table

Each node resolves its implementation through a binding table keyed
**(op × chip family × shape class × dtype)**:

- **mlx-c is the first binding** — today's wrappers, unchanged numerics.
- **Quantized variants (R3) and custom MSL kernels (R4) land as new rows.** The
  table, not the forward code, is what changes per rung.
- **A binding that fails its gate is not installed**; the table keeps mlx-c for
  that key. Fallback is a table property, not a code path.
- **Kernel artifacts ride binding keys** (oka's frag-key pattern): plan slot +
  chip family + shape class + dtype + kernel source digest. The build hook's
  colocated-metallib delivery (ADR 0051) carries them the same way it carries
  `mlx.metallib`.

Shape classes are declared predicates over a node's contract — at minimum
`skinny-gemm (M ≤ 128)`, `batched-prefill`, `attention`, `elementwise`,
`generic` — because that is the granularity kernels are actually tuned at.

### 3. Chip families are declarations

`M1`, `M2`, `M3`, `M4` exist as key dimensions from day one. **Only rows
measured on this M1/16GiB may carry claims.** Other families' rows either fall
back to mlx-c or stay unmeasured declarations — never performance statements.

### 4. External programs are plan nodes

The python reference runtime, laya-serve, and napbench appear in the plan as
external declaration nodes (not GPU-executed), so the plan is the whole
reviewable story of a decision path — native ops and the programs that
produce/verify its oracles.

### 5. The optimization ladder

Each rung: implement → golden gate → bench → evidence appended here.

| Rung | Change | Gate | Target |
|---|---|---|---|
| R0 | Baseline: per-op profile **derived from the binding table** (each plan slot auto-derives a µbench) + laya p50/p99 sweep B=1..20; napbench text-lane numbers cited from ADR 0051 L3 (recorded 2026-10-08, same machine, same lane) | forward unchanged (63/63) | the numbers the later rungs are judged against |
| R1 | Fusion without kernels: `mlx.compile` over the plan (per-shape traced closures) | `tool/test_fresh.sh` 63/63 with compile enabled | ≥50% fewer submitted GPU ops; latency recorded B=1..20 |
| R2 | Qwen3 dense migration in the same crate: fp16 then q4, KV cache, GQA + RoPE + RMSNorm, sampler, tokenizer; in-process client behind the existing serve wire | greedy token-for-token parity vs mlx-lm; then decode ≥ 45 tok/s p50 (1.2B q4 class, per the ADR 0051 table) | TTFT recorded at 2k/4k; **the ≤300 ms @4k row stays retired** (ADR 0051 L3: mis-calibrated against M1 prefill throughput) |
| R3 | Quantization: laya q8 behind a **calibration gate** (63/63 argmax, choice-prob and score/noul drift ≤ 0.02 — fixture regeneration only with a provenance note); q4 fused dequant-GEMV for decode | calibration gate green on golden cases | weights-stream floor: fp16 ~11–12 ms → q8 ~6 ms → q4 ~3 ms on M1 |
| R4 | Custom MSL kernels via the binding table: weight-stationary skinny GEMM (M ≤ 128), fused RMSNorm + epilogues, fused dequant-GEMV. Compiled at build (`xcrun metal` → colocated metallib; the hook already collocates) | per kernel: golden parity **and** ≥ 1.3× µbench vs the binding it replaces **on its tuned family** — else the table keeps mlx-c | kernels pay in latency/bandwidth-bound regimes (solo decisions, decode), not batched prefill |
| R5 | UI coexistence: chunked prefill | < 10% dropped frames during 4k prefill (manual/Instruments, noted as such) | laya + generation + Flutter on one GPU |

## Hard laws (carried from ADR 0051)

- Every rung keeps `tool/test_fresh.sh` green. **Never weaken an oracle**;
  fixture regeneration only with provenance notes.
- Known floors (headroom math): weights stream ~11–12 ms minimum on M1 at fp16
  (q8 ~6 ms, q4 ~3 ms); batched GEMMs already run ~77% of peak.
- No autodiff, no training, no continuous batching, no GGUF.
- Unmeasured numbers are non-claims. A gate that fails twice without new
  evidence stops, records the failure + owner here, and falls back a rung.

## Consequences

- The forward's structure becomes data: plans are diffable artifacts, rung
  claims point at them, and reviews read JSON instead of Rust.
- Optimization churn (compile toggles, new bindings, quantized weights) stops
  touching the golden-gated forward walk; it adds table rows.
- The Qwen decode lane (R2) lands in the same crate and dispatches through the
  same table — one native artifact serves laya today and the LLM lane (ADR 0051
  decision 1's long-term payoff).
- Per-op µbenches are derived from plan slots, so profile coverage tracks the
  plan automatically instead of rotting as a hand-written list.

## Non-claims

- No M2/M3/M4 performance statements until hardware runs them.
- R2 keeps the existing text-lane numbers scoped to the current mlx lane; the
  migrated lane's numbers are its own evidence, recorded when measured.
- R4 kernels are not scheduled before R3 lands; R5 rides whatever prefill
  exists then.
- No claim that compile (R1) preserves numerics in general — only that the
  golden gate passed with it enabled (and the gate failure, if it comes, is
  evidence, not a bypass).

## Evidence ladder

Observed (ADR 0032 protocol — appended as rungs land):

- **Composition API (2026-10-08, M1/16GiB, mlx 0.32.2):** the laya forward is
  now a declared plan (`plan.rs`, `bindings.rs`, `model.rs::build_plan`) —
  2,238 executable nodes per forward at any B, 210-array execution context,
  binding table keyed (op × chip × shape class × dtype) with the mlx-c
  baseline. **Bit-exact**: golden 63/63, max prob error **0.0** (the fixture's
  oracle), via `tool/test_fresh.sh`. A dump-stage bisection against the
  pre-rewrite engine (117 shared stages bit-identical, divergence localized to
  head layer 1's in_proj) uncovered a load-bearing numerics fact now encoded
  in the composer: **the reference runtime's relu is `max(x, f32 scalar)`,
  which mlx promotes f16 → f32 — the decision-head tail (head layers' FF,
  scorer, everything downstream of head layer 0) runs in float32 in the
  recorded fixture.** The builder therefore tracks per-node dtypes
  (`Op::output_dtype`, `plan::promote`) and layer_norm/gelu cast back to the
  *input's promoted dtype* — hardcoding fp16 drifts the golden to 4e-4 (still
  inside the 0.005 gate, but not the oracle; fixed to 0.0). Plans serialize to
  JSON (`LAYA_PLAN_DUMP`); external programs (laya-mlx reference runtime,
  laya-serve, napbench) are declared plan nodes.
- **R0 (2026-10-08):** the baseline TOOLS are landed and one-command
  runnable — `cargo test --release r0_forward_sweep -- --ignored --nocapture`
  (p50/p99 over B=1,2,3,5,8,12,16,20 in the fw13 shape) and
  `r0_plan_derived_microbench` (2025 executable plan slots each µbenched from
  its recorded contract; GEMM-dominated as ADR 0051 recorded). The napbench
  half of R0 is ADR 0051's L3 text-lane evidence (recorded 2026-10-08, same
  machine and lane; TTFT@4k row retired there). **This session's sweep run
  happened on battery (49%, discharging) — recorded as throttled, NOT a
  baseline** (the ADR 0051 law: battery throttles sustained GPU 4–10x;
  B=2..20 numbers sagged monotonically within the run). The AC re-run of the
  two commands is the pending R0 evidence step (owner: next session on AC).
- **R1 (2026-10-08):** `LAYA_COMPILE=1` routes the plan through
  `mlx.compile` (closure-with-payload over the plan walk; per-shape
  specialization, fused replay). **Gate PASSED: golden 63/63, max prob error
  1.5e-8** (fusion-level f32 rounding; gate is 0.005) — `tool/test_fresh.sh`
  now runs both legs. Interleaved same-process A/B (`r1_compile_ab_probe`,
  drift-controlled): **compiled 63.9 ms vs eager 77.1 ms p50 at B=1 =
  1.21×**, on battery — an indicative relative signal; the AC re-run with the
  R0 sweep is the latency-evidence step. The 2,238-node eager graph replays
  as one fused compiled graph per shape; exact kernel counts to be recorded
  with the AC run.
