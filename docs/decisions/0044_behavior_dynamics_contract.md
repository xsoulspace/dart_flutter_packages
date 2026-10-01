# ADR 0044: Behavior dynamics contract — declarative input profiles for humans and agents

- Status: Accepted
- Date: 2026-10-01
- North Star impact: `amends` [ADR 0037](0037_universal_automation_family.md)
  (extends the family contract with a behavior surface) and [ADR
  0038](0038_automation_kernel_unification.md) (new opt-in capability on the
  kernel contract)
- Builds on: [ADR 0037](0037_universal_automation_family.md) (driver
  contract, refuse-not-degrade), [ADR 0040](0040_universal_driver_macos.md)
  (CGEvent synthesis tier)

## Context

The family had no way to describe *how* input is delivered. CDP input is
teleporting (`mousePressed`/`mouseReleased` at a resolved center,
`Input.insertText` for text, zero timing control — `cdp_page.dart`), and
the only timing in the whole family is CDP's hard-coded 15s navigate wait.
Consumers pulled in opposite directions: agent workloads need deterministic,
near-zero-latency actuation with pacing policy and audit attribution; the
production browser-fleet consumer faces behavioral gates that reject
instant, metronomic input.

The naive framing — "humanized input" — is the wrong shape. It treats
human-like delivery as a feature bolted next to agent delivery, which makes
the two unvalidatable by construction: there is nothing to say about an
agent's timing, and no shared machinery to check either stream against.
The corrected frame: **input dynamics as declarative, composable data**, where
human-like and agent-like are both first-class profiles over the same facet
space, and the same pure functions synthesize and audit both. (External
prior art sharpened this: W3C WebDriver actions already standardized
declarative timed input; ghost-cursor ships one hardcoded realism preset
with no seed and no audit; Playwright proves outcome-determinism over
realism with per-call `delay`/`timeout` knobs.)

A Mixture-of-Experts design review (Dart contracts, behavioral detection,
agent systems, standards/validation; 2026-10-01) converged with these
corrections to the first sketch:

1. **The missing centerpiece is an input-primitive vocabulary.** The
   interface has no type between "intent action" and "protocol event", so
   `synthesize`/`audit` would be parameter schemas glued to nothing. A
   timed input-step family must come first.
2. **Session structure outranks per-action polish.** Detectors weight
   cross-action statistics (transition-conditioned gaps, noise events,
   rhythm drift) more than per-event texture; independent per-sample jitter
   is itself a synthetic tell.
3. **Presets must be priors, not shared constants.** A public
   `humanTypical` constant makes every user of the library emit the same
   distribution — a cohort fingerprint. Human delivery ships as a
   hyper-prior that samples per-session parameters from broad ranges.
4. **A materialized absolute-time stream re-creates the teleport problem
   one level up.** Synthesis produces a deterministic canonical *plan*;
   segments are target-anchored and materialized (re-resolved) at dispatch.
5. **`agentImmediate` must survive `synthesize`/`audit` untouched.** If the
   driver special-cased it as a bypass flag, the human/agent symmetry would
   be cosmetic.

## Decision

### Contract surface (`universal_automation_interface` 0.2.0)

- **`BehaviorStep`** — sealed, payload-light, timed input-step vocabulary
  (`pointerMove`, `pointerDown`, `pointerUp`, `keyDown`, `keyUp`, `char`,
  `wheel`, `dwell`), integer-microsecond relative timing, canonical JSON.
  This is the element type of every stream, plan, and audit.
- **Timing distributions as sealed data** — `FixedTiming`, `UniformTiming`,
  `PiecewiseTiming` (empirical quantile boundaries). Distributions are data
  with const constructors — never closures — so profiles are `const`-able
  and sampling is pure integer/rational arithmetic (bit-stable without
  transcendentals).
- **`BehaviorProfile`** (`TypedSpec`) — composable facets: `ActionRhythm`
  (pre-action dwell), `ReactionDelay` (observation→dispatch floor; the
  driver enforces the floor, the agent loop owns its real latency),
  `SessionPacing` (noise-event rate, drift), `PointerMotion` (path model,
  per-move duration, button hold), `KeystrokeCadence` (digraph latency,
  key hold). Validated at construction — an invalid profile is not
  constructible.
- **Priors**: `BehaviorProfile.agentImmediate` (`static const` degenerate
  profile — zero timing, direct paths; the current behavior, explicit) and
  `BehaviorProfile.humanPrior(seed)` — a hyper-prior sampling broad-range
  per-session parameters. No `humanTypical` constant ships.
- **Pure functions**: `synthesize(profile, seed, action) → BehaviorPlan`
  (deterministic; hand-rolled `xoshiro128**` PRNG, splitmix64 seeding, only
  correctly-rounded float ops); `project(profile, seed, action) →
  BehaviorProjection` (pre-flight timing/bounds for agent budgeting);
  `auditBehavior(report, profile) → BehaviorReport` (moment deltas vs the
  declared distributions, biomechanical-ceiling flags, structural
  descriptives — numbers, never boolean verdicts).
- **`BehavioralDriver`** — opt-in capability surface (`performWith(action,
  profile) → BehaviorOutcome`), immutable `withProfile()` wrapper, typed
  interruption report (verdict `complete`/`truncated`/`aborted`, cause,
  completed/cancelled steps; no magic rollback of half-delivered input).
  `DriverCapabilities.behaviorDynamics` (default `false`, additive).
- **`BehaviorReceipt`** — receipt line types (profile hash, seed, facet
  versions, stream hash, per-event planned/dispatched/drift, terminal
  verdict), aligning with the recording receipt contract families. The
  receipt records what was planned and dispatched — never what the page did.

### Determinism rules (binding on all implementations)

Hand-rolled pinned PRNG (`xoshiro128**-v1`, 32-bit masked ops) seeded via
splitmix64; synthesis restricted to `+ - * / sqrt` and integer ops (Bezier
via de Casteljau); times canonicalized to integer microseconds, coordinates
to a fixed decimal grid; canonical JSONL with documented field order;
SHA-256 hand-rolled in-package (zero-dep discipline) pinned by test vectors.
`DateTime.now()` never enters synthesis — wall time exists only in receipt
envelopes. Seeds for production sessions are session-sensitive secrets;
deterministic seeds are for tests/CI.

### Lowering

- **CDP** (`universal_browser_cdp` 0.2.0): client-side scheduler —
  absolute wall-clock schedule points, planned timestamps *stamped* on every
  dispatch (delivery jitter becomes invisible to page-observable timing),
  serialized awaited dispatches, move cadence ≥ one frame period, dispatch
  gate across navigation, revision re-check before commit. Typing lowers to
  per-char `rawKeyDown`/`char`/`keyUp` (cadence is unobservable over
  `Input.insertText`); a facet the transport cannot honor throws
  `DriverUnsupportedException` — never silently degrades. Click resolution
  gains scrollIntoView + hit-target verification (element or descendant at
  the point). Reaction floors are enforced against the last observation
  timestamp. Receipt writer mirrors the screencast file contract.
- **WebDriver/BiDi**: lower to W3C actions sequences (remote-end timing) —
  Phase 3 follow-up; until landed, `behaviorDynamics` stays `false` and the
  driver refuses loudly, which is the family-correct posture.
- **CGEvent tier**: Phase 3 follow-up, same contract.

### Phasing

Full facet set declared in the contract up front (sealed families are
cheapest to declare once); implementation lands: (1) rhythm/pacing/reaction
— driver-agnostic, serves agents immediately; (2) CDP primitives (per-char
keys, stamped motion scheduler, hit-checked resolution) + receipts +
conformance; (3) pointer-motion and cadence facets live on CDP, W3C actions
lowering, CGEvent lowering.

## Non-claims

- `isTrusted` is a property of the transport, not this API; the API neither
  grants nor strengthens it.
- The API changes no environment signals (`navigator.webdriver`, CDP
  surface, TLS/HTTP fingerprints, IP reputation) — where most gating volume
  actually happens.
- No claim, implied or stated, about pass rates on any third-party
  challenge or risk score. Audit numbers are descriptive, never predictive.
- The API models motor statistics, not decisions; realistic motion with
  robotic task structure still scores as automated.
- It removes gross dynamic tells; it does not make streams
  indistinguishable from human streams, and synthesized distributions are
  themselves identifiable. Human-likeness *scoring* requires a reference
  corpus and is the consumer's job; the library measures physics and
  self-consistency only.
- Presets/priors are per-deployment configuration (like UA strings);
  shipping one shared human-like distribution is explicitly rejected as a
  cohort marker.

## Consequences

- `universal_automation_interface` → 0.2.0 (sealed-family additions are
  breaking for exhaustive switches without `_` arms); dependents bump
  constraints; behavior types are additive elsewhere.
- The legacy `perform` path is unchanged — profiles are opt-in; absence of
  a profile means today's delivery.
- Conformance gains behavior suites: hermetic determinism (bit-identical
  plans, no driver), structural wire equivalence against fake endpoints,
  and refuse-not-degrade pinning for unsupported facets.
- Ownership boundaries unchanged: profiles are data the orchestrator may
  choose per session; lifecycle (process spawn/stop) stays outside the
  family. moli (lexmount/moli) and similar agent-browser kernels are
  *targets* this family's CDP/WebDriver clients can attach to, not
  competitors of the drivers.
