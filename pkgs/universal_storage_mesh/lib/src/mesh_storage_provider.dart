import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:universal_storage_convergence/universal_storage_convergence.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';
import 'package:universal_storage_world/universal_storage_world.dart';

import 'mesh_kv_store.dart';
import 'mesh_kv_store_factory.dart'
    if (dart.library.js_interop) 'mesh_kv_store_web.dart'
    if (dart.library.io) 'mesh_kv_store_io.dart';
import 'mesh_path_utils.dart';
import 'mesh_peer_registry.dart';
import 'mesh_sync_protocol.dart';

/// Serverless P2P storage provider (ADR 0010).
///
/// - Local reads/writes never touch the network; every replica's local
///   store is authoritative for latency.
/// - Each stored member is one convergence document whose content ↔ op
///   mapping is owned by a [MemberCodec] (ADR 0047 §3; the default
///   [SingleFieldMemberCodec] reproduces the original single-`content`
///   register semantics exactly).
/// - [sync] runs symmetric anti-entropy sessions over the attached
///   [MeshTransport]; unreachable peers are skipped silently — sync is
///   opportunistic, manual-trigger friendly, and never blocks local work.
/// - Interest management (ADR 0048): each side publishes an
///   [InterestSelection] every exchange; the peer's selection gates what
///   we announce and send them, ours gates what they send us. No
///   subscription frame (older peer) means the wildcard — full delivery.
final class MeshStorageProvider implements StorageProvider {
  /// Overrides the platform-selected persistence backing. Production
  /// builds pick the backing via compile-time conditional import (file
  /// backed under `dart:io`, `localStorage`-backed on web); tests inject
  /// a store directly to exercise web semantics on the VM.
  MeshStorageProvider({
    final MemberCodec? memberCodec,
    final UrnResolver? urnResolver,
    @visibleForTesting this._kvStoreFactory,
  }) : _memberCodec = memberCodec ?? const SingleFieldMemberCodec(),
       _urnResolver = urnResolver ?? const PathUrnResolver();

  final MeshKeyValueStore Function(String root)? _kvStoreFactory;

  /// How this provider's member content maps to kernel doc state
  /// (ADR 0047 §3). Default: the file-shaped single-register codec.
  final MemberCodec _memberCodec;

  /// docId ↔ [WorldUrn] naming (ADR 0047 §2). Default: identity.
  final UrnResolver _urnResolver;

  /// The member kind this replica stores (from its codec).
  String get memberKind => _memberCodec.kind;

  /// World-model naming for [docId] (pure naming layer; the wire and store
  /// keys stay bare docIds).
  WorldUrn urnOf(final String docId) => _urnResolver.urnForDoc(docId);

  /// World-model refs of every LIVE local member — catalog and warm-plan
  /// raw material (ADR 0047 §2).
  Iterable<WorldMemberRef> memberRefs() sync* {
    for (final doc in _docs.values) {
      if (_memberCodec.hasLiveValue(doc)) {
        yield WorldMemberRef(docId: doc.docId, version: doc.vv);
      }
    }
  }

  MeshKeyValueStore? _store;
  MeshStorageConfig? _config;
  MeshPeerRegistry? _registry;
  var _inMemory = false;
  final List<MeshTransport> _transports = [];
  final List<StreamSubscription<MeshSession>> _incomingSubscriptions = [];
  final Map<String, ConvergenceDoc> _docs = {};
  var _initialized = false;

  // -- Interest management (ADR 0048) --------------------------------------

  /// What WE want delivered; null = the wildcard. Published in every
  /// exchange's `sub` frame.
  InterestSelection? _interest;

  /// Receiver-expressed ordering: docId → rank (ascending = delivered
  /// first). We honor the PEER's map when building their delta.
  Map<String, int> _deliveryPriority = const {};

  /// The cap WE ask peers to honor when sending to us (published in our
  /// sub frame); null = unlimited.
  int? _incomingBudget;

  /// Delivery rank for members the peer did not rank: after all ranked
  /// ones, deterministically by docId.
  static const _unrankedDeliveryRank = 1 << 30;

  /// Publishes what this replica wants DELIVERED (ADR 0048 §2), resolved
  /// from [policy] immediately. Re-set before every pulse — policies are
  /// per-cycle resolvers (movement between zones re-subscribes without
  /// protocol change). Null clears back to the wildcard.
  void setInterest(final InterestPolicy? policy) =>
      _interest = policy?.resolve();

  /// Receiver-expressed delivery preference for the NEXT exchanges: the
  /// peer sends these docIds' ops first (ascending rank). Optional;
  /// unranked members follow deterministically after.
  void setDeliveryPriority(final Map<String, int> priority) =>
      _deliveryPriority = Map.unmodifiable(priority);

  /// Asks peers to cap their delta to [maxOps] ops per exchange
  /// (backpressure-lite: the remainder arrives on a later pulse). Null =
  /// unlimited (the default, and the pre-0048 behavior).
  void setIncomingBudget(final int? maxOps) => _incomingBudget = maxOps;

  /// Registers a transport for this replica and wires inbound sessions.
  /// Call once per transport after [initWithConfig]; a replica may hold
  /// several transports simultaneously (e.g. LAN + BLE).
  void attachTransport(final MeshTransport transport) {
    _transports.add(transport);
    _incomingSubscriptions.add(
      transport.incoming.listen((final session) async {
        try {
          await _runExchange(session);
        } finally {
          await session.close();
        }
      }),
    );
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
    _inMemory = config.storePath == ':memory:';
    if (_inMemory) {
      _config = config;
      _registry = MeshPeerRegistry.inMemory();
      _initialized = true;
      return;
    }
    // Persistence backing is selected per platform: file-backed under
    // dart:io (storePath is a real directory), `localStorage`-backed on
    // web (storePath is only a namespace and is never used as a path).
    _store =
        _kvStoreFactory?.call(config.storePath) ??
        createMeshKvStore(config.storePath);
    _config = config;
    _registry = await MeshPeerRegistry.loadFromStore(
      store: _store!,
      key: 'peers.json',
      filePath: '${config.storePath}/peers.json',
    );
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
    return _applyContentOp(normalizeMeshPath(path), content, true);
  }

  @override
  Future<FileOperationResult> updateFile(
    final String path,
    final String content, {
    final String? commitMessage,
  }) async {
    _ensureInitialized();
    return _applyContentOp(normalizeMeshPath(path), content, false);
  }

  @override
  Future<String?> getFile(final String path) async {
    _ensureInitialized();
    final doc = _docs[normalizeMeshPath(path)];
    if (doc == null) return null;
    return _memberCodec.readValue(doc) as String?;
  }

  @override
  Future<FileOperationResult> deleteFile(
    final String path, {
    final String? commitMessage,
  }) async {
    _ensureInitialized();
    final docPath = normalizeMeshPath(path);
    final doc = _ensureDoc(docPath);
    for (final op in _memberCodec.deleteOps()) {
      doc.applyLocal(op, DateTime.now());
    }
    await _persist(doc);
    return FileOperationResult(path: docPath);
  }

  @override
  Future<List<FileEntry>> listDirectory(final String directoryPath) async {
    _ensureInitialized();
    final prefix = '${normalizeMeshPath(directoryPath)}/';
    final entries = <FileEntry>[];
    for (final docPath in _docs.keys) {
      if (!docPath.startsWith(prefix)) continue;
      final doc = _docs[docPath]!;
      final value = _memberCodec.readValue(doc);
      if (value == null && !_memberCodec.hasLiveValue(doc)) continue;
      entries.add(
        FileEntry(name: docPath.substring(prefix.length), isDirectory: false),
      );
    }
    entries.sort((final a, final b) => a.name.compareTo(b.name));
    return entries;
  }

  @override
  Future<void> restore(final String path, {final String? versionId}) async {
    throw const UnsupportedOperationException(
      'Mesh replicas have no version history; restore is not supported.',
    );
  }

  @override
  Future<void> sync({
    final String? pullMergeStrategy,
    final String? pushConflictStrategy,
  }) async {
    _ensureInitialized();
    if (_transports.isEmpty) return; // No transports: nothing to do.
    for (final peer in _registry!.peers.toList()) {
      MeshSession? session;
      for (final transport in _transports) {
        try {
          session = await transport.connect(peer);
          break;
        } on MeshConnectionException {
          continue; // Try the next transport for this peer.
        }
      }
      if (session == null) {
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
    for (final sub in _incomingSubscriptions) {
      await sub.cancel();
    }
    _incomingSubscriptions.clear();
    _transports.clear();
    _docs.clear();
    _store = null;
    _initialized = false;
  }

  /// Compacts every local document (retires pending op logs, keeping the
  /// folded state as the snapshot). Policy-driven at the app layer per
  /// ADR 0011 §1; lagging peers catch up via snapshots afterwards.
  Future<void> compactAll() async {
    _ensureInitialized();
    for (final doc in _docs.values) {
      if (doc.compact() > 0) {
        await _persist(doc);
      }
    }
  }

  // -- Internals -----------------------------------------------------------

  Future<FileOperationResult> _applyContentOp(
    final String docPath,
    final String content,
    final bool allowNew,
  ) async {
    final doc = _ensureDoc(docPath);
    final hadEntry = _memberCodec.wasWritten(doc);
    OpRecord? lastOp;
    for (final op in _memberCodec.writeOps(content)) {
      lastOp = doc.applyLocal(op, DateTime.now());
    }
    await _persist(doc);
    return FileOperationResult(
      path: docPath,
      revisionId: lastOp?.opId ?? '',
      isNew: allowNew && !hadEntry,
    );
  }

  ConvergenceDoc _ensureDoc(final String docPath) => _docs.putIfAbsent(
    docPath,
    () => ConvergenceDoc(docId: docPath, actorId: _config!.peerId),
  );

  Future<void> _runExchange(final MeshSession session) async {
    // Symmetric script (ADR 0010 §4 + ADR 0048 §2): both sides send
    // hello + sub + vv, compute deltas, exchange, close.
    //
    // The `sub` frame publishes what each side wants DELIVERED; the
    // peer's selection gates our DELTA (the semantics). The vv stays
    // unfiltered and goes out immediately — no handshake round-trip on
    // the critical path, and a pre-0048 peer (which sends no sub) simply
    // skips the unknown frame type while waiting for the vv, exactly as
    // it always has.
    final self = _config!;
    await session.send(
      MeshSyncProtocol.encode(
        MeshSyncProtocol.hello(
          peerId: self.peerId,
          displayName: self.displayName,
        ),
      ),
    );
    await session.send(
      MeshSyncProtocol.encode(
        MeshSyncProtocol.sub(
          selection: _interest ?? const InterestSelection.all(),
          priority: _deliveryPriority,
          budget: _incomingBudget,
        ),
      ),
    );
    await session.send(
      MeshSyncProtocol.encode(
        MeshSyncProtocol.vv({
          for (final doc in _docs.values) doc.docId: doc.vv,
        }),
      ),
    );

    final inbound = StreamIterator<Uint8List>(session.inbound);
    await _recvOfType(inbound, MeshSyncProtocol.helloType);

    // Consume the peer's optional `sub` (pre-0048 peers skip it) and
    // their vv. Absent sub = wildcard (full delivery, old behavior).
    var selection = const InterestSelection.all();
    var priority = const <String, int>{};
    int? budget;
    Map<String, VersionVector>? peerVv;
    while (peerVv == null && await inbound.moveNext()) {
      final message = MeshSyncProtocol.decode(inbound.current);
      switch (message['type']) {
        case MeshSyncProtocol.subType:
          final parsed = MeshSyncProtocol.parseSub(message);
          selection = parsed.selection;
          priority = parsed.priority;
          budget = parsed.budget;
        case MeshSyncProtocol.vvType:
          peerVv = MeshSyncProtocol.parseVv(message);
      }
    }
    if (peerVv == null) {
      throw StateError('Session closed while waiting for "vv"');
    }

    // Our outgoing delta: gate = peer selection, order = peer priority,
    // cap = peer budget (receiver-expressed, like the game relevancy
    // filter). Unranked members follow in deterministic docId order.
    final wanted =
        _docs.values
            .where((final doc) => selection.matchesDocId(doc.docId))
            .toList()
          ..sort((final a, final b) {
            final rankA = priority[a.docId] ?? _unrankedDeliveryRank;
            final rankB = priority[b.docId] ?? _unrankedDeliveryRank;
            if (rankA != rankB) return rankA.compareTo(rankB);
            return a.docId.compareTo(b.docId);
          });
    final opsOut = <OpRecord>[];
    final statesOut = <Snapshot>[];
    for (final doc in wanted) {
      if (budget != null && opsOut.length >= budget) break;
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
      MeshSyncProtocol.encode(
        MeshSyncProtocol.delta(ops: opsOut, states: statesOut),
      ),
    );

    final incoming = MeshSyncProtocol.parseDelta(
      await _recvOfType(inbound, MeshSyncProtocol.deltaType),
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

    await inbound.cancel();
  }

  Future<Map<String, Object?>> _recvOfType(
    final StreamIterator<Uint8List> inbound,
    final String type,
  ) async {
    Uint8List? lastMismatch;
    while (await inbound.moveNext()) {
      final bytes = inbound.current;
      final message = MeshSyncProtocol.decode(bytes);
      if (message['type'] == type) return message;
      lastMismatch = bytes;
    }
    throw StateError(
      'Session closed while waiting for "$type" '
      '(last unexpected: ${lastMismatch?.length ?? 0} bytes)',
    );
  }

  Future<void> _loadDocs() async {
    if (_inMemory) return;
    for (final key in await _store!.list('docs')) {
      if (!key.endsWith('.json')) continue;
      final content = await _store!.read(key);
      if (content == null) continue;
      try {
        final raw = jsonDecode(content) as Map<dynamic, dynamic>;
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
    if (_inMemory) return;
    final store = _store;
    // An inbound exchange may still be finishing while dispose() runs —
    // persisting is then moot, never a crash.
    if (store == null) return;
    final fileName = encodeDocFileName(doc.docId);
    await store.write(
      'docs/$fileName.json',
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
