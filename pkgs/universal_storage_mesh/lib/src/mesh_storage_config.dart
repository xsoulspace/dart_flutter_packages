import 'package:meta/meta.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';

/// Configuration for [MeshStorageProvider] (ADR 0010).
class MeshStorageConfig extends StorageConfig {
  /// {@macro mesh_storage_config}
  MeshStorageConfig({
    required this.storePath,
    required this.peerId,
    this.displayName = 'device',
  }) : assert(storePath != ''),
       assert(peerId != '');

  /// Directory holding the local replica store and pairing records.
  /// Created on init.
  final String storePath;

  /// This device's stable peer id (issued at first pairing).
  final String peerId;

  final String displayName;

  @override
  Map<String, dynamic> toMap() => {
    'store_path': storePath,
    'peer_id': peerId,
    'display_name': displayName,
  };

  static MeshStorageConfig fromMap(final Map<String, dynamic> map) =>
      MeshStorageConfig(
        storePath: map['store_path'] as String,
        peerId: map['peer_id'] as String,
        displayName: (map['display_name'] ?? 'device') as String,
      );
}

/// Normalizes storage paths the same way across replicas so identical
/// logical paths map to identical doc ids.
@internal
String normalizeMeshPath(final String raw) =>
    raw.startsWith('/') ? raw.substring(1) : raw;

/// Encodes a normalized path into a filesystem-safe file name.
@internal
String encodeDocFileName(final String path) =>
    Uri.encodeComponent(path).replaceAll('/', '%2F');
