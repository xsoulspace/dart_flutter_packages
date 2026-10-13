/// Host-private cursor persistence over an existing ACP conversation. These
/// references do not contain a transcript, credentials or execution authority.
library;

final class AcpSessionBinding {
  const AcpSessionBinding({
    required this.conversationKey,
    required this.workingDirectory,
    required this.providerIdentity,
    required this.descriptorRevision,
  });

  factory AcpSessionBinding.fromJson(Map<String, Object?> value) {
    String text(String key) {
      final item = value[key];
      if (item is! String || item.isEmpty) {
        throw const AcpSessionPersistenceRefusal('acp_session_store_invalid');
      }
      return item;
    }

    return AcpSessionBinding(
      conversationKey: text('conversationKey'),
      workingDirectory: text('workingDirectory'),
      providerIdentity: text('providerIdentity'),
      descriptorRevision: text('descriptorRevision'),
    );
  }
  final String conversationKey;
  final String workingDirectory;
  final String providerIdentity;
  final String descriptorRevision;

  bool matches(AcpSessionBinding other) =>
      conversationKey == other.conversationKey &&
      workingDirectory == other.workingDirectory &&
      providerIdentity == other.providerIdentity &&
      descriptorRevision == other.descriptorRevision;

  Map<String, Object?> toJson() => {
    'conversationKey': conversationKey,
    'workingDirectory': workingDirectory,
    'providerIdentity': providerIdentity,
    'descriptorRevision': descriptorRevision,
  };
}

final class AcpSessionReference {
  const AcpSessionReference({required this.binding, required this.sessionId});

  factory AcpSessionReference.fromJson(Map<String, Object?> value) {
    final binding = value['binding'];
    final session = value['sessionId'];
    if (binding is! Map || session is! String || session.isEmpty) {
      throw const AcpSessionPersistenceRefusal('acp_session_store_invalid');
    }
    return AcpSessionReference(
      binding: AcpSessionBinding.fromJson(Map<String, Object?>.from(binding)),
      sessionId: session,
    );
  }
  final AcpSessionBinding binding;
  final String sessionId;

  Map<String, Object?> toJson() => {
    'binding': binding.toJson(),
    'sessionId': sessionId,
  };
}

/// Read/save are device-local owner callbacks. Authorize must check the current
/// native participant/grant, including resume and already connected turns. A
/// saved reference or descriptor fingerprint cannot authorize a prompt itself.
final class AcpSessionPersistence {
  const AcpSessionPersistence({
    required this.read,
    required this.save,
    required this.authorize,
    this.rebind,
    this.acknowledge,
  });
  final Future<AcpSessionReference?> Function(AcpSessionBinding binding) read;
  final Future<void> Function(AcpSessionReference reference) save;
  final Future<bool> Function(
    AcpSessionBinding binding,
    AcpSessionReference? previous,
  )
  authorize;

  /// Native-owner transition authority. Absent ports preserve strict mismatch
  /// refusal. The opaque ticket is a live capability, never cursor JSON.
  final AcpSessionRebindPort? rebind;

  /// Records an actual remote new/load ACK before persistence. Remembered
  /// references never invoke this callback and cannot mint remote lineage.
  final Future<void> Function(AcpSessionReference acknowledged)? acknowledge;
}

final class AcpSessionRebindPort {
  const AcpSessionRebindPort({
    required this.stage,
    required this.authorize,
    required this.commit,
  });

  /// Stage durable pending evidence through the existing owner before load.
  /// Null denies. Failure/uncertain completion must remain pending at the owner.
  final Future<Object?> Function(
    AcpSessionReference previous,
    AcpSessionBinding nextBinding,
  )
  stage;
  final Future<bool> Function(
    Object ticket,
    AcpSessionReference previous,
    AcpSessionBinding nextBinding,
  )
  authorize;

  /// CAS the original cursor only after the exact remote session ACK. This
  /// callback also validates native ticket identity; JSON is not authority.
  final Future<bool> Function(
    Object ticket,
    AcpSessionReference previous,
    AcpSessionReference acknowledged,
  )
  commit;
}

final class AcpSessionPersistenceRefusal implements Exception {
  const AcpSessionPersistenceRefusal(this.code);
  final String code;
  @override
  String toString() => code;
}
