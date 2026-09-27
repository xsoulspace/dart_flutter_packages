import 'dart:convert';
import 'dart:io';

import 'automation_exceptions_export.dart';

const _utf8Decoder = Utf8Decoder(allowMalformed: true);

/// `GET /json/version` response.
class CdpVersionInfo {
  /// Creates version info.
  const CdpVersionInfo({
    required this.browser,
    required this.protocolVersion,
    required this.webSocketDebuggerUrl,
  });

  /// Restores version info from a `/json/version` payload.
  factory CdpVersionInfo.fromJson(Map<String, Object?> json) => CdpVersionInfo(
    browser: json['Browser'] as String? ?? 'unknown',
    protocolVersion: json['Protocol-Version'] as String? ?? '',
    webSocketDebuggerUrl: json['webSocketDebuggerUrl'] as String? ?? '',
  );

  /// `Browser` string, e.g. `Chrome/141.0.0.0`.
  final String browser;

  /// `Protocol-Version` string.
  final String protocolVersion;

  /// Browser-level debugger WebSocket URL.
  final String webSocketDebuggerUrl;

  @override
  String toString() => 'CdpVersionInfo($browser)';
}

/// One entry of `GET /json/list`.
class CdpTargetInfo {
  /// Creates target info.
  const CdpTargetInfo({
    required this.id,
    required this.type,
    required this.url,
    required this.title,
    required this.webSocketDebuggerUrl,
  });

  /// Restores target info from a `/json/list` entry.
  factory CdpTargetInfo.fromJson(Map<String, Object?> json) => CdpTargetInfo(
    id: json['id']! as String,
    type: json['type'] as String? ?? 'page',
    url: json['url'] as String? ?? '',
    title: json['title'] as String? ?? '',
    webSocketDebuggerUrl: json['webSocketDebuggerUrl'] as String? ?? '',
  );

  /// Target id (CDP `targetId`).
  final String id;

  /// Target type: `page`, `iframe`, `worker`, …
  final String type;

  /// Current target URL.
  final String url;

  /// Current target title.
  final String title;

  /// Page-level debugger WebSocket URL.
  final String webSocketDebuggerUrl;

  @override
  String toString() => 'CdpTargetInfo($id, $type, $url)';
}

/// HTTP-side discovery against a CDP endpoint's debug server.
///
/// This is the same readiness contract oka uses for borrowed-lease identity
/// (`GET /json/version` must answer before attach is attempted) plus
/// target enumeration. It is discovery only — the wire protocol lives in
/// [CdpConnection] (see `cdp_connection.dart`).
abstract final class CdpDiscovery {
  /// Probes `/json/version`; `null` when the endpoint is silent or slow.
  static Future<CdpVersionInfo?> version(
    Uri httpBase, {
    Duration timeout = const Duration(seconds: 5),
    HttpClient? client,
  }) async {
    final owned = client == null;
    final http = client ?? HttpClient();
    try {
      final request = await http
          .getUrl(httpBase.replace(path: '/json/version'))
          .timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) return null;
      final body = await response
          .transform(_utf8Decoder)
          .join()
          .timeout(timeout);
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, Object?>) return null;
      return CdpVersionInfo.fromJson(decoded);
    } on Object {
      return null;
    } finally {
      if (owned) http.close();
    }
  }

  /// Requires the endpoint to answer; throws otherwise. Use this before
  /// attaching to a borrowed browser: the identity check is what keeps a
  /// stale port from being mistaken for a live session.
  static Future<CdpVersionInfo> requireAlive(
    Uri httpBase, {
    Duration timeout = const Duration(seconds: 5),
    HttpClient? client,
  }) async {
    final info = await version(httpBase, timeout: timeout, client: client);
    if (info == null) {
      throw EndpointUnreachableException(
        'no CDP endpoint answered at $httpBase; borrowed-lease identity '
        'check failed',
        details: {'httpBase': httpBase.toString()},
      );
    }
    return info;
  }

  /// Lists targets (`/json/list`); empty when unreachable.
  static Future<List<CdpTargetInfo>> listTargets(
    Uri httpBase, {
    Duration timeout = const Duration(seconds: 5),
    HttpClient? client,
  }) async {
    final owned = client == null;
    final http = client ?? HttpClient();
    try {
      final request = await http
          .getUrl(httpBase.replace(path: '/json/list'))
          .timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) return const [];
      final body = await response
          .transform(_utf8Decoder)
          .join()
          .timeout(timeout);
      final decoded = jsonDecode(body);
      if (decoded is! List<Object?>) return const [];
      return decoded
          .whereType<Map<String, Object?>>()
          .map(CdpTargetInfo.fromJson)
          .toList(growable: false);
    } on Object {
      return const [];
    } finally {
      if (owned) http.close();
    }
  }

  /// First target of [type], or `null`.
  static Future<CdpTargetInfo?> findTarget(
    Uri httpBase, {
    String type = 'page',
    Duration timeout = const Duration(seconds: 5),
    HttpClient? client,
  }) async {
    final targets = await listTargets(
      httpBase,
      timeout: timeout,
      client: client,
    );
    for (final target in targets) {
      if (target.type == type) return target;
    }
    return null;
  }
}
