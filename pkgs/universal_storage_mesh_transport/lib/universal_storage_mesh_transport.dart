/// Transport seam for Universal Storage mesh sync (ADR 0010 §1).
///
/// The mesh provider knows nothing about radios; transports know nothing
/// about documents. Frames carry convergence-kernel envelopes only.
library;

export 'src/fake_mesh_transport.dart';
export 'src/frame_codec.dart';
export 'src/mesh_peer.dart';
export 'src/mesh_transport.dart';
export 'src/addressed_relay_protocol.dart';
export 'src/addressed_relay_client.dart';
export 'src/addressed_relay_server.dart';
