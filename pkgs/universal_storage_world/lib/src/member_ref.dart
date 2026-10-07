import 'package:universal_storage_convergence/universal_storage_convergence.dart';

/// Everything the world layer knows about one member of a zone (ADR 0047
/// §2): its identity and its convergence watermark. Content lives in kernel
/// docs behind a [MemberCodec]; a member ref is what catalogs, prefetch
/// plans, and subscriptions exchange. Never the content itself.
final class WorldMemberRef {
  const WorldMemberRef({required this.docId, required this.version});

  /// Storage/kernel identity (the wire truth since ADR 0010).
  final String docId;

  /// The member's version vector at observation time — what a warm-up or
  /// resume compares against (`opsSince` on the kernel).
  final VersionVector version;

  Map<String, Object?> toJson() => {'docId': docId, 'vv': version.toJson()};

  static WorldMemberRef fromJson(final Map<String, Object?> json) =>
      WorldMemberRef(
        docId: json['docId']! as String,
        version: VersionVector.fromJson(
          Map<String, dynamic>.from(json['vv']! as Map<dynamic, dynamic>),
        ),
      );

  @override
  bool operator ==(final Object other) =>
      other is WorldMemberRef &&
      other.docId == docId &&
      other.version == version;

  @override
  int get hashCode => Object.hash(docId, version);

  @override
  String toString() => 'WorldMemberRef($docId@${version.toJson()})';
}
