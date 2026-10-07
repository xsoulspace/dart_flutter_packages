/// Stable, connection-independent address of one world member (ADR 0047 §2).
///
/// `world://<worldId>/<memberPath>` — the game "one continuous world" law:
/// identity never changes when connectivity, device, or zone changes. A
/// member reached through a relay, a LAN peer, or a cold local cache is the
/// SAME member because its URN is the same.
///
/// The wire still carries bare docIds (the storage/kernel truth, unchanged
/// since ADR 0010); the URN is the naming layer above them, resolved by a
/// [UrnResolver]. World ids are opaque strings chosen by the embedding app
/// (`'local'` by default) — a game might use its world/save id, the harness
/// its workspace id.
final class WorldUrn {
  const WorldUrn({required this.worldId, required this.memberPath});

  /// Parses `world://<worldId>/<memberPath>`. Throws [FormatException] on
  /// any other scheme or an empty component.
  factory WorldUrn.parse(final String raw) {
    final prefix = '$scheme://';
    if (!raw.startsWith(prefix)) {
      throw FormatException('WorldUrn must start with "$prefix": $raw');
    }
    final rest = raw.substring(prefix.length);
    final slash = rest.indexOf('/');
    if (slash <= 0 || slash == rest.length - 1) {
      throw FormatException(
        'WorldUrn needs "<worldId>/<memberPath>" after the scheme: $raw',
      );
    }
    final worldId = rest.substring(0, slash);
    final memberPath = rest.substring(slash + 1);
    if (memberPath.isEmpty || memberPath.endsWith('/')) {
      throw FormatException('WorldUrn memberPath is empty: $raw');
    }
    return WorldUrn(worldId: worldId, memberPath: memberPath);
  }

  /// Static factory avoiding the exception path for untrusted input.
  static WorldUrn? tryParse(final String raw) {
    try {
      return WorldUrn.parse(raw);
    } on FormatException {
      return null;
    }
  }

  static const scheme = 'world';

  /// Opaque id of the world (workspace, save, device namespace).
  final String worldId;

  /// Member path INSIDE the world. By the default [PathUrnResolver] this
  /// equals the storage docId byte-for-byte.
  final String memberPath;

  /// Canonical string form.
  String get value => '$scheme://$worldId/$memberPath';

  /// Child member under this urn's path prefix.
  WorldUrn child(final String relativePath) =>
      WorldUrn(worldId: worldId, memberPath: '$memberPath/$relativePath');

  Map<String, Object?> toJson() => {'world': worldId, 'path': memberPath};

  static WorldUrn fromJson(final Map<String, Object?> json) => WorldUrn(
    worldId: json['world']! as String,
    memberPath: json['path']! as String,
  );

  @override
  bool operator ==(final Object other) =>
      other is WorldUrn &&
      other.worldId == worldId &&
      other.memberPath == memberPath;

  @override
  int get hashCode => Object.hash(worldId, memberPath);

  @override
  String toString() => value;
}
