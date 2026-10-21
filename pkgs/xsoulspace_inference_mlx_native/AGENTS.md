# xsoulspace_inference_mlx_native — agent notes

The MLX-native engine host: one Rust cdylib (`native/mlx_native`),
one composition API, one binding table, and the model drivers that share
it (laya decision op-chain, Qwen3, LFM2/LFM2.5 incl. the 2.6B variant).
Knows no product — products depend on this package ([ADR 0057](../../docs/decisions/0057_engine_host_refactor_and_bench_architecture.md),
[ADR 0058](../../docs/decisions/0058_native_engines_unified_inference_interface.md)).

## Gates

Dart build hooks hang under the agent sandbox — run dart/cargo with the
sandbox disabled.

```bash
just analyze-one xsoulspace_inference_mlx_native
just test-one xsoulspace_inference_mlx_native          # dart suite (loads the dylib)
(cd native/mlx_native && cargo test --release)          # rust parity battery
tool/test_fresh.sh                                      # golden cycle: 63/63 @ 0.0 / 1.5e-8
```

The `l0_ops_run_and_are_dispatch_cheap` gate flakes under thermal load —
re-run standalone before calling it a failure.

[`MTP-GATES.md`](MTP-GATES.md) holds the frozen gates for the MTP lane
(J-G1..J-G4, plus the J' and K' amendments) and the swappable-adapter lane
(K-G1..K-G4), with the pre-registered failure readings. It is TRACKED on
purpose: `bench/` is gitignored in this package, so a gate written under
`bench/` would not bind a later run.

[`LINES.md`](LINES.md) is the lane's TRACKED verdict ledger — rows, verdicts,
evidence paths, and the non-claims. `bench/` is gitignored, so the results
themselves live there and are NOT versioned; the ledger is what binds them,
and a clone must be able to see that a line is closed and why.
[`EXPERIMENT-PLAN.md`](EXPERIMENT-PLAN.md) is what is next and what it costs
(it changes no gate). [`PYTHON-BOUNDARY.md`](PYTHON-BOUNDARY.md) is the
durable answer to "which Python may move to Rust, to accelerate model
experiments" — with the measured facts, the port/no-port rule, and the
non-examples. Read it before proposing a port; it names the ones that were
already priced and rejected.

## The experiment lane's surfaces

The model-experiment lane (Qwen3-0.6B-4bit + LoRA on MLX) has four kinds of
surface. **Status is stated, because a "capability" list that names files that
do not exist is a lie a future agent will trust.**

| surface                                                               | what it is                                                                                                                     | status                                                                                                                                                                                                |
| --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `native/mlx_native/src/qwen_mtp.rs` + `src/bin/qwen_mtp_bench.rs`     | the MTP draft head and its interleaved A/B                                                                                     | in the tree; the line is **CLOSED on physics** (Row J)                                                                                                                                                |
| `native/mlx_native/src/qwen_marginal_cost.rs`                         | the forced-eval body-forward cost probe that decided Row J                                                                     | in the tree                                                                                                                                                                                           |
| `native/mlx_native/src/qwen_batch.rs` + `src/bin/qwen_batch_bench.rs` | the **batched decode** path and its bench (gate **L-G4**)                                                                      | in the tree; the gate is **frozen and unrun**. The path ships a **lockstep control**, not a fused batch: `qwen.rs` hardcodes the batch dim to 1, and the bench says so and names the four-part change |
| `native/mlx_native/src/qwen_rank.rs` + `src/bin/qwen_rank_bench.rs`   | the **ranking** path — argmax over the legal labels' log-probabilities, length-normalized (gate **L-G6**)                      | in the tree; the gate is **frozen and unrun**. Defaults: bare-label boundary, **mean** normalization, both reported                                                                                   |
| `tool/nursery/scoring.py`                                             | the **single-definition** module: the strict/legacy extractors, the matched trivial baseline, coverage, the exact McNemar test | in the tree; imported by `adapter_conditioning.py` (the run) and by `fast_score.py` (the replay)                                                                                                      |
| `tool/nursery/adapter_conditioning.py`                                | the arm driver — trains, evaluates, caches per-item completions                                                                | in the tree; arms are selected with `--only-arms`                                                                                                                                                     |
| `tool/nursery/fast_score.py`                                          | the **replay** scorer — every gate question from the cache, no GPU (0.183 s over the 10 cells)                                 | in the tree; the gate rules are **imported** from `scoring.py`, not re-implemented                                                                                                                    |
| `tool/nursery/rank_labels.py`                                         | the ranking arm's label set-up and scoring (gate **L-G6**)                                                                     | in the tree; the mlx-lm peer of `qwen_rank.rs` — two implementations of one gate, defaults aligned by hand                                                                                            |
| `tool/nursery/third_task_dataset.py`                                  | the third, **semantically dissimilar** task's corpus (gate **L-G7**)                                                           | in the tree; the corpus is generated, not yet trained on                                                                                                                                              |
| `--arm fewshot` / `--arm noise` / `--eval-rows`                       | the few-shot control (L-G1), the noise-adapter control (L-G2), and a scored-row count knob                                     | in the tree; arms are selected with `--only-arms`                                                                                                                                                     |

**The two closing gates.** **L-G1** (few-shot) and **L-G6** (ranking) are
inference-only, cost minutes each, and **either passing CLOSES the LoRA
line** — a PASS ends the program, a FAIL keeps it open. They run first; the
expensive arms (L-G2 ≈ 18 min, L-G7 ≈ 1.5 h) are conditional on them
failing. Order and cost: [`EXPERIMENT-PLAN.md`](EXPERIMENT-PLAN.md) Part B;
gates: [`MTP-GATES.md`](MTP-GATES.md) Part 4; ledger: [`LINES.md`](LINES.md)
**Row M — the acceleration program**.

## The native text path — what it does and does not promise

`MlxNativeTextClient` (the `InferenceClient` binding, ADR 0058) is the one
public inference surface here. Two contract points are stated so a future
agent does not "fix" them into a lie:

- **Seed (ADR 0071).** The engines decode greedily (argmax), so a request
  seed cannot move the draw — the answer is deterministic by construction, not
  seed-derived. The seed is therefore ECHOED (response meta under
  `inferenceSeedMetaKey`) and REPORTED (an `InferenceResult.warnings` entry),
  never dropped and never claimed as honoured. There is no counter-based
  sampler in this package, so no seed is consumed. If a sampling decode ever
  lands here, it must draw from the core's seeded RNG — never `Random()`.
- **Structured output.** `request.outputSchema` is rendered into the prompt
  (standard JSON Schema, via the core's shared `bundleToJsonSchema`) and the
  answer is parsed back into `InferenceResponse.structuredOutput` — a markdown
  fence and surrounding prose are tolerated. This is PROMPT-RENDERED: there is
  no server-side and no token-level grammar enforcement, so
  `InferenceTask.nativelyStructuredText` is NOT claimed. An unparseable answer
  is the named `structured_output_unparseable` failure, never a success with
  a null/empty structured output.

## Laws

- Every new architecture = Rust port with a parity fixture (venv-recorded,
  provenance in the file). Never weaken an oracle.
- MoE ports: routers compute fp32 end-to-end from dequantized weights, and
  parity fixtures pin per-layer routes, not just logits (block-47 lesson;
  [PORTING-MOE.md](native/mlx_native/PORTING-MOE.md)). Nursery models train
  under [TRAIN-GATES.md](TRAIN-GATES.md) — gates frozen before the rung's
  first run, self-test oracles mandatory.
- The runtime NEVER downloads. Checkpoints resolve from the HF hub cache
  or explicit dirs.
- MLX IS LAZY. A timing harness that evaluates an UNRELATED dummy array
  measures GRAPH CONSTRUCTION, not execution (measured: 0.95 ms vs 27.18 ms
  for the same op — 28.7x). Force the ACTUAL output every iteration. The
  2026-10-20 MTP arm's speedups were artifacts of this; the rule is now
  recorded in `bench/HISTORY.md`.
- Parity-fixture streams run with EOS stop OFF (byte-identical oracles);
  the chat surfaces opt in.
- Special-token ids resolve from the checkpoint's own tokenizer, never
  carried across checkpoints: the lfm2 FFI exposes them
  (`mlx_native_lfm2_special_ids` — the 1.2B's 7/2 vs the 2.6B's
  124900/124895); the Qwen3 family shares one tokenizer across sizes
  (ids pinned by the parity fixtures).
- Bench numbers are non-claims until recorded with power state (AC/battery);
  speed comparisons are interleaved same-process (cross-run is
  thermal-contaminated).

## What is NOT bought, and why

The lane's own negative results, recorded so a future agent does not re-derive
them. The full list with the evidence is in [`LINES.md`](LINES.md); the
entries below are the ones that most often look attractive.

- **An MTP attention head.** The cost structure is the killer: attention
  raises per-head cost without touching the marginal cost of a verified
  position (J'-G4).
- **More MTP acceptance arms on the current head.** In-sample 0.90 vs
  held-out 0.12, and below a trivial bigram baseline — the arm measured a
  memorizing head, not a capacity limit.
- **A 4-bit dequant→merge→requant path.** No consumer, and the requantization
  error is the same order as the adapter delta (‖ΔW‖/‖W‖ median 5.0 %).
- **A rank / target-module sweep on the adapter.** The product-shape question
  decides whether the adapter surface is over-built; a shape sweep optimizes
  an unknown.
- **A `Task:` tag as the conditioning mechanism.** The tag's paired effect
  against the untagged control is not significant (perm p=0.185, veto
  p=1.000) and both point estimates are negative. The legal label set already
  in the prompt is the conditioning signal.
- **A shared answer space across semantically dissimilar tasks — UNESTABLISHED.**
  The per-task list is the **default** (the shared list cost ~7–9 points AND
  leaked 6 % of one task's answers into the other's vocabulary), but the
  exception — a shared list across tasks that are semantically _distant_ — has
  NOT been measured. `perm` and `veto` are both permission requests, so 6 % is
  an **upper bound**. **L-G7** (a third, dissimilar task) is the arm that
  establishes it. Until it runs, the exception is unestablished, not available.
- **A Rust port of the numerical stack.** Priced and rejected, with the
  arithmetic, in [`PYTHON-BOUNDARY.md`](PYTHON-BOUNDARY.md): the scoring path
  is 0.183 s and does not import numpy, scipy and pandas are not imported at
  all, and a port would **add a second copy of the rules** — the exact defect
  class (C-4, C-11) the lane has already paid for twice. A Python library
  earns a port only if it sits on a measured hot path, has a second copy of a
  rule that can drift, or is a correctness hazard.
