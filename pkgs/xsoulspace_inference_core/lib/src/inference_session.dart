import 'context_cache_diagnostics.dart';
import 'models/inference_models.dart';

const inferenceSessionMetadataKey = 'inference_session';

String _identity(Object? value) {
  if (value is! String ||
      !RegExp(r'^[a-zA-Z0-9_.:/-]{1,256}$').hasMatch(value)) {
    throw const FormatException('inference_session_identity_invalid');
  }
  return value;
}

/// Cache sharing is explicit and independent of actor/session identity.
/// The caller authorizes the group. This grants no access to context.
final class InferenceCachePolicy {
  InferenceCachePolicy({required String group, this.boundaries})
    : group = _identity(group);
  factory InferenceCachePolicy.fromJson(Map<String, Object?> json) =>
      InferenceCachePolicy(
        group: _identity(json['group']),
        boundaries: json['boundaries'] == null
            ? null
            : ContextCacheIntent.fromJson(
                Map<String, Object?>.from(json['boundaries']! as Map),
              ),
      );
  final String group;
  final ContextCacheIntent? boundaries;
  Map<String, Object?> toJson() => {
    'group': group,
    if (boundaries != null) 'boundaries': boundaries!.toJson(),
  };
}

/// Immutable desired session state. Adapters own transport resources and
/// ephemeral routing state; reconstructing this value does not reset them.
final class InferenceSessionSpec {
  InferenceSessionSpec({required String id, String? affinityKey, this.cache})
    : id = _identity(id),
      affinityKey = affinityKey == null ? null : _identity(affinityKey);
  factory InferenceSessionSpec.fromJson(Map<String, Object?> json) =>
      InferenceSessionSpec(
        id: _identity(json['id']),
        affinityKey: json['affinityKey'] as String?,
        cache: json['cache'] == null
            ? null
            : InferenceCachePolicy.fromJson(
                Map<String, Object?>.from(json['cache']! as Map),
              ),
      );
  final String id;
  final String? affinityKey;
  final InferenceCachePolicy? cache;
  String get effectiveAffinityKey => affinityKey ?? id;
  String get effectiveCacheGroup => cache?.group ?? id;
  Map<String, Object?> toJson() => {
    'id': id,
    if (affinityKey != null) 'affinityKey': affinityKey,
    if (cache != null) 'cache': cache!.toJson(),
  };

  InferenceRequest attach(InferenceRequest request, {InferenceTurnSpec? turn}) {
    final boundaries = cache?.boundaries;
    if (boundaries != null &&
        request.metadata.containsKey(contextCacheIntentMetadataKey)) {
      throw const FormatException('cache_boundaries_declared_twice');
    }
    return request.copyWith(
      metadata: {
        ...request.metadata,
        inferenceSessionMetadataKey: {
          'session': toJson(),
          if (turn != null) 'turn': turn.toJson(),
        },
        if (boundaries != null)
          contextCacheIntentMetadataKey: boundaries.toJson(),
      },
    );
  }
}

/// A logical model/tool loop, not an individual HTTP request or actor lifetime.
final class InferenceTurnSpec {
  InferenceTurnSpec({required String id}) : id = _identity(id);
  final String id;
  Map<String, Object?> toJson() => {'id': id};
}

final class InferenceSessionContext {
  const InferenceSessionContext({required this.session, this.turn});
  final InferenceSessionSpec session;
  final InferenceTurnSpec? turn;
  static InferenceSessionContext? fromRequest(InferenceRequest request) {
    final value = request.metadata[inferenceSessionMetadataKey];
    if (value == null) return null;
    try {
      final json = Map<String, Object?>.from(value as Map);
      return InferenceSessionContext(
        session: InferenceSessionSpec.fromJson(
          Map<String, Object?>.from(json['session']! as Map),
        ),
        turn: json['turn'] == null
            ? null
            : InferenceTurnSpec(id: _identity((json['turn']! as Map)['id'])),
      );
    } on Object {
      throw const FormatException('inference_session_invalid');
    }
  }
}
