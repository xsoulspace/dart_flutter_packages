part of 'openai_responses.dart';

const openAiSessionOptionsMetadataKey = 'openai_session_options';

/// Explicit adapter specialization. Codex conventions are opt-in on the SIWC
/// route; successful transport does not qualify cache availability or affinity.
final class OpenAiSessionOptions {
  const OpenAiSessionOptions({
    this.sessionAffinity = false,
    this.turnAffinity = false,
  });
  final bool sessionAffinity;
  final bool turnAffinity;
  InferenceRequest attach(InferenceRequest request) => request.copyWith(
    metadata: {
      ...request.metadata,
      openAiSessionOptionsMetadataKey: {
        'sessionAffinity': sessionAffinity,
        'turnAffinity': turnAffinity,
      },
    },
  );
  static OpenAiSessionOptions? fromRequest(InferenceRequest request) {
    final value = request.metadata[openAiSessionOptionsMetadataKey];
    if (value == null) return null;
    if (value is! Map ||
        value['sessionAffinity'] is! bool ||
        value['turnAffinity'] is! bool ||
        (value['turnAffinity'] == true && value['sessionAffinity'] != true)) {
      throw const FormatException('openai_session_options_invalid');
    }
    return OpenAiSessionOptions(
      sessionAffinity: value['sessionAffinity'] as bool,
      turnAffinity: value['turnAffinity'] as bool,
    );
  }
}

/// In-memory adapter state, reusable across short-lived provider clients.
/// Reconciliation preserves a turn's first server token; late responses cannot
/// repopulate a replaced turn. No tokens or auth identity are serialized.
final class OpenAiSessionState {
  OpenAiSessionState({this.capacity = 32}) {
    if (capacity < 1) throw ArgumentError.value(capacity, 'capacity');
  }
  final int capacity;
  final _turns = <String, _OpenAiTurnRouting>{};
  void clear() => _turns.clear();
  void release(String sessionId) => _turns.remove(sessionId);

  _OpenAiTurnRouting _reconcile(
    InferenceSessionContext context,
    ChatGptAccount account,
    ChatGptAuth auth,
    String model,
  ) {
    final session = context.session;
    final signature = (
      account.clientId,
      account.hostId,
      account.subject,
      auth,
      auth.inferenceIdentityGeneration(account.clientId),
      model,
      session.effectiveCacheGroup,
      session.effectiveAffinityKey,
      context.turn!.id,
    );
    final previous = _turns[session.id];
    if (previous != null && previous.signature == signature) return previous;
    if (previous == null && _turns.length >= capacity) {
      throw const FormatException('openai_session_capacity_reached');
    }
    return _turns[session.id] = _OpenAiTurnRouting(session.id, signature);
  }

  void _observe(_OpenAiTurnRouting routing, Map<String, String> headers) {
    if (!identical(_turns[routing.sessionId], routing)) return;
    String? value;
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'x-codex-turn-state') value = entry.value;
    }
    if (value != null &&
        value.isNotEmpty &&
        value.length <= 4096 &&
        value.codeUnits.every((c) => c >= 0x20 && c <= 0x7e)) {
      routing.token ??= value;
    }
  }
}

final class _OpenAiTurnRouting {
  _OpenAiTurnRouting(this.sessionId, this.signature);
  final String sessionId;
  final Object signature;
  String? token;
}
