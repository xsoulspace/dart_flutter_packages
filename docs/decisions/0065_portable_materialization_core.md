# ADR 0065: Portable deterministic materialization core

Status: Accepted
Date: 2026-10-13
North Star impact: applies

## Context

Harness workspace compilation and typed edit admission are deterministic tools,
but lived alongside ECS world adapters, source observation and filesystem
transactions. Consumers could not use the compiler without importing that
product graph. Harness ADR 0091 permits semantic and conventional authoring
routes to share native application, verification and recovery authority.

## Decision

DFP owns `xsoulspace_materialization_core`: the existing Dart op-chain compiler,
graph-to-file compiler, resolved node-edit inputs, observed-expression descriptions, map-node descriptions
and Markdown/configuration scalar payload admission. The implementation moves;
workspace compatibility imports re-export it. The workspace's world/suite adapter
projects its resolved inputs into the pure compiler.

The package uses pure Dart and YAML parsing. It has no IO, ECS, Flutter, model
transport, permission system, executor or journal. It accepts host-resolved
observations as data; their presence is not authorization. Source-revision checks,
consent, locks, transaction recovery and grading remain in native adapters. Rust
Codemap remains its native implementation, not a Dart port.

Materialization does not gate all code authoring. Unsupported shapes return named
problems; conventional proposals may use the existing shared change workflow.
Denial, stale source and failed verification never become escalation permission.

## Consequences and evidence boundary

The active harness workspace is the production consumer of this extraction.
Standalone tests exercise it without a world or inference provider. This is
portable tooling, not evidence of a second product's independent adoption,
general language conversion, behavioral equivalence or direct-coding acceptance.
The existing numeric-only VM `add` versus Dart string composition distinction is
retained. Native format registries, AST observation, pack consent and transactions
remain coupled to their current owners until separately extracted and qualified.

Gate: `just check xsoulspace_materialization_core` from DFP; existing workspace
materializer, observed-return, binding and edit gates verify compatibility.
