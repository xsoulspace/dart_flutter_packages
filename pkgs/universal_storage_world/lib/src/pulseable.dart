/// The ONLY scheduling contract of the world layer (ADR 0047 §4): hosts
/// drive sync; the layer never owns a loop.
///
/// Composability law — the oka/flutter pattern: like a Flutter `Ticker` is
/// driven by the SchedulerBinding and an oka lane is executed by the oka
/// runner, a [Pulseable] is PULLED by whatever loop its host already runs:
///
/// - a game drops `meshPulseSystem(session)` into its existing ecsly
///   schedule (its own scheduler in `ecsly_flutter`/`ecsly_app` — nothing
///   new to adopt);
/// - a Flutter app drives it from a `Timer.periodic` convenience or its own
///   ticker;
/// - the harness drives it from its event loop;
/// - tests drive it from microtasks.
///
/// Contract: implementations must be idempotent and COALESCING — a pulse
/// landing while a cycle is in flight is skipped, never queued; the next
/// pulse picks the work up. Transport-level failures are swallowed and
/// surfaced as session state, never thrown into the host's loop.
abstract interface class Pulseable {
  /// Runs at most one sync cycle. Safe to call from any loop, any rate.
  Future<void> pulse();
}
