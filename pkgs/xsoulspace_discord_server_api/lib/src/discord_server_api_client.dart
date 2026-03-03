import 'dart:convert';

import 'discord_transport.dart';
import 'models.dart';
import 'response_codec.dart';

final class DiscordServerApiClient {
  DiscordServerApiClient({
    required this.transport,
    this.baseUri = const String.fromEnvironment(
      'DISCORD_API_V10_BASE',
      defaultValue: 'https://discord.com/api/v10/',
    ),
    this.bearerToken,
  });

  final DiscordTransport transport;
  final String baseUri;
  final String? bearerToken;

  Future<DiscordApiResponse> request({
    required final String method,
    required final String path,
    final Map<String, String> query = const <String, String>{},
    final Map<String, String> headers = const <String, String>{},
    final Map<String, Object?>? jsonBody,
    final String? body,
  }) async {
    final uri = _resolvePath(path);

    final requestHeaders = <String, String>{
      'accept': 'application/json',
      ...headers,
      if (bearerToken != null &&
          bearerToken!.isNotEmpty &&
          !headers.containsKey('authorization'))
        'authorization': 'Bearer $bearerToken',
    };

    String? encodedBody = body;
    if (jsonBody != null) {
      requestHeaders['content-type'] = 'application/json';
      encodedBody = jsonEncode(jsonBody);
    }

    final response = await transport.send(
      DiscordTransportRequest(
        method: method,
        uri: uri,
        query: query,
        headers: requestHeaders,
        body: encodedBody,
      ),
    );

    final apiResponse = toApiResponse(response);
    if (!apiResponse.isSuccess) {
      throw toApiError(apiResponse);
    }

    return apiResponse;
  }

  Future<DiscordCurrentUser> getCurrentUser() async {
    final response = await request(method: 'GET', path: '/users/@me');
    return DiscordCurrentUser.fromMap(response.data);
  }

  Uri _resolvePath(final String path) {
    final base = Uri.parse(baseUri);
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Uri.parse(path);
    }
    final normalized = path.startsWith('/') ? path.substring(1) : path;
    return base.resolve(normalized);
  }
}
