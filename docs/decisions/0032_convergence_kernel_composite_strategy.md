# ADR 0032: Convergence kernel — composite strategy (one document, one kernel doc)

- Status: Accepted
- Date: 2026-09-06
- North Star impact: `clarifies` (new strategy within the ADR 0011
  `MergeStrategy` seam; sub-star boundary unchanged)
- Builds on: [0011](0011_convergence_kernel_dual_mode.md),
  [0029](0029_convergence_kernel_presence_and_sequence_strategy.md)
- Driving consumers: last_answer `DocReplica` (doc ops), ecsly
  `plugins/ecsly_world_sync` (future multi-lane worlds)

## Context

A `ConvergenceDoc` binds exactly one `MergeStrategy`, and a real document
needs several fold semantics in one op stream: LWW for fields and
fractional order keys, RGA for block text. The first consumer
(last_answer `DocReplica`) worked around this with **two sibling kernel
docs per document** (an LWW lane + an RGA lane, shared docId, prefix-routed
ops, shared HLC watermark). That workaround is now a recorded liability:
anti-entropy (`opsSince` / `needsSnapshotFor` / snapshots / compaction) is
per-kernel-doc, so the parent would have to merge two version vectors and
coordinate half-covered peers itself — the exact hand-rolled
ordering/compaction logic ADR 0011 forbids. ecsly worlds will hit the same
wall the moment a world needs LWW + sequence state together.

## Decision

### 1. Composite strategy inside the existing seam (chosen: key-prefix dispatch)

The kernel gains one new strategy, `CompositeMergeStrategy`:

- constructed from an ordered lane map: `key prefix → sub-strategy`;
- `fold` dispatches each op to its lane by longest-matching prefix (the
  composite validates that every op matches exactly one lane and names
  the mismatch otherwise — never silently drops);
- one `ConvergenceDoc` per document: ONE version vector, ONE op log, ONE
  snapshot/compaction decision, ONE anti-entropy header;
- serialization: the lane map is part of the composite's registry name
  (wire-stable, e.g. `composite:<lane-spec-id>`); `ConvergenceDoc.fromJson`
  restores it without parent-side re-routing.

Property obligations (per ADR 0011 §2, extended):

- **Commutativity by inheritance**: property tests assert that when every
  lane is commutative/idempotent, the composite is too — for any delivery
  order, any interleaving of lanes, and any batch split;
- snapshots fold all lanes atomically (a peer is never half-covered);
- lane-map mismatch on restore is a named error, never a silent re-route.

Consumers migrate: last_answer `DocReplica` collapses its two lanes into
one `ConvergenceDoc` (removing prefix-routing from the parent). This is
the gate for 5b mesh wiring — wiring does not start on the two-lane shape.

### 2. Scheduled expansion: per-op strategy tags (chosen: deferred, trigger recorded)

The more general shape — `OpRecord` carrying its own strategy tag, the doc
routing per op — stays OUT of v1. Expand from prefix dispatch to per-op
tags when ANY of these fires (recorded as the trigger, not speculation):

1. **Prefix collision across parents**: two consumers need different lane
   maps for the same key namespace (the lane map stops being shareable).
2. **Unstable keys**: a document needs a strategy lane whose keys have no
   stable prefix (heterogeneous per-node strategies).
3. **Lane count**: a document legitimately needs more than ~4 lanes and
   prefix dispatch becomes brittle to maintain.
4. **Cross-repo self-description**: ecsly worlds need ops that identify
   their semantics without the receiving parent owning the lane map.

Until a trigger fires, prefix dispatch is the whole contract; adding tags
prematurely doubles the wire surface for zero consumers.

## Non-claims

- The composite adds no new merge semantics — it composes strategies that
  carry their own conformance obligations.
- No migration of existing two-lane persisted docs is owed (DocReplica has
  no shipped users; fresh docs under the composite).

## Consequences

- Parents (last_answer, ecsly) keep one-document-one-replica mental
  models; anti-entropy stays trivially per-document.
- The kernel's strategy registry grows by one name; conformance suite
  grows the composite property tests above.
