import 'package:meta/meta.dart';

@immutable
final class VkPlaySignatureDiagnostics {
  const VkPlaySignatureDiagnostics({
    required this.canonicalPayload,
    required this.sortedKeys,
    this.skippedNullKeys = const <String>[],
  });

  final String canonicalPayload;
  final List<String> sortedKeys;
  final List<String> skippedNullKeys;
}

@immutable
final class VkPlaySignatureResult {
  const VkPlaySignatureResult({
    required this.signature,
    required this.diagnostics,
  });

  final String signature;
  final VkPlaySignatureDiagnostics diagnostics;
}

@immutable
final class VkPlayApiResponse {
  const VkPlayApiResponse({
    required this.statusCode,
    required this.data,
    required this.rawBody,
    this.headers = const <String, String>{},
  });

  final int statusCode;
  final Map<String, Object?> data;
  final String rawBody;
  final Map<String, String> headers;

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

@immutable
final class VkPlayTransportRequest {
  const VkPlayTransportRequest({
    required this.method,
    required this.uri,
    this.query = const <String, String>{},
    this.headers = const <String, String>{},
    this.form = const <String, String>{},
    this.body,
  });

  final String method;
  final Uri uri;
  final Map<String, String> query;
  final Map<String, String> headers;
  final Map<String, String> form;
  final String? body;
}

@immutable
final class VkPlayTransportResponse {
  const VkPlayTransportResponse({
    required this.statusCode,
    required this.body,
    this.headers = const <String, String>{},
  });

  final int statusCode;
  final String body;
  final Map<String, String> headers;
}
