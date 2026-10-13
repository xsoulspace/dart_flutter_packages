/// Physical input is observed; synthetic delivery and semantic invocation remain
/// distinct even when they produce the same product operation.
enum InteractionOrigin {
  surfaceInput,
  physicalHuman,
  syntheticInput,
  semanticAgent,
}

enum InteractionPhase { idle, active, staged, cancelled }

/// A target-anchored manipulation lifecycle. It owns neither project writes nor
/// permission: ending only stages a candidate for a separate adoption operation.
final class InteractionSession {
  InteractionSession({
    required this.id,
    required this.target,
    required this.revision,
    required this.origin,
  }) {
    if (id.isEmpty || target.isEmpty || revision.isEmpty) {
      throw ArgumentError(
        'Interaction identity, target and revision are required',
      );
    }
  }
  final String id;
  final String target;
  final String revision;
  final InteractionOrigin origin;
  InteractionPhase _phase = InteractionPhase.idle;
  Map<String, Object?> _candidate = const {};
  InteractionPhase get phase => _phase;
  Map<String, Object?> get candidate => Map.unmodifiable(_candidate);

  void begin() {
    if (_phase != InteractionPhase.idle)
      throw StateError('interaction_already_started');
    _phase = InteractionPhase.active;
  }

  void update(Map<String, Object?> value, {required String currentRevision}) {
    if (_phase != InteractionPhase.active)
      throw StateError('interaction_not_active');
    if (currentRevision != revision) {
      cancel();
      throw StateError('interaction_target_stale');
    }
    _candidate = Map.of(value);
  }

  Map<String, Object?> end({required String currentRevision}) {
    if (_phase != InteractionPhase.active)
      throw StateError('interaction_not_active');
    if (revision != currentRevision) {
      cancel();
      throw StateError('interaction_target_stale');
    }
    _phase = InteractionPhase.staged;
    return candidate;
  }

  void cancel() {
    if (_phase == InteractionPhase.staged)
      throw StateError('interaction_already_staged');
    _candidate = const {};
    _phase = InteractionPhase.cancelled;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'target': target,
    'revision': revision,
    'origin': origin.name,
    'phase': phase.name,
    'candidate': candidate,
  };
}
