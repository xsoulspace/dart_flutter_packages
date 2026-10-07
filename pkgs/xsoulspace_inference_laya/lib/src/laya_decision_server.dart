import 'dart:async';
import 'dart:convert';
import 'dart:io'
    show ContentType, HttpServer, HttpRequest, InternetAddress, HttpStatus;

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
/// This is a wire server, not a model: token counts are estimates, the
/// engine is deterministic unless a real model engine is attached to
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

  HttpServer? _server;
  var _requestCounter = 0;

  /// Optional observer for served requests (demo logging, fixtures).
  /// Observer errors are ignored.
  void Function(LayaDecisionQuery query)? onRequest;

  /// The bound base URL (`http://127.0.0.1:<port>`), after [start].
  Uri get url {
    final server = _server;
    if (server == null) {
      throw StateError('LayaDecisionServer.start() first');
    }
    return Uri.parse('http://${server.address.host}:${server.port}');
  }

  Future<void> start() async {
    if (_server != null) return;
    _server = await HttpServer.bind(
      address ?? InternetAddress.loopbackIPv4,
      port,
    );
    unawaited(_serve());
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  Future<void> _serve() async {
    final server = _server;
    if (server == null) return;
    await for (final request in server) {
      try {
        await _handle(request);
      } on Object {
        // A handler crash must not kill the server isolate; the 500 lands
        // only when the handler did not already close the response.
        try {
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
        } on Object {
          // The handler already committed the response.
        }
      }
    }
  }

  Future<void> _handle(final HttpRequest request) async {
    switch ((request.method, request.uri.path)) {
      case ('GET', '/health'):
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, String>{'status': 'ok', 'model': model}),
        );
        await request.response.close();
      case ('POST', '/v1/systemone'):
        await _handleSystemOne(request);
      default:
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
    }
  }

  Future<void> _handleSystemOne(final HttpRequest request) async {
    final expectedKey = apiKey;
    if (expectedKey != null) {
      final header = request.headers.value('authorization');
      if (header != 'Bearer $expectedKey') {
        request.response.statusCode = HttpStatus.unauthorized;
        await request.response.close();
        return;
      }
    }
    final body = await utf8.decoder.bind(request).join();
    final Map<String, dynamic> decoded;
    try {
      final value = jsonDecode(body);
      if (value is! Map) {
        request.response.statusCode = HttpStatus.unprocessableEntity;
        await request.response.close();
        return;
      }
      decoded = value.cast<String, dynamic>();
    } on FormatException {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    final requestModel = decoded['model'];
    final state = decoded['state'];
    final rawQuestions = decoded['questions'];
    if (requestModel is! String || state is! String || rawQuestions is! Map) {
      request.response.statusCode = HttpStatus.unprocessableEntity;
      await request.response.close();
      return;
    }

    final questions = <String, LayaDecisionQuestion>{};
    for (final entry in rawQuestions.entries) {
      final id = entry.key;
      final raw = entry.value;
      if (raw is! Map) {
        request.response.statusCode = HttpStatus.unprocessableEntity;
        await request.response.close();
        return;
      }
      final question = raw.cast<String, dynamic>();
      final criteria = question['criteria'];
      if (criteria is! Map || criteria.isEmpty) {
        request.response.statusCode = HttpStatus.unprocessableEntity;
        await request.response.close();
        return;
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
    onRequest?.call(query);
    final Map<String, String> chosen;
    try {
      chosen = _engine.answer(query);
    } on Object {
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
      return;
    }

    final answers = <String, Object?>{};
    for (final entry in questions.entries) {
      final question = entry.value;
      final optionId = chosen[entry.key];
      if (optionId == null || !question.criteria.containsKey(optionId)) {
        request.response.statusCode = HttpStatus.unprocessableEntity;
        await request.response.close();
        return;
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

    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode(<String, Object?>{
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
      }),
    );
    await request.response.close();
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
