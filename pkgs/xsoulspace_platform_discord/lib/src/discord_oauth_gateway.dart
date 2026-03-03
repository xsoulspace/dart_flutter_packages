import 'package:meta/meta.dart';

@immutable
final class DiscordOAuthExchangeRequest {
  const DiscordOAuthExchangeRequest({
    required this.code,
    this.state,
    this.codeChallenge,
    this.codeChallengeMethod,
  });

  final String code;
  final String? state;
  final String? codeChallenge;
  final String? codeChallengeMethod;
}

@immutable
final class DiscordOAuthExchangeResult {
  const DiscordOAuthExchangeResult({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
    this.metadata = const <String, Object?>{},
  });

  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;
  final Map<String, Object?> metadata;
}

abstract interface class DiscordOAuthGateway {
  Future<DiscordOAuthExchangeResult> exchangeAuthorizationCode(
    DiscordOAuthExchangeRequest request,
  );
}
