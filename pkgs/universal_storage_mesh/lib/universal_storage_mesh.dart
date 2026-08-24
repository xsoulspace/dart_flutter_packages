/// Serverless peer-to-peer storage provider for Universal Storage
/// (ADR 0010).
///
/// Every device is a full replica with equal standing; relays or bridges,
/// if ever added, are nodes with a role — never an origin. Reads and
/// writes are always local; [MeshStorageProvider.sync] opportunistically
/// converges state over whatever [MeshTransport] link exists.
library;

export 'src/mesh_path_utils.dart';
export 'src/pairing_service.dart';
export 'src/mesh_peer_registry.dart';
export 'src/mesh_storage_provider.dart';
