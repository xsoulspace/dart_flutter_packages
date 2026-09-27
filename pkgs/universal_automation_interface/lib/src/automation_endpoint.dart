import 'package:meta/meta.dart';

/// Wire protocol family an automation endpoint speaks.
enum AutomationTransport {
  /// Chrome DevTools Protocol over WebSocket (`universal_browser_cdp`).
  cdp,

  /// W3C WebDriver over HTTP (`universal_browser_webdriver`).
  webdriver,

  /// Dart VM service over WebSocket (Flutter/Dart app drivers).
  vmService,

  /// OS-native accessibility tier (macOS AX, Linux AT-SPI, Windows UIA).
  osAccessibility,

  /// Any other protocol; `AutomationEndpoint.metadata` must name it.
  custom,
}

/// A resolved automation endpoint: where to attach and how to speak to it.
///
/// Endpoints are values, not live connections. Production composition
/// publishes them as session-handle artifacts (see [SessionHandles]); a
/// driver takes an endpoint and attaches. The endpoint never owns the
/// process behind it — that belongs to the lifecycle layer (oka).
@immutable
class AutomationEndpoint {
  /// Creates an endpoint value.
  const AutomationEndpoint({
    required this.transport,
    required this.uri,
    this.authToken,
    this.metadata = const {},
  });

  /// Restores an endpoint from [toJson] output.
  factory AutomationEndpoint.fromJson(Map<String, Object?> json) =>
      AutomationEndpoint(
        transport: AutomationTransport.values.byName(
          json['transport']! as String,
        ),
        uri: Uri.parse(json['uri']! as String),
        authToken: json['authToken'] as String?,
        metadata: (json['metadata'] as Map<Object?, Object?>? ?? const {}).map(
          (key, value) => MapEntry(key! as String, value! as String),
        ),
      );

  /// Which protocol family speaks at [uri].
  final AutomationTransport transport;

  /// HTTP or WebSocket base URI of the endpoint.
  final Uri uri;

  /// Bearer token or probe secret, when the endpoint requires one.
  final String? authToken;

  /// Free-form, protocol-specific metadata (browser version, device serial…).
  final Map<String, String> metadata;

  /// Returns a copy with the given fields replaced.
  AutomationEndpoint copyWith({
    AutomationTransport? transport,
    Uri? uri,
    String? authToken,
    Map<String, String>? metadata,
  }) => AutomationEndpoint(
    transport: transport ?? this.transport,
    uri: uri ?? this.uri,
    authToken: authToken ?? this.authToken,
    metadata: metadata ?? this.metadata,
  );

  /// Serializes the endpoint (auth token included — treat as sensitive).
  Map<String, Object?> toJson() => {
    'transport': transport.name,
    'uri': uri.toString(),
    if (authToken != null) 'authToken': authToken,
    'metadata': metadata,
  };

  @override
  String toString() =>
      'AutomationEndpoint(${transport.name}, $uri, metadata: $metadata)';
}

/// Session-handle naming convention shared with oka.
///
/// The primary handle artifact is `session-<name>-handle`; sub-handles are
/// `session-<name>-<sub>` (for example `session-chrome-cdp-port`). The
/// convention is deliberately a naming contract, not a class hierarchy —
/// hence static-only members here.
// ignore: avoid_classes_with_only_static_members
abstract final class SessionHandles {
  /// Primary handle artifact id for a session named [name].
  static String handle(String name) => 'session-$name-handle';

  /// Sub-handle artifact id for [sub] of a session named [name].
  static String sub(String name, String sub) => 'session-$name-$sub';

  /// Extracts the session [name] back out of a handle produced here,
  /// or `null` when [artifactId] is not a primary handle.
  static String? nameOf(String artifactId) {
    const prefix = 'session-';
    const suffix = '-handle';
    if (!artifactId.startsWith(prefix) || !artifactId.endsWith(suffix)) {
      return null;
    }
    return artifactId.substring(
      prefix.length,
      artifactId.length - suffix.length,
    );
  }
}
