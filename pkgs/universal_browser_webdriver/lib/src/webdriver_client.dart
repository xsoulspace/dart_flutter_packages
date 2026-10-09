import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:universal_automation_interface/universal_automation_interface.dart';

import 'webdriver_bidi.dart';
import 'webdriver_exceptions.dart';

/// A remote end element handle (`element-6066-…-key`).
class WebElement {
  /// Creates a handle from a raw element id.
  const WebElement(this.id);

  /// The W3C element constant.
  static const String wireKey = 'element-6066-11e4-a52e-4f735466cecf';

  /// Raw element id.
  final String id;

  /// Wire representation for requests.
  Map<String, String> toWire() => {wireKey: id};

  @override
  String toString() => 'WebElement($id)';
}

/// A W3C WebDriver (classic, HTTP) client.
///
/// Error envelopes (`value.error`) are mapped onto the family exception
/// types; unexpected payloads throw [ProtocolException].
class WebDriverClient {
  /// Creates a client for an HTTP WebDriver endpoint.
  WebDriverClient(
    this.serverUri, {
    HttpClient? client,
    Map<String, Object?>? alwaysMatch,
  }) : _client = client ?? HttpClient(),
       alwaysMatch = alwaysMatch ?? const {};

  /// Endpoint base, e.g. `http://127.0.0.1:7000` (safaridriver serves
  /// under `/`).
  final Uri serverUri;
  final HttpClient _client;

  /// Capabilities merged into every `newSession` `alwaysMatch`.
  final Map<String, Object?> alwaysMatch;
  String? _sessionId;

  /// Active session id after [newSession].
  String? get sessionId => _sessionId;

  Uri? _webSocketUrl;

  /// BiDi WebSocket URL advertised by the new-session response, when the
  /// remote end supports WebDriver BiDi.
  Uri? get webSocketUrl => _webSocketUrl;

  /// Opens the BiDi connection for the current session.
  ///
  /// Throws [DriverUnsupportedException] when the remote end advertised
  /// no `webSocketUrl` — BiDi requires a remote end that speaks it
  /// (geckodriver, chromedriver 106+, safaridriver does not yet).
  Future<WebDriverBidiConnection> bidi() async {
    final url = _webSocketUrl;
    if (url == null) {
      throw const DriverUnsupportedException(
        'remote end advertised no webSocketUrl; WebDriver BiDi is not '
        'supported by this remote end',
      );
    }
    return WebDriverBidiConnection.connect(url);
  }

  Future<Map<String, Object?>> _send(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    final session = _sessionId;
    final fullPath = session == null ? path : '/session/$session$path';
    final request = await _client.openUrl(
      method,
      serverUri.replace(path: fullPath),
    );
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close().timeout(const Duration(seconds: 30));
    final text = await response.transform(utf8.decoder).join();
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, Object?>) {
      throw ProtocolException(
        'webdriver returned a non-object payload',
        details: {'status': response.statusCode},
      );
    }
    final value = decoded['value'];
    if (value is Map<String, Object?> && value['error'] is String) {
      throw WebDriverException.fromEnvelope(
            value['error']! as String,
            value['message'] as String? ?? '',
            response.statusCode,
          );
    }
    return {'status': response.statusCode, 'value': value};
  }

  /// `GET /status` — no session needed.
  Future<Map<String, Object?>> status() async {
    final result = await _send('GET', '/status');
    return result['value'] as Map<String, Object?>? ?? const {};
  }

  /// Starts a session with [capabilities] merged over [alwaysMatch].
  Future<String> newSession({Map<String, Object?>? capabilities}) async {
    final result = await _send('POST', '/session', {
      'capabilities': {
        'alwaysMatch': {...alwaysMatch, ...?capabilities},
      },
    });
    final value = result['value'];
    final id = value is Map<String, Object?> ? value['sessionId'] : null;
    if (id is! String || id.isEmpty) {
      throw const ProtocolException('webdriver returned no sessionId');
    }
    _sessionId = id;
    final sessionCapabilities =
        value is Map<String, Object?> ? value['capabilities'] : null;
    if (sessionCapabilities is Map<String, Object?>) {
      final wsUrl = sessionCapabilities['webSocketUrl'];
      if (wsUrl is String && wsUrl.isNotEmpty) {
        _webSocketUrl = Uri.parse(wsUrl);
      }
    }
    return id;
  }

  /// Ends the session. Idempotent.
  Future<void> deleteSession() async {
    if (_sessionId == null) return;
    try {
      await _send('DELETE', '');
    } on Object {
      // A dead remote end must not block teardown.
    }
    _sessionId = null;
    _webSocketUrl = null;
  }

  /// Navigates the session to [url].
  Future<void> navigate(Uri url) async {
    await _send('POST', '/url', {'url': url.toString()});
  }

  /// Current URL.
  Future<Uri> currentUrl() async {
    final result = await _send('GET', '/url');
    return Uri.parse(result['value']! as String);
  }

  /// Page title.
  Future<String> title() async {
    final result = await _send('GET', '/title');
    return result['value'] as String? ?? '';
  }

  /// Finds an element. [using] is a W3C locator: `css selector`,
  /// `xpath`, `link text`, `tag name`, `accessibility id` (where
  /// supported by the remote end).
  Future<WebElement> findElement(String using, String value) async {
    final result = await _send('POST', '/element', {
      'using': using,
      'value': value,
    });
    final map = result['value'];
    if (map is! Map<String, Object?>) {
      throw const ProtocolException('findElement returned no element');
    }
    final id = map[WebElement.wireKey];
    if (id is! String) {
      throw const ProtocolException('findElement returned no element id');
    }
    return WebElement(id);
  }

  /// Finds an element by CSS selector.
  Future<WebElement> findElementByCss(String selector) =>
      findElement('css selector', selector);

  /// Element text content.
  Future<String> elementText(WebElement element) async {
    final result = await _send('GET', '/element/${element.id}/text');
    return result['value'] as String? ?? '';
  }

  /// Clicks an element.
  Future<void> elementClick(WebElement element) async {
    await _send('POST', '/element/${element.id}/click');
  }

  /// Types [text] into an element.
  Future<void> sendKeys(WebElement element, String text) async {
    await _send('POST', '/element/${element.id}/value', {'text': text});
  }

  /// Presses a key on the active element via the actions API.
  Future<void> keyPress(String key) async {
    await _send('POST', '/actions', {
      'actions': [
        {
          'type': 'key',
          'id': 'keyboard',
          'actions': [
            {'type': 'keyDown', 'value': key},
            {'type': 'keyUp', 'value': key},
          ],
        },
      ],
    });
  }

  /// Runs one pointer-action bundle through the W3C Actions API.
  ///
  /// [actions] are the inner action objects (pointerMove /
  /// pointerDown / pointerUp); moves use viewport coordinates
  /// (`origin: viewport`), the same top-left system the CDP and macOS
  /// tiers use.
  Future<void> runPointerActions(List<Map<String, Object?>> actions) async {
    await runInputSources([
      {
        'type': 'pointer',
        'id': 'mouse',
        'parameters': {'pointerType': 'mouse'},
        'actions': actions,
      },
    ]);
  }

  /// Runs a full multi-source W3C Actions dispatch — the chord shape:
  /// a keyboard source holding modifiers alongside the pointer source.
  Future<void> runInputSources(
    List<Map<String, Object?>> sources,
  ) async {
    await _send('POST', '/actions', {'actions': sources});
  }

  /// Captures a PNG screenshot of the current viewport.
  Future<Uint8List> screenshot() async {
    final result = await _send('GET', '/screenshot');
    final data = result['value'];
    if (data is! String) {
      throw const ProtocolException('screenshot returned no data');
    }
    return base64Decode(data);
  }
}
