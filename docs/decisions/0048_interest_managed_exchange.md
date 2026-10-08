# ADR 0048: Interest-managed mesh exchange — the sub frame, priority, budget

- Status: Accepted
- Date: 2026-10-08
- North Star impact: `amends` — extends [0010 §4](0010_mesh_sync_architecture.md)
  with one additive frame; the symmetric single-round anti-entropy shape,
  the kernel's authority, and the convergence guarantees are unchanged.
- Builds on: [0010](0010_mesh_sync_architecture.md),
  [0047](0047_world_layer_zone_journeys.md) (the world model)

## Context

The mesh exchange sent every local doc's version vector and computed
deltas for every doc in the store, unconditionally. Sync cost scaled with
the whole world instead of the subscriber's working set — the one
industry-proven mechanism for invisible zone travel (game relevancy
filters: UE Iris's cell filters, coherence LiveQueries) that the stack
lacked entirely.

## Decision

### 1. One additive frame: `sub`

Both sides now send `hello`, **`sub`**, `vv`, `delta`. The sub frame
publishes:

- `policy` — the sender's [InterestSelection] (wire form):
  `{all: bool, docs: [docId…], prefixes: [pathPrefix…]}`. Structural and
  auditable on purpose — there is deliberately no predicate language on
  the wire; a subscriber's choice must stay readable in a protocol trace.
- `priority` — receiver-expressed `{docId: rank}`; the peer sends ranked
  members' ops first (unranked follow deterministically by docId).
- `budget` — max ops the peer may send in this delta (backpressure-lite;
  the remainder arrives on later pulses).

Hosts build policies with `InterestPolicy` resolvers (static sets,
prefixes, unions — or their own: a game's spatial query, an app's open
surfaces); the policy is RESOLVED to a selection before each pulse, so
movement between zones re-subscribes without protocol change.

### 2. The gate is the delta, not the announcement

The `vv` stays unfiltered and goes out immediately — no handshake
round-trip on the critical path. The peer's selection gates OUR DELTA:
out-of-selection members are never computed, ordered, or sent. This
ordering also makes the frame backward-compatible (§3).

### 3. Back-compat law: absent sub = wildcard

A pre-0048 peer sends no sub frame. Our receive loop tolerates its
absence (wildcard), and the old peer's `_recvOfType(vv)` skips our
unknown `sub` frame exactly like any other unrecognized type — both
directions converge unchanged. Proven by the mesh integration suite,
including a scripted old-peer speaking the pre-0048 script.

## Property obligations

- Subscriber-only delivery: out-of-selection members never cross the
  wire (mesh `interest_exchange_test.dart`).
- Budget determinism: N ops per exchange, convergence across pulses.
- Priority: with a budget of one, exactly the ranked member crosses.
- Old-peer interop: scripted pre-0048 responder completes a full
  exchange.

## Non-claims

- No partial-DOC subscriptions (lane/key predicates inside a doc) — the
  selection is member-grained; sub-doc filtering is deferred until a
  consumer needs it.
- No push-based "relevance change" notification — selections re-publish
  every exchange (cheap: one small frame); a delta-push channel is
  ADR 0041's domain.
- No privacy claim: selections reveal interest to paired peers; paired
  meshes are trust-on-pair.
