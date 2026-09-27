import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';

/// One BiDi event pushed by the remote end.
@immutable
final class BidiEvent {
  /// Creates an event.
  const BidiEvent(this.method, this.params);

  /// Event name, e.g. `log.entryAdded`.
  final String method;

  /// Event parameters.
  final Map<String, Object?> params;

  @override
  String toString() => 'BidiEvent($method)';
}

/// A BiDi command error response.
class BidiException extends ProtocolException {
  /// Creates the exception from an error response.
  const BidiException(this.bidiError, String message) : super(message);

  /// The BiDi error code (`invalid argument`, `no such frame`, …).
  final String bidiError;
}

/// The bidirectional WebSocket half of WebDriver: command/response plus
/// a live event stream, per the W3C WebDriver BiDi spec.
///
/// Attach after a classic session: the new-session response carries
/// `capabilities.webSocketUrl`. Classic HTTP remains the fallback
/// command path; BiDi adds observation the classic protocol cannot do —
/// console logs, network activity, and page lifecycle as they happen.
class WebDriverBidiConnection {
  WebDriverBidiConnection._(this._socket) {
    _subscription = _socket.listen(_onData, onError: (Object e) {
      _failAll(e);
    }, onDone: () {
      _closed = true;
      _failAll(const WebSocketException('bidi socket closed'));
      unawaited(_events.close());
    });
  }

  final WebSocket _socket;
  final _events = StreamController<BidiEvent>.broadcast();
  final _pending = <int, Completer<Map<String, Object?>>>{};
  StreamSubscription<dynamic>? _subscription;
  int _nextId = 0;
  bool _closed = false;

  /// Connects to a `webSocketUrl` advertised by a new-session response.
  static Future<WebDriverBidiConnection> connect(
    Uri webSocketUrl, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final WebSocket socket;
    try {
      socket = await WebSocket.connect(
        webSocketUrl.toString(),
      ).timeout(timeout);
    } on Object catch (error) {
      throw EndpointUnreachableException(
        'cannot connect BiDi socket $webSocketUrl: $error',
        details: {'uri': webSocketUrl.toString()},
      );
    }
    return WebDriverBidiConnection._(socket);
  }

  /// Broadcast of subscribed events.
  Stream<BidiEvent> get events => _events.stream;

  /// Events filtered by [method] (e.g. `log.entryAdded`).
  Stream<BidiEvent> on(String method) =>
      _events.stream.where((event) => event.method == method);

  /// Sends one BiDi command and completes with its `result`.
  Future<Map<String, Object?>> send(
    String method, [
    Map<String, Object?>? params,
  ]) {
    if (_closed) throw StateError('WebDriverBidiConnection is closed');
    final id = ++_nextId;
    final completer = Completer<Map<String, Object?>>();
    _pending[id] = completer;
    _socket.add(
      jsonEncode({'id': id, 'method': method, 'params': params ?? const {}}),
    );
    return completer.future;
  }

  void _onData(data) {
    if (data is! String) return;
    final Object? message;
    try {
      message = jsonDecode(data);
    } on FormatException {
      return;
    }
    if (message is! Map<String, Object?>) return;
    final type = message['type'];
    if (type == 'event') {
      final method = message['method'];
      if (method is String) {
        _events.add(
          BidiEvent(
            method,
            message['params'] as Map<String, Object?>? ?? const {},
          ),
        );
      }
      return;
    }
    final id = message['id'];
    if (id is! int) return;
    final completer = _pending.remove(id);
    if (completer == null) return;
    if (type == 'error') {
      completer.completeError(
        BidiException(
          message['error'] as String? ?? 'unknown',
          message['message'] as String? ?? 'bidi command failed',
        ),
      );
    } else {
      completer.complete(
        message['result'] as Map<String, Object?>? ?? const {},
      );
    }
  }

  void _failAll(Object error) {
    for (final completer in _pending.values) {
      completer.completeError(error);
    }
    _pending.clear();
  }

  /// Closes the socket; pending commands fail.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription?.cancel();
    await _socket.close();
    _failAll(const WebSocketException('bidi closed by client'));
    await _events.close();
  }
}

/// High-level commands over a [WebDriverBidiConnection].
///
/// v1 surface: event subscription, context tree, navigation, and script
/// evaluation — the observation primitives the classic protocol cannot
/// express.
class WebDriverBidiSession {
  /// Creates a session facade over [connection].
  WebDriverBidiSession(this.connection);

  final WebDriverBidiConnection connection;

  /// Subscribes this session to BiDi [events] (e.g. `log.entryAdded`,
  /// `browsingContext.contextCreated`), optionally scoped to [contexts].
  Future<void> subscribe(
    List<String> events, {
    List<String>? contexts,
  }) async {
    await connection.send('session.subscribe', {
      'events': events,
      'contexts': ?contexts,
    });
  }

  /// The context tree: top-level browsing contexts plus their children.
  Future<List<BidiContextInfo>> getTree({int maxDepth = 3}) async {
    final result = await connection.send('browsingContext.getTree', {
      'maxDepth': maxDepth,
    });
    final contexts = result['contexts'] as List<Object?>? ?? const [];
    return contexts
        .whereType<Map<String, Object?>>()
        .map(BidiContextInfo.fromJson)
        .toList(growable: false);
  }

  /// Navigates [context] (default: current top-level) to [url].
  Future<void> navigate(Uri url, {String? context}) async {
    await connection.send('browsingContext.navigate', {
      'context': ?context,
      'url': url.toString(),
      'wait': 'complete',
    });
  }

  /// Evaluates [expression] in the context's sandbox and returns the
  /// raw BiDi result (`{type, value}` shapes).
  Future<Object?> evaluate(String expression, {String? context}) async {
    final result = await connection.send('script.evaluate', {
      'expression': expression,
      'target': {
        'context': context,
      },
      'awaitPromise': false,
    });
    final scriptResult = result['result'];
    if (scriptResult is Map<String, Object?>) {
      return scriptResult['value'];
    }
    return scriptResult;
  }

  /// Closes the underlying connection.
  Future<void> close() => connection.close();
}

/// One browsing context from `browsingContext.getTree`.
@immutable
final class BidiContextInfo {
  /// Creates context info.
  const BidiContextInfo({
    required this.context,
    required this.url,
    required this.children,
  });

  /// Restores one node from a getTree result.
  factory BidiContextInfo.fromJson(Map<String, Object?> json) =>
      BidiContextInfo(
        context: json['context']! as String,
        url: json['url'] as String? ?? '',
        children: (json['children'] as List<Object?>? ?? const [])
            .whereType<Map<String, Object?>>()
            .map(BidiContextInfo.fromJson)
            .toList(growable: false),
      );

  /// Context id.
  final String context;

  /// Current URL.
  final String url;

  /// Child (iframe) contexts.
  final List<BidiContextInfo> children;

  @override
  String toString() => 'BidiContextInfo($context, $url)';
}
