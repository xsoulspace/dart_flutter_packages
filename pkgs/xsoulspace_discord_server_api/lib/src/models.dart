import 'package:meta/meta.dart';

@immutable
final class DiscordTransportRequest {
  const DiscordTransportRequest({
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
final class DiscordTransportResponse {
  const DiscordTransportResponse({
    required this.statusCode,
    required this.body,
    this.headers = const <String, String>{},
  });

  final int statusCode;
  final String body;
  final Map<String, String> headers;
}

@immutable
final class DiscordRateLimitMetadata {
  const DiscordRateLimitMetadata({
    this.retryAfter,
    this.global,
    this.limit,
    this.remaining,
    this.resetAt,
    this.resetAfterSeconds,
  });

  final Duration? retryAfter;
  final bool? global;
  final int? limit;
  final int? remaining;
  final DateTime? resetAt;
  final double? resetAfterSeconds;

  bool get hasRateLimitHint =>
      retryAfter != null ||
      global != null ||
      limit != null ||
      remaining != null ||
      resetAt != null ||
      resetAfterSeconds != null;
}

@immutable
final class DiscordApiResponse {
  const DiscordApiResponse({
    required this.statusCode,
    required this.data,
    required this.rawBody,
    this.headers = const <String, String>{},
    this.rateLimit = const DiscordRateLimitMetadata(),
  });

  final int statusCode;
  final Map<String, Object?> data;
  final String rawBody;
  final Map<String, String> headers;
  final DiscordRateLimitMetadata rateLimit;

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

final class DiscordApiError implements Exception {
  const DiscordApiError({
    required this.statusCode,
    required this.message,
    this.code,
    this.data = const <String, Object?>{},
    this.headers = const <String, String>{},
    this.rateLimit = const DiscordRateLimitMetadata(),
  });

  final int statusCode;
  final int? code;
  final String message;
  final Map<String, Object?> data;
  final Map<String, String> headers;
  final DiscordRateLimitMetadata rateLimit;

  @override
  String toString() {
    final codeLabel = code == null ? '' : ' code=$code';
    return 'DiscordApiError(status=$statusCode$codeLabel, message=$message)';
  }
}

@immutable
final class DiscordOAuthToken {
  const DiscordOAuthToken({
    required this.accessToken,
    required this.tokenType,
    required this.expiresIn,
    this.refreshToken,
    this.scope,
    this.metadata = const <String, Object?>{},
  });

  factory DiscordOAuthToken.fromMap(final Map<String, Object?> map) {
    return DiscordOAuthToken(
      accessToken: map['access_token']?.toString() ?? '',
      tokenType: map['token_type']?.toString() ?? 'Bearer',
      expiresIn: (map['expires_in'] as num?)?.toInt() ?? 0,
      refreshToken: map['refresh_token']?.toString(),
      scope: map['scope']?.toString(),
      metadata: Map<String, Object?>.unmodifiable(map),
    );
  }

  final String accessToken;
  final String tokenType;
  final int expiresIn;
  final String? refreshToken;
  final String? scope;
  final Map<String, Object?> metadata;
}

@immutable
final class DiscordCurrentUser {
  const DiscordCurrentUser({
    required this.id,
    required this.username,
    this.globalName,
    this.discriminator,
    this.avatar,
    this.metadata = const <String, Object?>{},
  });

  factory DiscordCurrentUser.fromMap(final Map<String, Object?> map) {
    return DiscordCurrentUser(
      id: map['id']?.toString() ?? '',
      username: map['username']?.toString() ?? '',
      globalName: map['global_name']?.toString(),
      discriminator: map['discriminator']?.toString(),
      avatar: map['avatar']?.toString(),
      metadata: Map<String, Object?>.unmodifiable(map),
    );
  }

  final String id;
  final String username;
  final String? globalName;
  final String? discriminator;
  final String? avatar;
  final Map<String, Object?> metadata;
}
