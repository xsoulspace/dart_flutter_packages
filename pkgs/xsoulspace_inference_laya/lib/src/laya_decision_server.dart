import 'dart:io' show InternetAddress;

import 'package:xsoulspace_inference_local_serve/xsoulspace_inference_local_serve.dart';

/// One typed question rendered from a System One request body.
final class LayaDecisionQuestion {
  const LayaDecisionQuestion({
    required this.id,
    required this.instructions,
    required this.criteria,
  });

  /// Question id from the request body.
  final String id;
  final String instructions;

  /// optionId -> human-readable description, as sent on the wire.
  final Map<String, String> criteria;
}

/// One System One request, decoded for an engine.
final class LayaDecisionQuery {
  const LayaDecisionQuery({
    required this.model,
    required this.state,
    required this.questions,
  });

  final String model;
  final String state;
  final Map<String, LayaDecisionQuestion> questions;
}

/// The decision seam of the pure-Dart laya server.
///
/// The wire, health, auth, and response normalization live in
/// [LayaDecisionServer]; an engine only answers. Today's engines are
/// deterministic (the scripted engine below); the same seam is where a
/// native model runtime (MLX via Dart native assets) attaches later without
/// any change to clients or the harness path.
abstract interface class LayaDecisionEngine {
  /// Returns questionId -> chosen optionId. Implementations must answer
  /// every question with an option from that question's criteria.
  Map<String, String> answer(final LayaDecisionQuery query);
}

/// One pinned answer for [ScriptedLayaDecisionEngine], matched against the
/// option **descriptions** on the wire (option ids are transport-local).
final class LayaDecisionPin {
  const LayaDecisionPin(
    this.questionId,
    this.optionDescription, {
    this.isPrefix = false,
  });

  final String questionId;
  final String optionDescription;

  /// When true, any description starting with [optionDescription] matches.
  final bool isPrefix;
}

/// Deterministic scripted engine: pins are consumed order-insensitively by
/// question id; an unpinned question falls back to its first criterion.
/// Mirrors the semantics harness fixtures use for the hosted adapters.
final class ScriptedLayaDecisionEngine implements LayaDecisionEngine {
  ScriptedLayaDecisionEngine(final List<LayaDecisionPin> pins)
    : pins = List<LayaDecisionPin>.unmodifiable(pins);

  final List<LayaDecisionPin> pins;
  final List<LayaDecisionQuery> requests = <LayaDecisionQuery>[];
  final Set<int> _consumed = <int>{};

  /// Clears consumed pins so a fresh run replays the script from the start
  /// (benchmarks and repeated fixtures).
  void reset() => _consumed.clear();

  @override
  Map<String, String> answer(final LayaDecisionQuery query) {
    requests.add(query);
    final answers = <String, String>{};
    for (final entry in query.questions.entries) {
      final question = entry.value;
      String? chosen;
      for (var i = 0; i < pins.length; i++) {
        if (_consumed.contains(i)) continue;
        final pin = pins[i];
        if (pin.questionId != question.id) continue;
        _consumed.add(i);
        for (final optionId in question.criteria.keys) {
          final description = question.criteria[optionId]!;
          final matches = pin.isPrefix
              ? description.startsWith(pin.optionDescription)
              : description == pin.optionDescription;
          if (matches) {
            chosen = optionId;
            break;
          }
        }
        break;
      }
      answers[question.id] = chosen ?? question.criteria.keys.first;
    }
    return answers;
  }
}

/// A laya-compatible decision server in pure Dart.
///
/// Serves the System One wire — `GET /health` (open, `{"status":"ok"}`) and
/// `POST /v1/systemone` (optional `Bearer` auth when [apiKey] is set) — so
/// the whole decision path (clients, bindings, the harness handler) runs and
/// is tested with no Python runtime and no model weights. The response is
/// normalized into the strict shape our clients validate: one complete
/// probability distribution per question, the chosen option at mass 1.
///
/// The wire plumbing (loopback bind, health, auth, body decoding, crash
/// containment) is the shared [LoopbackJsonServer] skeleton; this class
/// owns the System One route and response normalization. It is a wire
/// server, not a model: token counts are estimates, the engine is
/// deterministic unless a real model engine is attached to
/// [LayaDecisionEngine]. The `laya-serve`/`laya-mlx` Python runtimes remain
/// the only way to run the trained checkpoints today.
final class LayaDecisionServer {
  LayaDecisionServer({
    required LayaDecisionEngine engine,
    this.model = 'laya',
    this.apiKey,
    this.address,
    this.port = 0,
    // A named parameter cannot spell the private initializing formal.
    // ignore: prefer_initializing_formals
  }) : _engine = engine;

  final LayaDecisionEngine _engine;
  final String model;

  /// When set, `/v1/systemone` requires `Authorization: Bearer <apiKey>`;
  /// `/health` stays open (the laya-serve contract).
  final String? apiKey;

  /// Defaults to the loopback interface.
  final InternetAddress? address;
  final int port;

  // A late final field can reference instance members (the route tear-off);
  // a constructor initializer cannot.
  late final LoopbackJsonServer _server = LoopbackJsonServer(
    apiKey: apiKey,
    address: address,
    port: port,
    healthPayload: () => <String, Object?>{'status': 'ok', 'model': model},
    route: _handleSystemOne,
  );
  var _requestCounter = 0;

  /// Optional observer for served requests (demo logging, fixtures).
  /// Observer errors are ignored.
  void Function(LayaDecisionQuery query)? onRequest;

  /// The bound base URL (`http://127.0.0.1:<port>`), after [start].
  Uri get url => _server.url;

  Future<void> start() => _server.start();

  Future<void> stop() => _server.stop();

  Future<LoopbackReply?> _handleSystemOne(
    final LoopbackRequest request,
  ) async {
    if (request.method != 'POST' || request.path != '/v1/systemone') {
      return null;
    }
    final decoded = request.jsonBody!;
    final requestModel = decoded['model'];
    final state = decoded['state'];
    final rawQuestions = decoded['questions'];
    if (requestModel is! String || state is! String || rawQuestions is! Map) {
      return const LoopbackReply(422, <String, Object?>{});
    }

    final questions = <String, LayaDecisionQuestion>{};
    for (final entry in rawQuestions.entries) {
      final id = entry.key;
      final raw = entry.value;
      if (raw is! Map) {
        return const LoopbackReply(422, <String, Object?>{});
      }
      final question = raw.cast<String, dynamic>();
      final criteria = question['criteria'];
      if (criteria is! Map || criteria.isEmpty) {
        return const LoopbackReply(422, <String, Object?>{});
      }
      questions['$id'] = LayaDecisionQuestion(
        id: '$id',
        instructions: '${question['instructions'] ?? ''}',
        criteria: criteria.cast<String, String>(),
      );
    }

    final query = LayaDecisionQuery(
      model: requestModel,
      state: state,
      questions: questions,
    );
    try {
      onRequest?.call(query);
    } on Object {
      // Observer errors are ignored (demo logging, fixtures).
    }
    final Map<String, String> chosen;
    try {
      chosen = _engine.answer(query);
    } on Object {
      return const LoopbackReply(500, <String, Object?>{});
    }

    final answers = <String, Object?>{};
    for (final entry in questions.entries) {
      final question = entry.value;
      final optionId = chosen[entry.key];
      if (optionId == null || !question.criteria.containsKey(optionId)) {
        return const LoopbackReply(422, <String, Object?>{});
      }
      answers[entry.key] = <String, Object?>{
        'type': 'choice',
        'choice': optionId,
        'confidence': 0.9,
        'probabilities': <String, double>{
          for (final candidate in question.criteria.keys)
            candidate: candidate == optionId ? 1.0 : 0.0,
        },
      };
    }

    return LoopbackReply(200, <String, Object?>{
      'id': 'laya-dart-${++_requestCounter}',
      'model': model,
      'provider': 'laya_dart',
      'answers': answers,
      // Estimated, never reported as measured: the scripted engine does
      // not run a tokenizer.
      'usage': <String, Object?>{
        'input_tokens': (state.length + _criteriaLength(questions)) ~/ 4,
        'output_tokens': answers.length * 8,
      },
    });
  }

  static int _criteriaLength(final Map<String, LayaDecisionQuestion> q) =>
      q.values.fold(
        0,
        (total, question) =>
            total +
            question.id.length +
            question.instructions.length +
            question.criteria.values.join().length,
      );
}
