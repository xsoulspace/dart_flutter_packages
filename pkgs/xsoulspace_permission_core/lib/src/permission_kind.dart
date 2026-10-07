/// The closed action-kind vocabulary of a permission request.
///
/// The names mirror the ACP `session/request_permission` kinds every
/// consumer already speaks (the pinned `acp_toolkit` carries them as an
/// open wire string with these conventional values). The kind is the
/// JOIN POINT for other permission families: operating-system consent
/// (camera, microphone, notifications, location) joins in a later
/// minor version as NEW names on this enum, so consumers must parse by
/// name and never exhaustive-switch without a default — see
/// [tryParse] / [coerce], which keep unknown wire kinds honestly
/// representable instead of throwing.
enum PermissionKind {
  /// Observing state: reads, listings, screenshots. Conventionally never
  /// gated — an agent that cannot read cannot work.
  read('read'),

  /// Mutating files inside the working set.
  edit('edit'),

  /// Renames and relocations inside the working set.
  move('move'),

  /// Running commands or code — reach beyond the working set.
  execute('execute'),

  /// Destructive removals.
  delete('delete'),

  /// Anything the wire names but this vocabulary does not model yet.
  /// Unknown kinds land here through [coerce]; the raw string survives
  /// on the request so a policy can still specialize on it.
  other('other');

  const PermissionKind(this.wireName);

  /// The wire token this kind round-trips as (the ACP `kind` string).
  final String wireName;

  /// Parses a wire kind; `null` when the name is not in this vocabulary
  /// — the caller decides what an unknown kind means (usually [other]).
  static PermissionKind? tryParse(final String? name) {
    if (name == null) return null;
    for (final kind in PermissionKind.values) {
      if (kind.wireName == name) return kind;
    }
    return null;
  }

  /// Total parse: unknown/absent names become [other], so a request is
  /// never lost to a vocabulary gap. Deny-by-default stays intact
  /// because `other` is never in an allow set by accident.
  static PermissionKind coerce(final String? name) =>
      tryParse(name) ?? PermissionKind.other;
}
