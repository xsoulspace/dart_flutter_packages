import 'package:meta/meta.dart';

/// An addressable AT-SPI accessible: which bus peer owns it, and the
/// object path under that peer.
///
/// AT-SPI trees span processes — the registry root lives on
/// `org.a11y.atspi.Registry`, while application subtrees live on each
/// app's unique bus name — so a bare object path is not addressable.
@immutable
final class AtspiNodeRef {
  /// Creates a node reference.
  const AtspiNodeRef({required this.destination, required this.path});

  /// Bus name of the owning peer (well-known or unique).
  final String destination;

  /// Object path under the owning peer.
  final String path;

  @override
  String toString() => 'AtspiNodeRef($destination$path)';
}

/// The AT-SPI2 D-Bus surface the driver consumes.
///
/// Abstracted so tests can serve a canned tree without a live session
/// bus; the production implementation is [DBusAtspiBus].
abstract interface class AtspiBus {
  /// Resolves the tree root.
  Future<AtspiNodeRef> root();

  /// `org.a11y.atspi.Accessible` Name property of [ref].
  Future<String> name(AtspiNodeRef ref);

  /// `GetRoleName` — lowercase AT-SPI role (`push button`, `text`,
  /// `frame`, …).
  Future<String> roleName(AtspiNodeRef ref);

  /// Child refs, in document order.
  Future<List<AtspiNodeRef>> children(AtspiNodeRef ref);

  /// Whether the node exposes `org.a11y.atspi.Action`.
  Future<bool> hasActions(AtspiNodeRef ref);

  /// Invokes action [index] on the node.
  Future<void> doAction(AtspiNodeRef ref, int index);

  /// Closes the bus connection. Idempotent.
  Future<void> close();
}
