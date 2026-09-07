/// Serverless peer-to-peer storage provider for Universal Storage
/// (ADR 0010).
///
/// Every device is a full replica with equal standing; relays or bridges,
/// if ever added, are nodes with a role — never an origin. Reads and
/// writes are always local; [MeshStorageProvider.sync] opportunistically
/// converges state over whatever [MeshTransport] link exists.
library;

export 'src/ephemeral_frame_auth.dart';
export 'src/ephemeral_frame_transport.dart';
export 'src/mesh_frame_auth.dart';
export 'src/mesh_kv_store.dart';
export 'src/mesh_pairing_session.dart';
export 'src/mesh_path_utils.dart';
export 'src/mesh_peer_registry.dart';
export 'src/mesh_presence_observer.dart';
export 'src/mesh_presence_session.dart';
export 'src/mesh_presence_tracker.dart';
export 'src/mesh_storage_provider.dart';
export 'src/pairing_service.dart';
export 'src/presence_config.dart';
export 'src/relay_ephemeral_transport.dart';
