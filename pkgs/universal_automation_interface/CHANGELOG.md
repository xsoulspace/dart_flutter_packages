# Changelog

## 0.2.0

- **Behavior dynamics contract (ADR 0044)**: declarative, composable input
  profiles for humans and agents.
  - New `behavior` module: `BehaviorStep` timed input-step vocabulary,
    `BehaviorPlan`, `BehaviorProfile` (facets: `ActionRhythm`,
    `ReactionDelay`, `SessionPacing`, `PointerMotion`, `KeystrokeCadence`),
    priors (`agentImmediate` degenerate profile, `humanPrior(seed)`
    hyper-prior), `synthesizeBehavior`/`projectBehavior` deterministic
    synthesis, `auditBehavior` self-consistency reporting,
    `BehaviorReceipts` encoders, canonical JSON + SHA-256 hashing, and the
    pinned `xoshiro128**`/splitmix32 PRNG.
  - New `BehavioralDriver` opt-in capability surface (`performWith` with
    typed `BehaviorOutcome`), `ProfiledDriver` wrapper, and
    `DriverCapabilities.behaviorDynamics` (default `false`; `full` sets it).
  - Breaking: `DriverCapabilities.full` now sets `behaviorDynamics: true`;
    drivers claiming `full` without implementing `BehavioralDriver` should
    declare an explicit capability set instead.
