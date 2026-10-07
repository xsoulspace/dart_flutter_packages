import 'package:universal_storage_convergence/universal_storage_convergence.dart';

/// The app-agnostic seam between ONE member kind and kernel doc state
/// (ADR 0047 §3): documents, whole files, game entities, and harness beats
/// are all just members; each domain brings its own codec and the
/// provider/session layer stays generic.
///
/// The kernel stays byte-blind (ADR 0011): codecs speak the LWW-map op
/// shape (`{'k': key, 'v': value}` / `{'k': key, 'del': true}`) and own
/// which registers their kind uses. A game entity codec writes one op per
/// component field; the harness beat codec writes one per beat field; the
/// file codec writes a single `content` register — the pre-0047 wire
/// semantics, unchanged.
abstract interface class MemberCodec {
  /// Stable kind id for diagnostics and wire metadata.
  String get kind;

  /// Whether [doc] has ever carried this member kind, tombstones included
  /// (drives `isNew` semantics on the storage contract).
  bool wasWritten(final ConvergenceDoc doc);

  /// Whether [doc] currently holds a live value (listability).
  bool hasLiveValue(final ConvergenceDoc doc);

  /// The member's current payload, null when absent or tombstoned.
  Object? readValue(final ConvergenceDoc doc);

  /// Kernel ops encoding a write of [value], in application order. The
  /// LAST op's id becomes the storage revision.
  List<Map<String, Object?>> writeOps(final Object? value);

  /// Kernel ops encoding a delete (tombstone).
  List<Map<String, Object?>> deleteOps();
}

/// The file-shaped default: one LWW register per member (ADR 0010 §5).
///
/// Reproduces [MeshStorageProvider]'s original single-`content` register
/// semantics exactly — same ops, same wire bytes, same storage JSON — so
/// adopting the codec seam is behavior-neutral for every existing replica.
final class SingleFieldMemberCodec implements MemberCodec {
  const SingleFieldMemberCodec({
    this.registerKey = 'content',
    this.kind = 'file',
  });

  /// The one LWW register this member kind lives in.
  final String registerKey;

  @override
  final String kind;

  @override
  bool wasWritten(final ConvergenceDoc doc) =>
      LwwMapStrategy.readHlc(doc.state, registerKey) != null;

  @override
  bool hasLiveValue(final ConvergenceDoc doc) =>
      LwwMapStrategy.readValue(doc.state, registerKey) != null;

  @override
  Object? readValue(final ConvergenceDoc doc) =>
      LwwMapStrategy.readValue(doc.state, registerKey);

  @override
  List<Map<String, Object?>> writeOps(final Object? value) => [
    {'k': registerKey, 'v': value},
  ];

  @override
  List<Map<String, Object?>> deleteOps() => [
    {'k': registerKey, 'del': true},
  ];
}
