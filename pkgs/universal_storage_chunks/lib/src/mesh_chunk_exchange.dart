import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';

import 'chunk_store.dart';

/// Chunk frames over an established [MeshSession] (ADR 0042 §3).
///
/// Manifests travel as kernel ops through the normal sync; the bytes move
/// HERE, lazily, per chunk — the "separate lazy channel". Proof of
/// possession on the wire is the hash check itself: a chunk is adopted
/// only when the received bytes hash to the requested address, so a peer
/// that knows a hash but not the bytes cannot make a replica accept or
/// skip anything.
///
/// Frames (JSON, additive to the ADR 0010 family but spoken only on
/// sessions the caller opens for chunk work):
/// - `chunk-req {v, addresses: [...]}` — what the fetcher lacks.
/// - `chunk {v, address, bytes(base64)}` — one verified chunk, sent as an
///   answer OR pushed unsolicited (the pull/push pairing below).
/// - `chunk-end {v, missing: [...]}` — a request answered (these
///   addresses the server does not hold), or a push finished.
///
/// The session is BIDIRECTIONAL: [serve] answers `chunk-req` and also
/// ABSORBS unsolicited `chunk` frames (verified, stored) — the topology
/// where only one side can dial (e.g. a phone pushing captures to the
/// desktop that hosts) needs no second server.
final class MeshChunkExchange {
  const MeshChunkExchange._();

  static const reqType = 'chunk-req';
  static const chunkType = 'chunk';
  static const endType = 'chunk-end';

  /// Requests [addresses] over [session] and sinks verified chunks into
  /// [sink]. Returns the number of chunks received; addresses the peer
  /// lacked are simply absent (retry against another peer later).
  ///
  /// Batches the request so a huge gap set doesn't build an unbounded
  /// frame; [batchSize] addresses go out per request.
  static Future<int> fetch({
    required final MeshSession session,
    required final Iterable<String> addresses,
    required final ChunkStore sink,
    final int batchSize = 64,
  }) async {
    final queue = addresses.where((final a) => a.isNotEmpty).toList();
    var received = 0;
    final inbound = StreamIterator<Uint8List>(session.inbound);
    for (var i = 0; i < queue.length; i += batchSize) {
      final batch = queue.sublist(
        i,
        (i + batchSize) < queue.length ? i + batchSize : queue.length,
      );
      await session.send(
        _encode({'v': 1, 'type': reqType, 'addresses': batch}),
      );
      // Read this batch's answer: chunks until chunk-end.
      var done = false;
      while (!done && await inbound.moveNext()) {
        final message = MeshChunkProtocol.decode(inbound.current);
        switch (message['type']) {
          case chunkType:
            final address = message['address'] as String?;
            final raw = message['bytes'] as String?;
            if (address == null || raw == null) continue;
            final bytes = base64Decode(raw);
            // Proof of possession: adopt only what hashes to the address.
            if (chunkAddress(bytes) != address) continue;
            await sink.put(bytes, address: address);
            received++;
          case endType:
            done = true;
        }
      }
    }
    await inbound.cancel();
    return received;
  }

  /// Pushes every chunk of [addresses] the [store] holds to the peer as
  /// UNSOLICITED verified chunks, then signals with `chunk-end`. The
  /// receiver ([serve]) adopts each only if the bytes hash to the
  /// address. Returns the number of chunks sent. This is how a
  /// dialer-only topology ships bytes: the phone dials one session and
  /// pushes; no second server ever exists.
  static Future<int> push({
    required final MeshSession session,
    required final Iterable<String> addresses,
    required final ChunkStore store,
    final int batchSize = 16,
  }) async {
    var sent = 0;
    final queue = addresses.where((final a) => a.isNotEmpty).toList();
    for (var i = 0; i < queue.length; i += batchSize) {
      final batch = queue.sublist(
        i,
        (i + batchSize) < queue.length ? i + batchSize : queue.length,
      );
      for (final address in batch) {
        final bytes = await store.get(address);
        if (bytes == null) continue; // Push what we hold; gaps stay gaps.
        await session.send(
          _encode({
            'v': 1,
            'type': chunkType,
            'address': address,
            'bytes': base64Encode(bytes),
          }),
        );
        sent++;
      }
    }
    await session.send(_encode({'v': 1, 'type': endType, 'missing': const []}));
    return sent;
  }

  /// Serves the peer's requests from [store] until they close the
  /// session: one answer (chunks + chunk-end) per received request.
  /// UNSOLICITED `chunk` frames are absorbed on the same session (hash
  /// verified before storing — the PoP law holds for pushes too).
  /// Returns when the inbound stream closes (the peer is done).
  static Future<void> serve({
    required final MeshSession session,
    required final ChunkStore store,
  }) async {
    await for (final frame in session.inbound) {
      final message = MeshChunkProtocol.decode(frame);
      switch (message['type']) {
        case reqType:
          final addresses =
              (message['addresses'] as List<dynamic>? ?? const [])
                  .whereType<String>();
          final missing = <String>[];
          for (final address in addresses) {
            final bytes = await store.get(address);
            if (bytes == null) {
              missing.add(address);
              continue;
            }
            await session.send(
              _encode({
                'v': 1,
                'type': chunkType,
                'address': address,
                'bytes': base64Encode(bytes),
              }),
            );
          }
          await session.send(
            _encode({'v': 1, 'type': endType, 'missing': missing}),
          );
        case chunkType:
          final address = message['address'] as String?;
          final raw = message['bytes'] as String?;
          if (address == null || raw == null) continue;
          final bytes = base64Decode(raw);
          if (chunkAddress(bytes) != address) continue;
          await store.put(bytes, address: address);
      }
    }
  }
}

/// JSON codec for the chunk frame family.
final class MeshChunkProtocol {
  const MeshChunkProtocol._();

  static Uint8List encode(final Map<String, Object?> message) =>
      Uint8List.fromList(utf8.encode(jsonEncode(message)));

  static Map<String, Object?> decode(final Uint8List bytes) =>
      Map<String, Object?>.from(
        jsonDecode(utf8.decode(bytes)) as Map<dynamic, dynamic>,
      );
}

Uint8List _encode(final Map<String, Object?> message) =>
    MeshChunkProtocol.encode(message);
