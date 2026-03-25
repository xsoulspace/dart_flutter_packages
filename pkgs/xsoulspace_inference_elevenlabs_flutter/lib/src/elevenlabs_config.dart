typedef ElevenLabsBearerTokenProvider = Future<String?> Function();

class ElevenLabsAuthConfig {
  const ElevenLabsAuthConfig({this.apiKey, this.bearerTokenProvider});

  final String? apiKey;
  final ElevenLabsBearerTokenProvider? bearerTokenProvider;

  String? get normalizedApiKey {
    final value = apiKey?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  Future<String?> resolveBearerToken() async {
    final provider = bearerTokenProvider;
    if (provider == null) {
      return null;
    }

    final value = (await provider())?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }

    return value;
  }
}

class ElevenLabsEndpointConfig {
  ElevenLabsEndpointConfig({
    final Uri? baseHttp,
    this.timeout = const Duration(seconds: 30),
  }) : baseHttp = baseHttp ?? Uri.parse('https://api.elevenlabs.io');

  final Uri baseHttp;
  final Duration timeout;

  Uri resolveHttpPath(final String path, {final Map<String, String>? query}) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return baseHttp.replace(
      path: normalizedPath,
      queryParameters: query == null || query.isEmpty ? null : query,
    );
  }

  Uri resolveWebSocketPath(
    final String path, {
    final Map<String, String>? query,
  }) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final scheme = switch (baseHttp.scheme) {
      'http' => 'ws',
      _ => 'wss',
    };
    return baseHttp.replace(
      scheme: scheme,
      path: normalizedPath,
      queryParameters: query == null || query.isEmpty ? null : query,
    );
  }
}
