import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:meta/meta.dart';

/// sha256 of [bytes], hex-encoded — the chunk address (ADR 0042 §1).
String chunkAddress(final List<int> bytes) {
  final digest = Sha256().toSync().hashSync(bytes);
  return digest.bytes.map((final b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// An immutable, content-addressed chunk store (ADR 0042 §1).
///
/// Additive by law: chunks are addressed by their own bytes, so stores
/// converge by SET UNION across replicas — no conflict logic below the
/// manifest. `put` of an existing address is a no-op (idempotent).
abstract interface class ChunkStore {
  /// Stores [bytes] under `chunkAddress(bytes)`. Idempotent.
  Future<void> put(final List<int> bytes, {required final String address});

  Future<bool> has(final String address);

  /// The stored bytes, null when absent. A stored chunk whose bytes do
  /// NOT hash to [address] must never be returned (corruption is
  /// reported as absent).
  Future<Uint8List?> get(final String address);
}

/// In-memory store — tests and hot caches.
final class MemoryChunkStore implements ChunkStore {
  final _chunks = <String, Uint8List>{};

  /// How many distinct addresses were written (dedup observability).
  int get length => _chunks.length;

  @override
  Future<void> put(final List<int> bytes, {required final String address}) async {
    if (_chunks.containsKey(address)) return; // idempotent
    _chunks[address] = Uint8List.fromList(bytes);
  }

  @override
  Future<bool> has(final String address) async => _chunks.containsKey(address);

  @override
  Future<Uint8List?> get(final String address) async {
    final bytes = _chunks[address];
    if (bytes == null) return null;
    // Never serve bytes that don't hash to their address.
    return chunkAddress(bytes) == address ? bytes : null;
  }
}

/// File-backed store: `<root>/<address[0:2]>/<address>.chunk`, written
/// atomically (temp file + rename) so a crash mid-`put` leaves no partial
/// chunk visible (ADR 0042 §4 conformance: crash mid-upload is safe).
final class FileChunkStore implements ChunkStore {
  FileChunkStore(this.root);

  final String root;

  File _fileFor(final String address) => File(
    '$root${Platform.pathSeparator}${address.substring(0, 2)}'
    '${Platform.pathSeparator}$address.chunk',
  );

  @override
  Future<void> put(final List<int> bytes, {required final String address}) async {
    final file = _fileFor(address);
    if (file.existsSync()) return; // idempotent: chunks are immutable
    await file.parent.create(recursive: true);
    final temp = File(
      '${file.path}.tmp-${DateTime.now().microsecondsSinceEpoch}',
    );
    await temp.writeAsBytes(bytes, flush: true);
    try {
      await temp.rename(file.path);
    } on FileSystemException {
      // Concurrent put of the same chunk: the winner renamed first.
      await temp.deleteIgnoreMissing();
      if (!file.existsSync()) rethrow;
    }
  }

  @override
  Future<bool> has(final String address) async => _fileFor(address).existsSync();

  @override
  Future<Uint8List?> get(final String address) async {
    final file = _fileFor(address);
    if (!file.existsSync()) return null;
    final bytes = await file.readAsBytes();
    // Never serve bytes that don't hash to their address — a torn write
    // (crash before rename is impossible with rename, but disk rot is
    // not) reports as absent, exactly like a missing peer chunk.
    return chunkAddress(bytes) == address ? bytes : null;
  }
}

@visibleForTesting
extension _DeleteIgnore on File {
  Future<void> deleteIgnoreMissing() async {
    try {
      await delete();
    } on FileSystemException {
      // Already gone.
    }
  }
}
