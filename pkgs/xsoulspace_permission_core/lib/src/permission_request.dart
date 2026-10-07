import 'permission_kind.dart';

/// One thing asking for authority — pure data, no transport.
///
/// Every consumer adapts ITS wire shape into this record at the edge
/// (ACP tool-call requests, OS consent prompts, doc-router announcements)
/// so policies and gates below stay transport-free. Identity and
/// attribution ride along ([origin]); authority never does — a request
/// is a claim, the decision is someone else's.
final class PermissionRequest {
  const PermissionRequest({
    required this.id,
    required this.title,
    this.kind = PermissionKind.other,
    this.wireKindOverride,
    this.details,
    this.origin,
    this.subject,
    this.requestedAt,
  });

  /// Opaque correlation id — the tool call, dialog or announcement this
  /// request belongs to. Answer flows reference it verbatim.
  final String id;

  /// Human-facing title the consent surface renders first.
  final String title;

  /// The classified action kind (the vocabulary policies branch on).
  final PermissionKind kind;

  /// The caller-supplied wire token override, if any.
  final String? wireKindOverride;

  /// The raw wire token the request arrived with. Defaults to
  /// [PermissionKind.wireName] of [kind]; when the request was coerced
  /// from an unknown token, this preserves it so a policy can still
  /// specialize where the closed vocabulary cannot.
  String get wireKind => wireKindOverride ?? kind.wireName;

  /// Optional human-facing detail block (e.g. the unified diff of the
  /// change under review) — the human decides on the CHANGE, not just
  /// the title.
  final String? details;

  /// WHO is acting (actor id, tool name, peer id) — attribution only,
  /// never authority: a known origin earns nothing by itself.
  final String? origin;

  /// The narrow resource the action targets (a path, a tool, a device)
  /// — what grant matching scopes over.
  final String? subject;

  /// When the request was raised (transport clocks differ; advisory).
  final DateTime? requestedAt;

  @override
  bool operator ==(final Object other) =>
      other is PermissionRequest &&
      other.id == id &&
      other.title == title &&
      other.kind == kind &&
      other.wireKind == wireKind &&
      other.details == details &&
      other.origin == origin &&
      other.subject == subject &&
      other.requestedAt == requestedAt;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    kind,
    wireKind,
    details,
    origin,
    subject,
    requestedAt,
  );

  @override
  String toString() =>
      'PermissionRequest($id, ${kind.wireName}, $title'
      '${subject == null ? '' : ', subject: $subject'})';
}
