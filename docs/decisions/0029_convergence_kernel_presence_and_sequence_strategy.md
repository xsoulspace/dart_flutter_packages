# ADR 0029: Convergence kernel — presence/ephemeral contract and sequence strategy pulled forward

- Status: Accepted
- Date: 2026-09-06
- North Star impact: `clarifies` (resolves two recorded non-claims of
  [0011](0011_convergence_kernel_dual_mode.md); the sub-star boundary is unchanged)
- Builds on: [0010](0010_mesh_sync_architecture.md), [0011](0011_convergence_kernel_dual_mode.md)
- Driving consumer: last_answer ADR 0005 (doc multiplayer over the
  convergence kernel — business logic lives there; this ADR records only
  the kernel-side contract)

## Context

Kernel ADR 0011 recorded two honest non-claims: "Not yet real-time session
infrastructure. Presence/ephemeral state … has no dedicated contract yet"
and "Sequence/text CRDT strategies … are a later phase." The first
multiplayer consumer (last_answer doc multiplayer) now pulls both:

1. Agent output arrives as **incremental text streams**; once a second
   peer connects, streamed text must merge — the sequence strategy cannot
   wait for a "later phase".
2. Presence must be **agent-queryable** ("who is connected to this doc")
   — AI-native, not UI-only — while live UI presence should still die on
   disconnect.

## Decision

### 1. Dual-mode presence mirrors the dual-mode kernel

- **Transport-level ephemeral frames** stay OUT of the kernel: unlogged,
  no durability, no GC — presence dies on disconnect by design. Defined
  at the mesh transport layer (ADR 0010 seam), consumed by live UI.
- **Kernel ephemeral ops**: a new op class carrying a TTL. Contract:
  - delivered through the normal `ConvergenceDoc` path (same dedupe,
    same ordering);
  - never folded into snapshots, never retired by compaction — they
    simply expire;
  - expired ops are dropped on apply and excluded from version-vector
    watermark obligations (an expired op needs no ack);
  - the agent-queryable registry is a fold over live (unexpired)
    ephemeral ops.
- Property tests extend accordingly: expiry is commutative and idempotent
  (a peer applying the same expired op set converges to the same state).

### 2. Sequence merge strategy is pulled forward — scoped

- First strategy beyond LWW: a sequence merge (RGA/YATA family) behind
  the unchanged `MergeStrategy` seam, scoped to **block text content**
  (including streamed agent text).
- All ADR 0011 obligations apply unchanged: property-tested
  commutativity/idempotence per shipped strategy, conformance evidence
  from all consuming parents before kernel release.
- **Fractional order keys for structural child order are parent-side
  policy (last_answer), not kernel types** — the kernel gains no new
  structure-ordering concept.

## Non-claims

- No broadcast/pub-sub API: ephemeral ops ride the existing doc path; the
  kernel still knows nothing about transports.
- No intra-kernel presence semantics (typing, cursors): payloads are
  opaque to the kernel, as with all ops.

## Consequences

- last_answer's multiplayer ADR can name the kernel as its sole merge
  substrate without waiting for a future kernel phase.
- The kernel's strategy count grows to three (LWW map, sequence,
  ephemeral class) — each carries its own property-test obligation, per
  ADR 0011's "known-hard parts now explicit" rule.
