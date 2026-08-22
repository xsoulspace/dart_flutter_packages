# ADR 0002: Handler response contract — return value is authoritative

- Status: Accepted
- Date: 2026-08-22
- North Star impact: `clarifies`

## Context

`actorActSystem` dispatches generation fire-and-forget and relies on the
handler to publish the result as an `ActorGenerateResponse` event on the world
channel; `processResponsesSystem` consumes only channel events. The returned
`Future<ActorGenerateResponse>` was ignored on the happy path.

This created an **undocumented dual delivery contract**: every built-in
handler (mock, scripted, native bridge) both sends to the channel *and*
returns the response. A handler that only returns — the natural thing to
write — silently deadlocks the actor in `AwaitingResponse` forever:
`respSent=0`, no error, `canSleep()` never true. Found while building the
guided-decision handler (`StructuredToolDecisionHandler`); reproduced with a
minimal sync handler (`debug_sync_handler.dart`, since removed).

Industry ECS engines avoid this class of bug structurally:

- **Bevy** orders `EventWriter` before `EventReader` via declared system
  access — same-tick delivery is guaranteed by the schedule compiler.
- **Unity DOTS / Unreal Mass** carry events as buffer components on entities,
  so one lifecycle governs all messages.
- **Flecs** uses deferred command queues with one flush point — a single
  authoritative direction of flow, never two competing delivery mechanisms.

The harness violated the Flecs principle: two delivery paths for one message.

## Decision

1. **The returned future is authoritative.** `actorActSystem` now inspects
   the resolved response: if the channel has no event for that `taskId`, it
   publishes the returned response itself. Handlers that send-and-return
   (all built-ins) are unaffected — no double-send.
2. **The channel remains the only consumption path.**
   `processResponsesSystem` is unchanged; ordering, ledger, and idle
   detection semantics are preserved.
3. **Handler authors may send *or* return; the system guarantees delivery.**
   The contract is documented at the `GenerationHandler` interface level.
4. **Long-term direction (not in this change):** move to Bevy-style declared
   access or handler-returns-only publication, removing the ambiguity at the
   type level. Revisit if a second dispatch site appears.

## Consequences

- A whole class of silent hangs becomes impossible; a non-sending handler
  degrades to working-by-fallback instead of deadlocking.
- The fallback check is O(pending events) per dispatch — negligible at
  harness scale (≤256-capacity channels, serial AFM).
- `HarnessExecutionLedger` traces remain accurate: the synthesized send is a
  real channel send, visible in watermarks.
- Known limitation: a handler that sends a *different* response than it
  returns still wins with its send (channel-first). That is the correct
  precedence — explicit publication is more intentional than a return value.

## Non-goals

- Changing `processResponsesSystem`, event channel capacity/policy, or the
  tool-call path (already task-registry-backed and race-tested).
- Restructuring events into entity-buffer components (viable future work,
  larger blast radius).
