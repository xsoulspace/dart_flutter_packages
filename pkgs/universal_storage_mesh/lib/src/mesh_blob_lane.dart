import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:universal_storage_chunks/universal_storage_chunks.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';
import 'package:universal_storage_world/universal_storage_world.dart';

import 'mesh_sync_protocol.dart';

/// The binary-member lane (ADR 0042 §3 + ADR 0049): manifests travel as
/// ordinary kernel members through the normal sync; the BYTES move here —
/// content-addressed chunks over dedicated sessions, hash-verified before
/// anything is stored.
///
/// Topology law: the lane is DIALER-SYMMETRIC. A fetcher dials a peer and
/// requests its gaps ([fetchFrom]); a producer dials a peer and PUSHES
/// what it holds ([pushTo]) — this is how a dialer-only topology (a phone
/// pushing captures to the desktop that hosts the only server) ships
/// bytes with no second server. [attachTransport] consumes the claimed
/// blob plane on the hosting side and serves requests AND absorbs pushes
/// on the same session.
///
/// The lane never interprets content: callers choose docIds and mime
/// types; the catalog entry ([catalogEntryFor]) carries the manifest's
/// shape (root/size/chunk count) as census metadata so a peer can decide
/// to fetch BEFORE opening anything (you cannot warm what you cannot
/// enumerate).
final class MeshBlobLane {
  MeshBlobLane({
    required final StorageService storage,
    required final ChunkedBlobStore blobs,
    this.onPublished,
    this.onUnpublished,
  }) : _storage = storage,
       _blobs = blobs;

  final StorageService _storage;
  final ChunkedBlobStore _blobs;

  /// Fired after [publish] so the embedding participant can carry the
  /// manifest in its zone census.
  final void Function(String docId, ZoneMemberEntry entry)? onPublished;

  /// Fired after [unpublish] so the census drops the entry (and the next
  /// flush tombstones the manifest member).
  final void Function(String docId)? onUnpublished;

  final List<StreamSubscription<MeshSession>> _serving = [];

  /// The content-addressed store (fetch/serve/push all speak in
  /// addresses).
  ChunkStore get chunks => _blobs.chunks;

  /// The blob facade over that store (materialization for consumers).
  ChunkedBlobStore get blobs => _blobs;

  /// Consumes the CLAIMED blob plane of a claiming wrapper: every inbound
  /// session is chunk work; [MeshChunkExchange.serve] answers requests
  /// and absorbs unsolicited pushes until the peer closes the session.
  void attachTransport(final MeshTransport blobPlane) {
    _serving.add(
      blobPlane.incoming.listen((final session) async {
        try {
          await MeshChunkExchange.serve(session: session, store: _blobs.chunks);
        } on Object {
          // A malformed frame kills the session, never the lane; the
          // peer may retry on a fresh dial.
        } finally {
          await session.close();
        }
      }),
    );
  }

  /// Splits [bytes] into content-addressed chunks, stores them locally,
  /// and writes the manifest as the member [docId]'s content register —
  /// from there the ordinary sync ships the reference like any member.
  Future<ChunkManifest> publish(
    final String docId,
    final List<int> bytes, {
    final String? mime,
  }) async {
    final manifest = await _blobs.putBytes(bytes, mime: mime);
    await _storage.saveFile(docId, jsonEncode(manifest.toJson()));
    onPublished?.call(docId, catalogEntryFor(docId, manifest));
    return manifest;
  }

  /// Tombstones the manifest member (the chunks stay — the store is
  /// immutable and possibly shared; collection is a separate policy).
  Future<void> unpublish(final String docId) async {
    await _storage.removeFile(docId);
    onUnpublished?.call(docId);
  }

  /// The manifest stored at [docId], null when the member is absent or
  /// its content is not a manifest.
  Future<ChunkManifest?> manifestOf(final String docId) async {
    final raw = await _storage.readFile(docId);
    if (raw == null) return null;
    try {
      return ChunkManifest.tryFromJson(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  /// The census entry for a published blob: kind `blob`, manifest shape
  /// as meta (a peer can warm the first chunk — the preview — from this
  /// alone, before any session opens).
  static ZoneMemberEntry catalogEntryFor(
    final String docId,
    final ChunkManifest manifest, {
    final String? title,
  }) => ZoneMemberEntry(
    docId: docId,
    kind: 'blob',
    title: title,
    meta: {
      'root': manifest.root,
      'size': manifest.size,
      'chunks': manifest.chunks.length,
      if (manifest.mime != null) 'mime': manifest.mime,
    },
  );

  /// Fetches every chunk of [docId]'s manifest that the local store lacks
  /// from [peer] over a FRESH session ([dial] — the lane does not keep
  /// sessions), verifying each on receipt, then materializes the whole
  /// content (root-checked). Throws [MissingChunksException] listing the
  /// addresses the peer lacked — retry against another peer or pulse.
  Future<Uint8List> fetchFrom(
    final String docId, {
    required final MeshTransport dial,
    required final MeshPeerRecord peer,
    final void Function(int fetched, int total)? onProgress,
  }) async {
    final manifest = await manifestOf(docId);
    if (manifest == null) {
      throw StateError('no manifest member at $docId (sync it first)');
    }
    final missing = await manifest.missingChunks(_blobs.chunks);
    if (missing.isNotEmpty) {
      final session = await dial.connect(peer);
      var fetched = 0;
      try {
        fetched = await MeshChunkExchange.fetch(
          session: session,
          addresses: missing,
          sink: _blobs.chunks,
        );
      } finally {
        await session.close();
      }
      onProgress?.call(fetched, manifest.chunks.length);
    }
    return _blobs.getBytes(manifest);
  }

  /// Pushes every chunk of [docId]'s manifest this store HOLDS to [peer]
  /// over a fresh session (the receiver absorbs them hash-verified).
  /// Returns the number of chunks sent; gaps stay gaps (the receiver may
  /// fetch them elsewhere). This is the producer half of the
  /// dialer-only topology.
  Future<int> pushTo(
    final String docId, {
    required final MeshTransport dial,
    required final MeshPeerRecord peer,
  }) async {
    final manifest = await manifestOf(docId);
    if (manifest == null) {
      throw StateError('no manifest member at $docId (publish it first)');
    }
    final session = await dial.connect(peer);
    try {
      final sent = await MeshChunkExchange.push(
        session: session,
        addresses: manifest.chunks,
        store: _blobs.chunks,
      );
      return sent;
    } finally {
      await session.close();
    }
  }
}

/// Byte-level plane classifier (ADR 0047 "one server, two planes"):
/// whether a first inbound frame declares the BLOB plane — a
/// `chunk-req` (fetch) or an unsolicited `chunk` (push).
bool looksLikeChunkFrame(final Uint8List frame) {
  return meshFrameTypeIs(frame, const {
    MeshChunkExchange.reqType,
    MeshChunkExchange.chunkType,
  });
}
