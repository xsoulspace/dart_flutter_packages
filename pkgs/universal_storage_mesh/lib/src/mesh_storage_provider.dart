import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:universal_storage_convergence/universal_storage_convergence.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';

import 'mesh_peer_registry.dart';
import 'mesh_storage_config.dart';
import 'mesh_sync_protocol.dart';

/// Serverless P2P storage provider (ADR 0010).
///
/// - Local reads/writes never touch the network; every replica's local
///   store is authoritative for latency.
/// - Each stored file is one convergence document (kernel LWW map with a
///   single `content` register), giving deterministic object-level LWW
///   convergence across replicas (ADR 0010 §5).
/// - [sync] runs symmetric anti-entropy sessions over the attached
///   [MeshTransport]; unreachable peers are skipped silently — sync is
///   opportunistic, manual-trigger friendly, and never blocks local work.
final class MeshStorageProvider implements StorageProvider {
  static const _contentKey = 'content';

  MeshStorageConfig? _config;
  Directory? _docsDir;
  MeshPeerRegistry? _registry;
  MeshTransport? _transport;
  final Map<String, ConvergenceDoc> _docs = {};
  var _initialized = false;

  /// Registers a transport for this replica and wires inbound sessions.
  /// Call once after [initWithConfig].
  void attachTransport(final MeshTransport transport) {
    _transport = transport;
    transport.onIncomingSession = (final session) async {
      await _runExchange(session);
      await session.close();
    };
  }

  /// Outcome of QR scanning: adds a paired peer to the durable registry.
  Future<void> registerPeer(final MeshPeerRecord peer) async {
    _ensureInitialized();
    await _registry!.register(peer);
  }

  Iterable<MeshPeerRecord> get peers => _registry?.peers ?? const [];

  @override
  StorageCapabilities get declaredCapabilities => const StorageCapabilities(
    syncAvailability: SyncAvailability.withRemoteConfig,
  );

  @override
  bool get supportsSync => true;

  @override
  Future<bool> isAuthenticated() async => _initialized;

  // -- StorageProvider contract -------------------------------------------

  @override
  Future<void> initWithConfig(final StorageConfig config) async {
    if (config is! MeshStorageConfig) {
      throw ConfigurationException(
        'MeshStorageProvider requires MeshStorageConfig, '
        'got ${config.runtimeType}.',
      );
    }
    final docsDir = Directory('${config.storePath}/docs');
    await docsDir.create(recursive: true);
    _config = config;
    _docsDir = docsDir;
    _registry = await MeshPeerRegistry.load('${config.storePath}/peers.json');
    await _loadDocs();
    _initialized = true;
  }

  @override
  Future<FileOperationResult> createFile(
    final String path,
    final String content, {
    final String? commitMessage,
  }) async {
    _ensureInitialized();
    return _applyContentOp(normalizeMeshPath(path), content, allowNew: true);
  }

  @override
  Future<FileOperationResult> updateFile(
    final String path,
    final String content, {
    final String? commitMessage,
  }) async {
    _ensureInitialized();
    return _applyContentOp(normalizeMeshPath(path), content, allowNew: false);
  }

  @override
  Future<String?> getFile(final String path) async {
    _ensureInitialized();
    final doc = _docs[normalizeMeshPath(path)];
    if (doc == null) return null;
    return LwwMapStrategy.readValue(doc.state, _contentKey);
  }

  @override
  Future<FileOperationResult> deleteFile(
    final String path, {
    final String? commitMessage,
  }) async {
    _ensureInitialized();
    final docPath = normalizeMeshPath(path);
    final doc = _ensureDoc(docPath);
    doc.applyLocal({'k': _contentKey, 'del': true}, DateTime.now());
    await _persist(doc);
    return FileOperationResult(path: docPath, isNew: false);
  }

  @override
  Future<List<FileEntry>> listDirectory(final String directoryPath) async {
    _ensureInitialized();
    final prefix = '${normalizeMeshPath(directoryPath)}/';
    final entries = <FileEntry>[];
    for (final docPath in _docs.keys) {
      if (!docPath.startsWith(prefix)) continue;
      final value = LwwMapStrategy.readValue(_docs[docPath]!.state, _contentKey);
      if (value == null && !_hasLiveValue(_docs[docPath]!)) continue;
      entries.add(FileEntry(name: docPath.substring(prefix.length), isDirectory: false));
    }
    entries.sort((final a, final b) => a.name.compareTo(b.name));
    return entries;
  }

  @override
  Future<void> sync({
    final String? pullMergeStrategy,
    final String? pushConflictStrategy,
  }) async {
    _ensureInitialized();
    final transport = _transport;
    if (transport == null) return; // No peers configured: nothing to do.
    for (final peer in _registry!.peers.toList()) {
      final MeshSession session;
      try {
        session = await transport.connect(peer);
      } on MeshConnectionException {
        continue; // Opportunistic: unreachable peer, try next time.
      }
      try {
        await _runExchange(session);
      } finally {
        await session.close();
      }
    }
  }

  @override
  Future<void> dispose() async {
    _transport?.onIncomingSession = null;
    _transport = null;
    _docs.clear();
    _initialized = false;
  }

  // -- Internals -----------------------------------------------------------

  Future<FileOperationResult> _applyContentOp(
    final String docPath,
    final String content,
    final bool allowNew,
  ) async {
    final doc = _ensureDoc(docPath);
    final hadEntry =
        LwwMapStrategy.readHlc(doc.state, _contentKey) != null ||
        _tombstoneExists(doc);
    final op = doc.applyLocal({'k': _contentKey, 'v': content}, DateTime.now());
    await _persist(doc);
    return FileOperationResult(
      path: docPath,
      revisionId: op.opId,
      isNew: allowNew && !hadEntry,
    );
  }

  bool _hasLiveValue(final ConvergenceDoc doc) =>
      LwwMapStrategy.readValue(doc.state, _contentKey) != null;

  bool _tombstoneExists(final ConvergenceDoc doc) =>
      LwwMapStrategy.readHlc(doc.state, _contentKey) != null &&
      !_hasLiveValue(doc);

  ConvergenceDoc _ensureDoc(final String docPath) => _docs.putIfAbsent(
    docPath,
    () => ConvergenceDoc(
      docId: docPath,
      actorId: _config!.peerId,
    ),
  );

  Future<void> _runExchange(final MeshSession session) async {
    // Symmetric script: both sides send hello+vv, compute deltas, exchange.
    final self = _config!;
    await session.send(
      MeshSyncProtocol.encode(
        MeshSyncProtocol.hello(peerId: self.peerId, displayName: self.displayName),
      ),
    );
    await session.send(
      MeshSyncProtocol.encode(
        MeshSyncProtocol.vv({
          for (final doc in _docs.values) doc.docId: doc.vv,
        }),
      ),
    );

    await _recvOfType(session, MeshSyncProtocol.helloType);
    final peerVvRaw = await _recvOfType(session, MeshSyncProtocol.vvType);
    final peerVv = MeshSyncProtocol.parseVv(peerVvRaw);

    final opsOut = <OpRecord>[];
    final statesOut = <Snapshot>[];
    for (final doc in _docs.values) {
      final theirs = peerVv[doc.docId];
      if (theirs == null) {
        if (doc.pendingOps.isNotEmpty) {
          opsOut.addAll(doc.pendingOps);
        } else {
          statesOut.add(doc.snapshotFor());
        }
      } else {
        final missing = doc.opsSince(theirs);
        if (missing.isNotEmpty) {
          opsOut.addAll(missing);
        } else if (doc.needsSnapshotFor(theirs)) {
          statesOut.add(doc.snapshotFor());
        }
      }
    }
    await session.send(
      MeshSyncProtocol.encode(MeshSyncProtocol.delta(ops: opsOut, states: statesOut)),
    );

    final incoming = MeshSyncProtocol.parseDelta(
      await _recvOfType(session, MeshSyncProtocol.deltaType),
    );
    final touched = <ConvergenceDoc>{};
    final grouped = <String, List<OpRecord>>{};
    for (final op in incoming.ops) {
      grouped.putIfAbsent(op.docId, () => []).add(op);
    }
    grouped.forEach((final docId, final ops) {
      final doc = _ensureDoc(docId);
      doc.applyRemote(ops);
      touched.add(doc);
    });
    for (final snapshot in incoming.states) {
      final doc = _ensureDoc(snapshot.docId);
      if (doc.adoptSnapshot(snapshot)) touched.add(doc);
    }
    for (final doc in touched) {
      await _persist(doc);
    }
  }

  Future<Map<String, Object?>> _recvOfType(
    final MeshSession session,
    final String type,
  ) async {
    Uint8List? lastMismatch;
    await for (final bytes in session.inbound) {
      final message = MeshSyncProtocol.decode(bytes);
      if (message['type'] == type) return message;
      lastMismatch = bytes;
    }
    throw StateError('Session closed while waiting for "$type" '
        '(last unexpected: ${lastMismatch?.length ?? 0} bytes)');
  }

  Future<void> _loadDocs() async {
    await for (final entity in _docsDir!.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final raw =
            jsonDecode(await entity.readAsString()) as Map<dynamic, dynamic>;
        final path = raw['path'] as String;
        _docs[path] = ConvergenceDoc.fromJson(
          Map<String, dynamic>.from(raw['doc'] as Map<dynamic, dynamic>),
        );
      } on FormatException {
        continue; // Corrupt shard: ignore rather than fail startup.
      }
    }
  }

  Future<void> _persist(final ConvergenceDoc doc) async {
    final fileName = encodeDocFileName(doc.docId);
    final file = File('${_docsDir!.path}/$fileName.json');
    await file.writeAsString(
      jsonEncode({'path': doc.docId, 'doc': doc.toJson()}),
    );
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw const ConfigurationException(
        'MeshStorageProvider used before initWithConfig.',
      );
    }
  }
}
