import 'package:universal_storage_convergence/universal_storage_convergence.dart';

/// One entry in a zone census (ADR 0047 §2): what a client needs to warm a
/// member BEFORE opening it — identity, human title, kind, and whatever
/// metadata the domain attaches (blob manifests, sizes, preview hints).
final class ZoneMemberEntry {
  const ZoneMemberEntry({
    required this.docId,
    this.title,
    this.kind,
    this.meta = const {},
  });

  /// Storage/kernel identity of the member.
  final String docId;

  /// Human title for placeholder ("HLOD") rendering while content warms.
  final String? title;

  /// Domain kind tag — `'chat'`, `'doc'`, `'code'`, `'blob'`, `'entity'`.
  /// The world layer never interprets it.
  final String? kind;

  /// Domain metadata (blob manifests, byte sizes, preview hints).
  final Map<String, Object?> meta;

  Map<String, Object?> toJson() => {
    'docId': docId,
    if (title != null) 'title': title,
    if (kind != null) 'kind': kind,
    if (meta.isNotEmpty) 'meta': meta,
  };

  static ZoneMemberEntry fromJson(final Map<String, Object?> json) =>
      ZoneMemberEntry(
        docId: json['docId']! as String,
        title: json['title'] as String?,
        kind: json['kind'] as String?,
        meta: Map<String, Object?>.from(
          json['meta'] as Map<dynamic, dynamic>? ?? const {},
        ),
      );

  @override
  bool operator ==(final Object other) =>
      other is ZoneMemberEntry &&
      other.docId == docId &&
      other.title == title &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(docId, title, kind);
}

/// The zone census: an ordinary kernel doc's value (one LWW-map register),
/// shipped by the existing anti-entropy like any member — the game "zone
/// map" that makes prefetch POSSIBLE (you cannot warm what you cannot
/// enumerate; ADR 0047 §2). Subscribing to a zone's catalog first, then
/// warming its members, is the whole border-crossing choreography.
final class ZoneCatalog {
  const ZoneCatalog({required this.zoneId, this.title, this.entries = const []});

  /// Stable id of the zone this census describes.
  final String zoneId;

  /// Human title of the zone.
  final String? title;

  /// The members of the zone.
  final List<ZoneMemberEntry> entries;

  /// The member docIds in this census — a warm-up plan's raw material.
  Set<String> memberDocIds() =>
      entries.map((final entry) => entry.docId).toSet();

  Map<String, Object?> toJson() => {
    'zoneId': zoneId,
    if (title != null) 'title': title,
    'entries': [for (final entry in entries) entry.toJson()],
  };

  static ZoneCatalog fromJson(final Map<String, Object?> json) => ZoneCatalog(
    zoneId: json['zoneId']! as String,
    title: json['title'] as String?,
    entries: (json['entries'] as List<dynamic>? ?? const [])
        .whereType<Map<dynamic, dynamic>>()
        .map((final e) => ZoneMemberEntry.fromJson(Map<String, Object?>.from(e)))
        .toList(),
  );

  @override
  String toString() =>
      'ZoneCatalog($zoneId, ${entries.length} members)';
}

/// Encodes/decodes a [ZoneCatalog] as one kernel register value.
///
/// The catalog doc is just a member: created with the same ops, synced by
/// the same anti-entropy, snapshotted and compacted the same way (ADR 0047
/// §2 — "manifests are kernel docs", same move as ADR 0042 §2).
final class ZoneCatalogCodec {
  const ZoneCatalogCodec._();

  /// The register this codec lives in on a catalog doc.
  static const registerKey = 'catalog';

  /// The op payload storing [catalog].
  static Map<String, Object?> encode(final ZoneCatalog catalog) => {
    'k': registerKey,
    'v': catalog.toJson(),
  };

  /// Reads the catalog out of a doc's folded state, null when the doc
  /// carries no (valid) census.
  static ZoneCatalog? decode(final ConvergenceDoc doc) {
    final raw = LwwMapStrategy.readDynamicValue(doc.state, registerKey);
    if (raw is! Map) return null;
    try {
      return ZoneCatalog.fromJson(Map<String, Object?>.from(raw));
    } on Object {
      return null;
    }
  }
}
