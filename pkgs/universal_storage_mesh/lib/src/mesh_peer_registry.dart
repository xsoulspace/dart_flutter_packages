import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';

/// Durable registry of paired peers (the outcome of QR scanning,
/// ADR 0010 §3). v1 stores records as JSON; key material handling arrives
/// with real transports.
final class MeshPeerRegistry {
  MeshPeerRegistry({required this.filePath});

  final String filePath;
  final Map<String, MeshPeerRecord> _peers = {};

  static Future<MeshPeerRegistry> load(final String filePath) async {
    final registry = MeshPeerRegistry(filePath: filePath);
    final file = File(filePath);
    if (file.existsSync()) {
      try {
        final raw = jsonDecode(await file.readAsString());
        if (raw is List) {
          for (final entry in raw.whereType<Map<dynamic, dynamic>>()) {
            final peer = MeshPeerRecord.fromJson(
              Map<String, dynamic>.from(entry),
            );
            registry._peers[peer.peerId] = peer;
          }
        }
      } on FormatException {
        // Corrupt registry starts empty; pairing re-adds peers.
      }
    }
    return registry;
  }

  Iterable<MeshPeerRecord> get peers => _peers.values;

  MeshPeerRecord? byId(final String peerId) => _peers[peerId];

  Future<void> register(final MeshPeerRecord peer) async {
    _peers[peer.peerId] = peer;
    await persist();
  }

  @visibleForTesting
  Future<void> persist() async {
    final file = File(filePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(_peers.values.map((final p) => p.toJson()).toList()),
    );
  }
}
