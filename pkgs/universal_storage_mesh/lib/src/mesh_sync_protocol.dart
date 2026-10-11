/// Re-export of the anti-entropy wire codec, moved to the shared session
/// core (`universal_storage_convergence_session`) so mesh and ecsly world
/// sync speak byte-identical protocol.
///
/// Only the symbols this package has always exported are re-exported —
/// the envelope builders/parsers, and the byte-level plane classifiers —
/// not the session core's planner/watermark/policy surface. The goldens in
/// `test/mesh_sync_protocol_golden_test.dart` pin the wire bytes across
/// the move.
library;

export 'package:universal_storage_convergence_session/universal_storage_convergence_session.dart'
    show MeshSyncProtocol, looksLikeWorldSyncFrame, meshFrameTypeIs;
