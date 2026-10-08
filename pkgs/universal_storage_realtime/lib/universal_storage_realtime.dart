/// The realtime event plane over mesh sessions (ADR 0050): the four
/// semantics every realtime app re-implements — liveness, droppable
/// newest-wins sends, reliable exactly-once sends, multi-sender
/// arbitration — as a library, so an app brings only its event schema
/// and (for richer fusion) an arbiter policy.
///
/// Plane law: realtime is ONE plane of a shared server — claim it with
/// [looksLikeRealtimeFrame] next to the sync and blob planes (ADR 0047).
/// Scheduling law: a link either owns its heartbeat/staleness timers
/// (the default) or is built [RealtimeLink.tickDriven]/[RealtimeHost
/// .tickDriven] and the consumer pulses [RealtimeLink.tick] from a loop
/// it already runs — the pulse law (ADR 0047 §4). The HOST never spawns
/// loops beyond the links'. Auth law: the transport may authenticate the
/// session, but the host decides who drives — [RealtimeHost
/// .adoptSession] is the gate; [RealtimeHost.claimSender] is the
/// reconnect law's primitive.
library;

export 'src/realtime_envelope.dart';
export 'src/realtime_host.dart';
export 'src/realtime_link.dart';
