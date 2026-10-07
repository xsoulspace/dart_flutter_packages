import 'dart:async';
import 'dart:convert';
import 'dart:io'
    show ContentType, HttpServer, HttpRequest, InternetAddress, HttpStatus;

/// One decoded loopback request, handed to a [LoopbackRoute].
///
/// [jsonBody] is the parsed JSON object for requests that carried one;
/// null when the request had no body. Malformed bodies never reach a
/// route: the server answers 400 for unparseable JSON and 422 for JSON
/// that is not an object.
final class LoopbackRequest {
  const LoopbackRequest({
    required this.method,
    required this.path,
    this.jsonBody,
  });

  final String method;
  final String path;
  final Map<String, Object?>? jsonBody;
}

/// A route's reply. Routes that decline a request return null and the
/// server answers 404.
final class LoopbackReply {
  const LoopbackReply(this.status, this.body);

  final int status;
  final Map<String, Object?> body;
}

/// Handles one [LoopbackRequest]; returns null to decline (404).
typedef LoopbackRoute = Future<LoopbackReply?> Function(
  LoopbackRequest request,
);

/// A loopback JSON wire server skeleton in pure Dart.
///
/// Owns the plumbing every local model server shares — loopback bind,
/// an open `GET <healthPath>` route, optional `Bearer` auth on every other
/// route, JSON body decoding with named error statuses, and handler-crash
/// containment (a throwing route lands a 500, never a dead isolate) — so
/// wire fakes and pure-Dart servers only implement their route. The
/// laya System One server and the MLX chat fake both compose this; the
/// Python `laya-serve`/`mlx_lm.server` runtimes implement the same
/// contracts for real weights.
///
/// This is a wire server, not a model: engines behind routes are
/// deterministic unless a real model runtime answers instead.
final class LoopbackJsonServer {
  LoopbackJsonServer({
    LoopbackRoute? route,
    this.apiKey,
    this.address,
    this.port = 0,
    this.healthPath = '/health',
    Map<String, Object?> Function()? healthPayload,
  }) : _route =
           route ??
           ((_) async => null),
       _healthPayload = healthPayload ?? (() => <String, Object?>{});

  /// When set, non-health routes require `Authorization: Bearer <apiKey>`;
  /// the health route stays open (the laya-serve contract).
  final String? apiKey;

  /// Defaults to the loopback interface.
  final InternetAddress? address;
  final int port;

  /// The open health route path. Set to a path the server never serves
  /// (e.g. `/__none__`) when the wire under test has no health route.
  final String healthPath;

  final Map<String, Object?> Function() _healthPayload;
  // A named parameter cannot spell the private initializing formal.
  // ignore: prefer_initializing_formals
  final LoopbackRoute _route;

  HttpServer? _server;
  var _requestCounter = 0;

  /// The bound base URL (`http://127.0.0.1:<port>`), after [start].
  Uri get url {
    final server = _server;
    if (server == null) {
      throw StateError('LoopbackJsonServer.start() first');
    }
    return Uri.parse('http://${server.address.host}:${server.port}');
  }

  /// Monotonic count of served (non-health) requests — fixtures assert on
  /// traffic without reading payload content.
  int get servedRequests => _requestCounter;

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
      case ('GET', final path) when path == healthPath:
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(_healthPayload()));
        await request.response.close();
      case final route:
        await _handleRoute(request, route.$1, route.$2);
    }
  }

  Future<void> _handleRoute(
    final HttpRequest request,
    final String method,
    final String path,
  ) async {
    final expectedKey = apiKey;
    if (expectedKey != null) {
      final header = request.headers.value('authorization');
      if (header != 'Bearer $expectedKey') {
        request.response.statusCode = HttpStatus.unauthorized;
        await request.response.close();
        return;
      }
    }
    Map<String, Object?>? body;
    if (method == 'POST' || method == 'PUT' || method == 'PATCH') {
      final raw = await utf8.decoder.bind(request).join();
      if (raw.trim().isEmpty) {
        body = const <String, Object?>{};
      } else {
        final Object? decoded;
        try {
          decoded = jsonDecode(raw);
        } on FormatException {
          request.response.statusCode = HttpStatus.badRequest;
          await request.response.close();
          return;
        }
        if (decoded is! Map) {
          request.response.statusCode = HttpStatus.unprocessableEntity;
          await request.response.close();
          return;
        }
        body = decoded.cast<String, Object?>();
      }
    }
    LoopbackReply? reply;
    try {
      reply = await _route(
        LoopbackRequest(method: method, path: path, jsonBody: body),
      );
    } on Object {
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
      return;
    }
    if (reply == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    _requestCounter++;
    request.response.headers.contentType = ContentType.json;
    request.response.statusCode = reply.status;
    request.response.write(jsonEncode(reply.body));
    await request.response.close();
  }
}
