import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A canned CDP PNG payload (1x1 transparent pixel).
const fakePngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

/// In-process fake CDP endpoint for tests: serves `/json/version`,
/// `/json/list`, and a page-level debugger WebSocket that answers the
/// domains [universal_browser_cdp] uses.
///
/// Canned state is mutable so tests can script the world: [axNodes] feeds
/// `Accessibility.getFullAXTree`, [evaluateValue] is returned verbatim from
/// `Runtime.evaluate`, and [autoScreencast] makes `Page.startScreencast`
/// emit periodic `Page.screencastFrame` events. Everything the client
/// sends is recorded in [methods], [inputEvents], and [screencastAcks].
class FakeCdpServer {
  HttpServer? _server;
  final List<WebSocket> _sockets = [];
  Timer? _screencastTimer;

  /// Received method names, in order.
  final List<String> methods = [];

  /// Recorded `Input.*` params, prefixed with the method name.
  final List<Map<String, Object?>> inputEvents = [];

  /// Recorded `Page.screencastFrameAck` params.
  final List<Map<String, Object?>> screencastAcks = [];

  /// How many `Page.screencastFrame` events were emitted.
  int screencastFramesEmitted = 0;

  /// Whether the fake is currently screencasting (set by the client).
  bool screencastActive = false;

  /// `about:blank` initially; updated by `Page.navigate`.
  String currentUrl = 'about:blank';

  /// Payload returned by `Page.captureScreenshot`.
  String screenshotBase64 = fakePngBase64;

  /// JPEG payload per emitted screencast frame (4-byte SOI/EOI).
  String screencastFrameBase64 = base64Encode(const [0xFF, 0xD8, 0xFF, 0xD9]);

  /// `Accessibility.getFullAXTree` node list (CDP shape).
  List<Map<String, Object?>> axNodes = _cannedAxNodes();

  /// Value returned verbatim by `Runtime.evaluate` (default: the canned
  /// element rect JSON with a passing hit-target check, so clicks
  /// resolve).
  String evaluateValue =
      '{"x":40,"y":60,"width":200,"height":80,"hitOk":true}';

  /// When set, answers `Runtime.evaluate` instead of [evaluateValue]; a
  /// `null` result falls back to the default. Tests use this to script
  /// hit-target failures, viewport payloads, and `window.__mcpActions`
  /// registries. Returned values reach the driver exactly as returned —
  /// real CDP `returnByValue` semantics.
  Object? Function(String expression)? evaluateHandler;

  /// When set, `Runtime.evaluate` answers with `exceptionDetails` whose
  /// exception description carries this text — the JS-rejection path
  /// (`CdpPage.evaluateAsync` surfaces it).
  String? evaluateException;

  /// When set, `Page.navigate` answers with this `errorText` and emits no
  /// `Page.frameNavigated` — CDP's real navigation-failure shape.
  String? navigateErrorText;

  /// Whether `Page.navigate` also emits `Page.domContentEventFired` and
  /// `Page.loadEventFired` (default true; tests gate it to script
  /// slow-loading pages).
  bool emitLifecycleEvents = true;

  /// Value returned by `Network.getResponseBody` (plain text).
  String networkResponseBody = '{"ok":true}';

  /// Value returned by `Runtime.callFunctionOn` (defaults to
  /// [evaluateValue]).
  String? callFunctionOnValue;

  /// Target ids created via `Target.createTarget`.
  final List<String> createdTargets = [];

  /// Session ids created via `Target.attachToTarget`.
  final List<String> sessions = [];

  int _targetCounter = 0;

  /// When set, the next request is answered with this error payload.
  Map<String, Object?>? failNextWithError;

  /// Whether `Page.startScreencast` starts the frame-emission timer.
  bool autoScreencast = true;

  /// HTTP base of the running fake.
  Uri get httpBase => Uri.parse('http://127.0.0.1:${_server!.port}');

  /// Page-level debugger WebSocket URL.
  Uri get wsPageUri =>
      Uri.parse('ws://127.0.0.1:${_server!.port}/devtools/page/page-1');

  /// Starts the HTTP + WebSocket server on an ephemeral loopback port.
  Future<Uri> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((request) => _handle(request).catchError((Object _) {}));
    return httpBase;
  }

  /// Stops the server and every open socket.
  Future<void> stop() async {
    _screencastTimer?.cancel();
    for (final socket in List.of(_sockets)) {
      await socket.close();
    }
    _sockets.clear();
    await _server?.close(force: true);
    _server = null;
  }

  /// Pushes an event to every connected debugger socket.
  void emit(String method, Map<String, Object?> params) {
    final payload = jsonEncode({'method': method, 'params': params});
    for (final socket in _sockets) {
      socket.add(payload);
    }
  }

  Future<void> _respondJson(HttpRequest request, Object payload) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(payload));
    await request.response.close();
  }

  Future<void> _handle(HttpRequest request) async {
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      final socket = await WebSocketTransformer.upgrade(request);
      _sockets.add(socket);
      socket.listen(
        (data) => _onRpc(socket, data),
        onDone: () => _sockets.remove(socket),
      );
      return;
    }
    final path = request.uri.path;
    if (path == '/json/version') {
      await _respondJson(request, {
        'Browser': 'FakeChrome/141.0.0.0',
        'Protocol-Version': '1.3',
        'webSocketDebuggerUrl':
            'ws://127.0.0.1:${_server!.port}/devtools/browser/browser-1',
      });
    } else if (path == '/json/list') {
      await _respondJson(request, [
        {
          'id': 'page-1',
          'type': 'page',
          'url': currentUrl,
          'title': 'Fake page',
          'webSocketDebuggerUrl': wsPageUri.toString(),
        },
      ]);
    } else {
      request.response.statusCode = 404;
      await request.response.close();
    }
  }

  void _onRpc(WebSocket socket, data) {
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
    final params = message['params'] as Map<String, Object?>? ?? const {};
    methods.add(method);

    void respond(Map<String, Object?> result) {
      socket.add(jsonEncode({'id': id, 'result': result}));
    }

    final failure = failNextWithError;
    if (failure != null) {
      failNextWithError = null;
      socket.add(jsonEncode({'id': id, 'error': failure}));
      return;
    }

    switch (method) {
      case 'Page.enable':
      case 'Runtime.enable':
      case 'Accessibility.enable':
        respond(const {});
      case 'Page.navigate':
        final errorText = navigateErrorText;
        if (errorText != null) {
          respond({'frameId': 'frame-1', 'errorText': errorText});
          break;
        }
        currentUrl = params['url'] as String? ?? currentUrl;
        respond({'frameId': 'frame-1', 'loaderId': 'loader-1'});
        emit('Page.frameNavigated', {
          'frame': {
            'id': 'frame-1',
            'loaderId': 'loader-1',
            'url': currentUrl,
          },
        });
        if (emitLifecycleEvents) {
          emit('Page.domContentEventFired', const {});
          emit('Page.loadEventFired', const {});
        }
      case 'Page.captureScreenshot':
        respond({'data': screenshotBase64});
      case 'Page.startScreencast':
        screencastActive = true;
        respond(const {});
        if (autoScreencast) _startScreencast();
      case 'Page.stopScreencast':
        screencastActive = false;
        _screencastTimer?.cancel();
        respond(const {});
      case 'Page.screencastFrameAck':
        screencastAcks.add(params);
        respond(const {});
      case 'Runtime.evaluate':
        final expression = params['expression'] as String? ?? '';
        if (evaluateException != null) {
          respond({
            'result': const {'type': 'object'},
            'exceptionDetails': {
              'text': 'Uncaught',
              'exception': {
                'type': 'object',
                'description': evaluateException,
              },
            },
          });
          break;
        }
        final scripted = evaluateHandler?.call(expression);
        respond({
          'result': {
            'type': 'string',
            'value': scripted ?? evaluateValue,
          },
        });
      case 'Accessibility.getFullAXTree':
        respond({'nodes': axNodes});
      case 'Target.closeTarget':
        respond(const {});
      case 'Network.enable':
        respond(const {});
      case 'Network.getResponseBody':
        respond({'body': networkResponseBody, 'base64Encoded': false});
      case 'DOM.resolveNode':
        final backendId = params['backendNodeId'];
        respond({
          'object': {'objectId': 'obj-backend-$backendId'},
        });
      case 'Runtime.callFunctionOn':
        respond({
          'result': {
            'type': 'string',
            'value': callFunctionOnValue ?? evaluateValue,
          },
        });
      case 'Target.createTarget':
        final targetId = 'page-${++_targetCounter}';
        createdTargets.add(targetId);
        respond({'targetId': targetId});
      case 'Target.attachToTarget':
        final targetId = params['targetId'] as String? ?? 'unknown';
        final sessionId = 'session-$targetId';
        sessions.add(sessionId);
        respond({'sessionId': sessionId});
      case 'Target.getTargets':
        respond({
          'targetInfos': [
            {'targetId': 'page-1', 'type': 'page', 'url': currentUrl},
          ],
        });
      default:
        if (method.startsWith('Input.')) {
          inputEvents.add({'method': method, ...params});
        }
        respond(const {});
    }
  }

  void _startScreencast() {
    _screencastTimer?.cancel();
    _screencastTimer = Timer.periodic(const Duration(milliseconds: 20), (
      timer,
    ) {
      if (!screencastActive) {
        timer.cancel();
        return;
      }
      final sessionId = ++screencastFramesEmitted;
      emit('Page.screencastFrame', {
        'data': screencastFrameBase64,
        'metadata': {
          'offsetTop': 0,
          'pageScaleFactor': 1,
          'timestamp': DateTime.now().microsecondsSinceEpoch / 1e6,
        },
        'sessionId': sessionId,
      });
    });
  }
}

List<Map<String, Object?>> _cannedAxNodes() => [
  {
    'nodeId': '1',
    'role': {'value': 'root'},
    'name': {'value': 'document'},
    'bounds': {'x': 0, 'y': 0, 'width': 800, 'height': 600},
    'childIds': ['2', '4'],
  },
  {
    'nodeId': '2',
    'role': {'value': 'button'},
    'name': {'value': 'Submit'},
    'bounds': {'x': 40, 'y': 60, 'width': 200, 'height': 80},
  },
  {
    'nodeId': '3',
    'role': {'value': 'generic'},
    'ignored': true,
  },
  {
    'nodeId': '4',
    'role': {'value': 'textbox'},
    'name': {'value': 'Email'},
    'value': {'value': ''},
    'childIds': ['5'],
  },
  {
    'nodeId': '5',
    'role': {'value': 'generic'},
    'name': {'value': 'hint'},
  },
];
