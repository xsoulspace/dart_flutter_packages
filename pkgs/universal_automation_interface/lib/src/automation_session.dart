import 'package:meta/meta.dart';

import 'automation_exceptions.dart';

/// Whether a session is started by us or adopted from someone else.
enum StartMode {
  /// We own bring-up (oka `start`).
  start,

  /// Something else started it and we attach to the published handle
  /// (oka `attach`).
  attach,
}

/// Ownership of a session's process lease, mirroring oka's
/// `LeaseOwnership`.
enum LeaseOwnership {
  /// We are allowed — and expected — to stop the process on teardown.
  owned,

  /// The process belongs to someone else; it is reported, never stopped.
  borrowed,
}

/// Declarative description of an automation session.
///
/// Validation invariants (fail closed): a borrowed session can never be
/// [StartMode.start] — you do not launch what you only borrow.
@immutable
class SessionDescriptor {
  /// Creates a descriptor after validating its invariants.
  SessionDescriptor({
    required this.name,
    this.startMode = StartMode.attach,
    this.ownership = LeaseOwnership.owned,
  }) {
    ensureValid();
  }

  /// Session name, used in handle artifact ids.
  final String name;

  /// How the session comes to exist.
  final StartMode startMode;

  /// Who owns the underlying process lease.
  final LeaseOwnership ownership;

  /// Invariants; empty means valid.
  List<String> validate() {
    if (name.trim().isEmpty) {
      return const ['session name must not be empty'];
    }
    if (ownership == LeaseOwnership.borrowed && startMode == StartMode.start) {
      const message =
          'a borrowed session cannot have start mode `start`; '
          'borrowing means attaching to an existing process';
      return [message];
    }
    return const [];
  }

  /// Throws [SpecViolationException] when invariants are violated.
  void ensureValid() {
    final violations = validate();
    if (violations.isNotEmpty) {
      throw SpecViolationException(violations);
    }
  }

  /// Serializes the descriptor.
  Map<String, Object?> toJson() => {
    'name': name,
    'startMode': startMode.name,
    'ownership': ownership.name,
  };

  @override
  String toString() =>
      'SessionDescriptor($name, ${startMode.name}, ${ownership.name})';
}
