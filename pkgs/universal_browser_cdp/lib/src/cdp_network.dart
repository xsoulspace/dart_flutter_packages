import 'dart:async';
import 'dart:convert';

import 'cdp_connection.dart';

/// One observed network request and its lifecycle.
///
/// Entries are observation-only (`Network.enable` + events); interception
/// is a separate concern and deliberately not here. Redirects update the
/// same entry and bump [redirectCount].
final class NetworkEntry {
  /// Creates an entry.
  NetworkEntry({
    required this.requestId,
    required this.url,
    required this.method,
    required this.resourceType,
    required this.startedAt,
  });

  /// CDP request id (also the `Network.getResponseBody` key).
  final String requestId;

  /// Request URL.
  String url;

  /// Request method.
  final String method;

  /// CDP resource type (`Document`, `XHR`, `Fetch`, …).
  String resourceType;

  /// Wall-clock time the request was observed.
  final DateTime startedAt;

  /// Response status code, once `Network.responseReceived` arrived.
  int? status;

  /// Response MIME type, once known.
  String? mimeType;

  /// Whether `Network.loadingFailed` ended the request.
  bool failed = false;

  /// Failure text (`errorText`), when failed.
  String? failureText;

  /// Whether the request finished successfully.
  bool finished = false;

  /// Number of redirects folded into this entry.
  int redirectCount = 0;

  /// Canonical JSON shape.
  Map<String, Object?> toJson() => {
    'requestId': requestId,
    'url': url,
    'method': method,
    'resourceType': resourceType,
    'startedAt': startedAt.toIso8601String(),
    'status': ?status,
    'mimeType': ?mimeType,
    'failed': failed,
    'failureText': ?failureText,
    'finished': finished,
    'redirectCount': redirectCount,
  };

  @override
  String toString() => 'NetworkEntry(#$method $url '
      '${status?.toString() ?? '…'}${failed ? ' (failed)' : ''})';
}

/// Observation-side network log for one page: request lifecycle entries,
/// in-flight counting, and response-body retrieval.
///
/// Enabled by `CdpPage.attach` — the counters are what make
/// `NavigateWait.networkIdle` possible, and the entries give agents
/// API-level verification surface ("the request returned 200") without
/// touching the page. This is observe-only: no `Fetch` interception, and
/// bodies are fetched lazily per [responseBody].
final class CdpNetworkLog {
  CdpNetworkLog._(this._connection) {
    _subscriptions = [
      _connection.on('Network.requestWillBeSent').listen(_onRequest),
      _connection.on('Network.responseReceived').listen(_onResponse),
      _connection.on('Network.loadingFinished').listen(_onFinished),
      _connection.on('Network.loadingFailed').listen(_onFailed),
    ];
  }

  final CdpTransport _connection;
  late final List<StreamSubscription<CdpEvent>> _subscriptions;
  final List<NetworkEntry> _entries = [];
  final Map<String, NetworkEntry> _byRequestId = {};
  int _inFlight = 0;
  DateTime? _lastChangeAt;

  /// Ring-buffer cap; the oldest entries fall off beyond this.
  final int maxEntries = 1000;

  /// Attaches the log: subscribes to `Network.*` events first, then
  /// enables the domain — no early event can be lost.
  static Future<CdpNetworkLog> attach(CdpTransport connection) async {
    final log = CdpNetworkLog._(connection);
    await connection.send('Network.enable');
    return log;
  }

  /// Cancels the event subscriptions (page teardown).
  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
  }

  /// Observed entries, oldest first.
  List<NetworkEntry> get requests => List.unmodifiable(_entries);

  /// Requests currently in flight (sent but not finished/failed).
  int get inFlightCount => _inFlight;

  /// Last time any network event moved, or `null` if nothing has.
  DateTime? get lastChangeAt => _lastChangeAt;

  /// Fetches the response body for [requestId]: decoded text (malformed
  /// UTF-8 tolerated) when the browser still buffers it, else `null`.
  Future<String?> responseBody(String requestId) async {
    final result = await _connection.send(
      'Network.getResponseBody',
      {'requestId': requestId},
    );
    final body = result['body'];
    if (body is! String) return null;
    if (result['base64Encoded'] == true) {
      return utf8.decode(base64Decode(body), allowMalformed: true);
    }
    return body;
  }

  /// Waits until the page has seen no network movement for [quiet] and
  /// nothing is in flight, or throws [TimeoutException].
  Future<void> waitIdle({
    Duration quiet = const Duration(milliseconds: 500),
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final deadline = DateTime.now().add(timeout);
    final waitStart = DateTime.now();
    while (true) {
      // Anchor the quiet window once: "nothing ever moved" counts from
      // the wait's start, not from each poll.
      final quietFrom = _lastChangeAt ?? waitStart;
      final stillFor = DateTime.now().difference(quietFrom);
      if (_inFlight == 0 && stillFor >= quiet) return;
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException(
          'network never went idle ($_inFlight in flight, '
          'quiet for ${stillFor.inMilliseconds}ms)',
          timeout,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  void _touch() => _lastChangeAt = DateTime.now();

  void _add(NetworkEntry entry) {
    _entries.add(entry);
    _byRequestId[entry.requestId] = entry;
    while (_entries.length > maxEntries) {
      final dropped = _entries.removeAt(0);
      _byRequestId.remove(dropped.requestId);
    }
  }

  void _onRequest(CdpEvent event) {
    final params = event.params;
    final requestId = params['requestId'] as String?;
    final request = params['request'] as Map<String, Object?>?;
    if (requestId == null || request == null) return;
    _touch();
    // A redirect reuses the requestId: fold it into the entry.
    final existing = _byRequestId[requestId];
    if (existing != null && params.containsKey('redirectResponse')) {
      final redirect = params['redirectResponse'] as Map<String, Object?>?;
      if (redirect != null) {
        existing.status = redirect['status'] as int?;
        existing.redirectCount++;
      }
      existing.url = request['url'] as String? ?? existing.url;
      existing.finished = false;
      return;
    }
    _inFlight++;
    _add(
      NetworkEntry(
        requestId: requestId,
        url: request['url'] as String? ?? '',
        method: request['method'] as String? ?? 'GET',
        resourceType: params['type'] as String? ?? 'Other',
        startedAt: DateTime.now(),
      ),
    );
  }

  void _onResponse(CdpEvent event) {
    final requestId = event.params['requestId'] as String?;
    final response = event.params['response'] as Map<String, Object?>?;
    final entry = requestId == null ? null : _byRequestId[requestId];
    if (entry == null || response == null) return;
    _touch();
    entry
      ..status = response['status'] as int?
      ..mimeType = response['mimeType'] as String?;
  }

  void _onFinished(CdpEvent event) {
    final entry =
        _byRequestId[event.params['requestId'] as String?];
    if (entry == null || entry.finished || entry.failed) return;
    _touch();
    entry.finished = true;
    _inFlight = (_inFlight - 1).clamp(0, 1 << 31);
  }

  void _onFailed(CdpEvent event) {
    final entry = _byRequestId[event.params['requestId'] as String?];
    if (entry == null || entry.finished || entry.failed) return;
    _touch();
    entry
      ..failed = true
      ..failureText = event.params['errorText'] as String?;
    _inFlight = (_inFlight - 1).clamp(0, 1 << 31);
  }
}
