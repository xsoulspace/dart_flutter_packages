import 'dart:convert';

import 'models.dart';

Map<String, Object?> decodeBodyToMap(String body) {
  if (body.trim().isEmpty) {
    return const <String, Object?>{};
  }

  try {
    final decoded = jsonDecode(body);
    if (decoded is Map<Object?, Object?>) {
      return decoded.map(
        (key, value) => MapEntry(key?.toString() ?? '', value),
      );
    }
    return <String, Object?>{'data': decoded};
  } on FormatException {
    return <String, Object?>{'raw': body};
  }
}

DiscordRateLimitMetadata parseRateLimitMetadata({
  required Map<String, String> headers,
  required Map<String, Object?> data,
}) {
  final retryAfterFromBody = _readNum(data['retry_after']);
  final retryAfterFromHeader = _readNum(headers['retry-after']);
  final retryAfterSeconds = retryAfterFromBody ?? retryAfterFromHeader;

  final resetAfterSeconds = _readNum(headers['x-ratelimit-reset-after']);
  final resetUnix = _readNum(headers['x-ratelimit-reset']);

  DateTime? resetAt;
  if (resetUnix != null) {
    resetAt = DateTime.fromMillisecondsSinceEpoch(
      (resetUnix * 1000).round(),
      isUtc: true,
    );
  }

  return DiscordRateLimitMetadata(
    retryAfter: retryAfterSeconds == null
        ? null
        : Duration(milliseconds: (retryAfterSeconds * 1000).round()),
    global: _readBool(data['global']),
    limit: _readInt(headers['x-ratelimit-limit']),
    remaining: _readInt(headers['x-ratelimit-remaining']),
    resetAt: resetAt,
    resetAfterSeconds: resetAfterSeconds?.toDouble(),
  );
}

DiscordApiResponse toApiResponse(DiscordTransportResponse response) {
  final data = decodeBodyToMap(response.body);
  final rateLimit = parseRateLimitMetadata(
    headers: response.headers,
    data: data,
  );

  return DiscordApiResponse(
    statusCode: response.statusCode,
    data: data,
    rawBody: response.body,
    headers: response.headers,
    rateLimit: rateLimit,
  );
}

DiscordApiError toApiError(DiscordApiResponse response) {
  final code = _readInt(response.data['code']);
  final message = response.data['message']?.toString() ?? 'Discord API error';

  return DiscordApiError(
    statusCode: response.statusCode,
    code: code,
    message: message,
    data: response.data,
    headers: response.headers,
    rateLimit: response.rateLimit,
  );
}

num? _readNum(Object? value) {
  if (value is num) {
    return value;
  }
  if (value is String) {
    return num.tryParse(value);
  }
  return null;
}

int? _readInt(Object? value) {
  final number = _readNum(value);
  return number?.toInt();
}

bool? _readBool(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is String) {
    if (value == 'true') {
      return true;
    }
    if (value == 'false') {
      return false;
    }
  }
  return null;
}
