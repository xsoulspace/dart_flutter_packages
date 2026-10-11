/// Anti-entropy session core over the convergence kernel (ADR 0011
/// sub-star, sibling of mesh sync and ecsly world sync): the wire codec,
/// delta planning, the receive watermark, and the compaction policy that
/// every anti-entropy session needs — in one place, so the mesh exchange
/// and ecsly world sync speak byte-identical protocol and share one
/// decision logic.
///
/// Pure Dart. Knows nothing about transports, storage, documents, or
/// worlds: bytes in, bytes out; replicas in, plans out. The 4-byte frame
/// codec stays in `universal_storage_mesh_transport` — this package starts
/// above the frame layer.
library;

export 'src/delta_planner.dart';
export 'src/receive_watermark.dart';
export 'src/session_wire_protocol.dart';
export 'src/snapshot_policy.dart';
