import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The W3C element key.
const elementWireKey = 'element-6066-11e4-a52e-4f735466cecf';

/// In-process fake WebDriver remote end for tests: sessions, navigation,
/// element lookup by canned map, click/keys recording, and screenshots.
class FakeWebDriverServer {
  HttpServer? _server;
  final List<String> sessions = [];

  /// `css selector` → fake element id.
  Map<String, String> elements = {'#submit': 'elem-1'};

  /// Recorded commands as `METHOD path` strings (session-relative paths
  /// keep their `/session/<id>` prefix).
  final List<String> commands = [];

  /// Recorded click target element ids.
  final List<String> clicks = [];

  /// Recorded typed texts.
  final List<String> typedTexts = [];

  /// Recorded action key values.
  final List<String> keyPresses = [];

  /// Recorded pointer-action objects (pointerMove/pointerDown/pointerUp),
  /// in arrival order.
  final List<Map<String, Object?>> pointerActions = [];

  /// URL reported by `GET /session/{id}/url`; set by `POST .../url`.
  String currentUrl = 'about:blank';

  /// Payload for `GET /session/{id}/screenshot`.
  String screenshotBase64 = fakePngBase64;

  /// Text returned by element text lookups.
  String elementTextValue = 'fake element text';

  /// When set, the next command is answered with this error envelope.
  ({String error, String message, int status})? failNext;

  /// Recorded BiDi command method names, in order.
  final List<String> bidiCommands = [];

  /// BiDi events queued for delivery on the session socket.
  final List<Map<String, Object?>> bidiEvents = [];

  /// Fake BiDi document tree returned by `browsingContext.getTree`.
  List<Map<String, Object?>> bidiTree = [
    {
      'context': 'ctx-1',
      'url': 'about:blank',
      'children': <Map<String, Object?>>[],
    },
  ];

  /// Value returned by `script.evaluate`.
  Object? bidiEvaluateValue = 42;

  /// Whether the remote end advertises BiDi (`webSocketUrl`).
  bool bidiEnabled = true;

  final List<WebSocket> _bidiSockets = [];
  Uri? _bidiWsUri;

  /// HTTP base of the running fake.
  Uri get httpBase => Uri.parse('http://127.0.0.1:${_server!.port}');

  /// Starts the fake on an ephemeral loopback port.
  Future<Uri> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((request) => _handle(request).catchError((Object _) {}));
    return httpBase;
  }

  /// Stops the fake.
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  void _onBidi(WebSocket socket, dynamic data) {
    if (data is! String) return;
    final Map<String, Object?> message;
    try {
      message = jsonDecode(data) as Map<String, Object?>;
    } on FormatException {
      return;
    }
    final id = message['id'];
    if (id is! int) return;
    final method = message['method'] as String? ?? '';
    final params =
        (message['params'] as Map<String, Object?>? ?? const {});
    bidiCommands.add(method);
    switch (method) {
      case 'session.subscribe':
      case 'session.status':
      case 'browsingContext.navigate':
        if (method == 'browsingContext.navigate') {
          currentUrl = params['url'] as String? ?? currentUrl;
        }
        socket.add(jsonEncode({'type': 'result', 'id': id, 'result': {}}));
      case 'browsingContext.getTree':
        socket.add(jsonEncode({
          'type': 'result',
          'id': id,
          'result': {'contexts': bidiTree},
        }));
      case 'script.evaluate':
        socket.add(jsonEncode({
          'type': 'result',
          'id': id,
          'result': {
            'result': {'type': 'number', 'value': bidiEvaluateValue},
            'realm': 'realm-1',
          },
        }));
      default:
        socket.add(jsonEncode({
          'type': 'error',
          'id': id,
          'error': 'unknown command',
          'message': method,
        }));
    }
  }

  /// Delivers a BiDi event to every connected session socket.
  void emitBidiEvent(String method, Map<String, Object?> params) {
    final payload = jsonEncode(
      {'type': 'event', 'method': method, 'params': params},
    );
    for (final socket in List.of(_bidiSockets)) {
      socket.add(payload);
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      final socket = await WebSocketTransformer.upgrade(request);
      _bidiSockets.add(socket);
      socket.listen(
        (data) => _onBidi(socket, data),
        onDone: () => _bidiSockets.remove(socket),
      );
      return;
    }
    commands.add('${request.method} $path');
    Future<void> ok(Object? value) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'value': value}));
      await request.response.close();
    }

    Future<void> fail() async {
      final failure = failNext!;
      failNext = null;
      request.response.statusCode = failure.status;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'value': {'error': failure.error, 'message': failure.message},
        }),
      );
      await request.response.close();
    }

    Object? body;
    if (request.method == 'POST') {
      final text = await utf8.decoder.bind(request).join();
      if (text.isNotEmpty) body = jsonDecode(text);
    }

    if (failNext != null) {
      await fail();
      return;
    }

    if (request.method == 'GET' && path == '/status') {
      await ok({'ready': true, 'message': 'fake driver is ready'});
    } else if (request.method == 'POST' && path == '/session') {
      final id = 'session-${sessions.length + 1}';
      sessions.add(id);
      _bidiWsUri ??= Uri.parse(
        'ws://127.0.0.1:${_server!.port}/session/$id',
      );
      await ok({
        'sessionId': id,
        'capabilities': {
          if (bidiEnabled) 'webSocketUrl': _bidiWsUri.toString(),
        },
      });
    } else if (path.startsWith('/session/')) {
      // Split ['', 'session', <id>, ...rest]
      final segments = path.split('/');
      final rest = '/${segments.skip(3).join('/')}';
      final elementId = segments.length > 4 ? segments[4] : null;
      if (request.method == 'DELETE' && rest == '/') {
        await ok(null);
      } else if (request.method == 'POST' && rest == '/url') {
        currentUrl =
            ((body as Map<String, Object?>?)?['url'] as String?) ?? currentUrl;
        await ok(null);
      } else if (request.method == 'GET' && rest == '/url') {
        await ok(currentUrl);
      } else if (request.method == 'GET' && rest == '/title') {
        await ok('Fake page');
      } else if (request.method == 'POST' && rest == '/element') {
        final selector =
            ((body as Map<String, Object?>?)?['value'] as String?) ?? '';
        final id = elements[selector];
        if (id == null) {
          request.response.statusCode = 404;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'value': {'error': 'no such element', 'message': selector},
            }),
          );
          await request.response.close();
          return;
        }
        await ok({elementWireKey: id});
      } else if (request.method == 'GET' && rest.endsWith('/text')) {
        await ok(elementTextValue);
      } else if (request.method == 'POST' && rest.endsWith('/click')) {
        clicks.add(elementId!);
        await ok(null);
      } else if (request.method == 'POST' && rest.endsWith('/value')) {
        typedTexts.add(
          ((body as Map<String, Object?>?)?['text'] as String?) ?? '',
        );
        await ok(null);
      } else if (request.method == 'POST' && rest == '/actions') {
        final actions = body as Map<String, Object?>?;
        final inputs = actions?['actions'] as List<Object?>? ?? const [];
        for (final input in inputs) {
          final inputMap = input as Map<String, Object?>?;
          final keys =
              inputMap?['actions'] as List<Object?>? ?? const [];
          for (final key in keys) {
            final map = key as Map<String, Object?>?;
            if (inputMap?['type'] == 'pointer' && map != null) {
              pointerActions.add(Map<String, Object?>.from(map));
            }
            final isDown = map?['type'] == 'keyDown';
            final value = map?['value'] as String?;
            if (isDown && value != null) keyPresses.add(value);
          }
        }
        await ok(null);
      } else if (request.method == 'GET' && rest == '/screenshot') {
        await ok(screenshotBase64);
      } else {
        await ok(null);
      }
    } else {
      await ok(null);
    }
  }
}

/// Canned 1x1 transparent PNG.
const fakePngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
