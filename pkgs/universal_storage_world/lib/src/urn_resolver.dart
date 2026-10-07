import 'world_urn.dart';

/// Translates between member docIds (the storage/kernel truth) and
/// [WorldUrn]s (the naming layer) — ADR 0047 §2.
///
/// The wire and every store key remain bare docIds; the resolver is pure
/// naming. Games may namespace by save/world id; the harness by workspace
/// id; nobody is forced to.
abstract interface class UrnResolver {
  WorldUrn urnForDoc(final String docId, {final String? worldId});

  /// The docId a URN addresses, or null when this resolver does not own
  /// the urn's world.
  String? docIdForUrn(final WorldUrn urn);
}

/// Identity mapping: `memberPath == docId`. The default, preserving every
/// existing wire/storage format byte-for-byte (ADR 0047 §2 back-compat
/// law).
final class PathUrnResolver implements UrnResolver {
  const PathUrnResolver({this.defaultWorldId = 'local'});

  final String defaultWorldId;

  @override
  WorldUrn urnForDoc(final String docId, {final String? worldId}) => WorldUrn(
    worldId: worldId ?? defaultWorldId,
    memberPath: docId,
  );

  @override
  String? docIdForUrn(final WorldUrn urn) => urn.memberPath;
}
