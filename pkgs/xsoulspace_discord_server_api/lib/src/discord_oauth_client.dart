import 'discord_transport.dart';
import 'models.dart';
import 'response_codec.dart';

final class DiscordOAuthClient {
  DiscordOAuthClient({
    required this.clientId,
    required this.clientSecret,
    required this.redirectUri,
    required this.transport,
    this.apiBaseUri = const String.fromEnvironment(
      'DISCORD_API_BASE',
      defaultValue: 'https://discord.com/api/v10/',
    ),
  });

  final String clientId;
  final String clientSecret;
  final String redirectUri;
  final DiscordTransport transport;
  final String apiBaseUri;

  Uri get _tokenUri => Uri.parse(apiBaseUri).resolve('oauth2/token');
  Uri get _revokeUri => Uri.parse(apiBaseUri).resolve('oauth2/token/revoke');

  Future<DiscordOAuthToken> exchangeAuthorizationCode({
    required final String code,
    final String? codeVerifier,
  }) async {
    final response = await _sendForm(
      uri: _tokenUri,
      form: <String, String>{
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': redirectUri,
        if (codeVerifier != null && codeVerifier.isNotEmpty)
          'code_verifier': codeVerifier,
        'client_id': clientId,
        'client_secret': clientSecret,
      },
    );

    return DiscordOAuthToken.fromMap(response.data);
  }

  Future<DiscordOAuthToken> refreshToken({
    required final String refreshToken,
  }) async {
    final response = await _sendForm(
      uri: _tokenUri,
      form: <String, String>{
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': clientId,
        'client_secret': clientSecret,
      },
    );

    return DiscordOAuthToken.fromMap(response.data);
  }

  Future<void> revokeToken({
    required final String token,
    final String tokenTypeHint = 'access_token',
  }) async {
    await _sendForm(
      uri: _revokeUri,
      form: <String, String>{
        'token': token,
        'token_type_hint': tokenTypeHint,
        'client_id': clientId,
        'client_secret': clientSecret,
      },
    );
  }

  Future<DiscordApiResponse> _sendForm({
    required final Uri uri,
    required final Map<String, String> form,
  }) async {
    final transportResponse = await transport.send(
      DiscordTransportRequest(
        method: 'POST',
        uri: uri,
        headers: const <String, String>{
          'content-type': 'application/x-www-form-urlencoded',
          'accept': 'application/json',
        },
        form: form,
      ),
    );

    final response = toApiResponse(transportResponse);
    if (!response.isSuccess) {
      throw toApiError(response);
    }
    return response;
  }
}
