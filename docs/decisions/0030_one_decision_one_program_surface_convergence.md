# ADR 0030 — One decision, one program: the meaning surface converges; the format is never the model's choice

- Status: Accepted (2026-09-06)
- North Star impact: `clarifies` — applies the flat-tokens law (0028) and
  the verified-growth ladder (0022 §3) to the model-emitted chain; the
  composition law (0020) and materializer law (0024) are unchanged.
- Builds on: [0022](0022_workspace_oracle_meaning_pipeline.md),
  [0024](0024_filesystem_one_map_graph_typed_materializers.md),
  [0028](0028_one_move_per_decision_native_loop_bounded.md),
  [0029](0029_convergence_kernel_presence_and_sequence_strategy.md)
- Measured trigger: fixed-surface saturation — the meaning profile is
  6 tools at **1,598 of the 1,600-token gate**
  (`meaning_profile_overhead_test.dart`, 2026-09-06), with
  `meaning_locate` + the md/yaml verbs still unsurfaced; per finding 13
  the native truth is ~45% heavier than the estimator.

## Context

Two laws are colliding:

1. **Every capability wants a verb** — locate, `edit_section`,
   `edit_key`, run scopes, VCS reads, … — and every verb adds schema
   tokens to EVERY decision, forever (the anti-amortization force).
2. **The window does not grow** — 4,096 native on AFM, and the fixed
   surface is paid per decision (0028 made the per-decision shape exact:
   one call, one result).

Meanwhile the ladder proved the opposite force works: the trusted-author
row landed a real fix at ZERO authored tokens through a pre-forged chain;
`task_grammar` resolves the structured 80% of task sentences at zero
decisions; `capability_nodes` put the capability INVENTORY into the tree
so it costs nothing per prompt; `execution_meaning` established the
result-cut law (write-time span clipping). The host side of the
amortization problem is solved; what is missing is the rung for tasks
that parse to neither the grammar nor an existing pack: the model must
be able to chain the reads itself — without the surface growing.

## Decision

1. **One decision, one program (ladder rung 3).** A decision may emit
   ONE tool call whose argument is a PROGRAM over a closed READ op set —
   `locate`, `zoom`, `impact`, `read` — interpreted by the host against
   the meaning tree. Single linear cursor dataflow (each read op advances
   the cursor to what it found; explicit ids override), fail-fast with
   named bounces (`program_halt` naming the op index), deterministic op
   cap, per-op and verdict budgets. One call → the contract (0028) holds
   by construction; the fixed surface is paid once for N reads.
2. **The format is never the model's choice.** Ops address MEANING
   NODES, never files or languages. The node's class routes the host's
   reader/materializer (`file_class_spec`, ADR 0024): a section reads as
   md, a keypath as yaml/json, a symbol as a Dart span — through the SAME
   op. Project constraints (docs → md, configs → yaml/json/data, Dart →
   code) live in the host's registry and the task, never in a model
   parameter. NEW LANGUAGES AND FRAMEWORKS GROW THE REGISTRY, NEVER THE
   MODEL SURFACE — a tiny model must keep working unchanged when a new
   file class lands, because it works through meaning.
3. **Surface convergence, gated graduation.** The program tool does NOT
   enter the meaning profile while the gate is saturated. It graduates
   ONLY BY REPLACING the verbs it subsumes (locate/zoom/impact schemas
   come OUT when the program comes in) — the profile must SHRINK, never
   grow. Until the measured row exists, the tool ships behind an explicit
   gate (LLM-free tests + opt-in registration), like the intent-closure
   arm before it.
4. **Result-cut is the program's law** (from `execution_meaning`): each
   op's result is bounded at the interpreter; the verdict names
   truncation honestly. A program that reads widely still returns a
   compact envelope.

## Consequences

- The overhead test gains a second binding row: the CONVERGED profile
  (repo_etl + program + edit_symbol + write_review + run) — the row that
  proves the surface shrinks when the program graduates.
- Edit/mutation ops join the op set only behind a verified on-device row
  (same discipline as trusted-author); read-chains are the zero-risk
  first rung.
- The flatness probe (harness `tool/afm_flatness_probe.dart`) gains the
  program mode: per-move vs program-chained tokens/decision is THE
  graduation measurement.
- Named, not built: mutation ops; program-mode rows on-device; daemon
  registration of the program tool.
