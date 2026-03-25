import 'package:http/http.dart' as http;

import 'discord_transport.dart';
import 'models.dart';

final class HttpDiscordTransport implements DiscordTransport {
  HttpDiscordTransport({final http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<DiscordTransportResponse> send(
    final DiscordTransportRequest request,
  ) async {
    final uri = request.query.isEmpty
        ? request.uri
        : request.uri.replace(
            queryParameters: <String, String>{
              ...request.uri.queryParameters,
              ...request.query,
            },
          );

    final method = request.method.toUpperCase();
    late final http.Response response;

    switch (method) {
      case 'GET':
        response = await _client.get(uri, headers: request.headers);
      case 'POST':
        if (request.form.isNotEmpty) {
          response = await _client.post(
            uri,
            headers: request.headers,
            body: request.form,
          );
        } else {
          response = await _client.post(
            uri,
            headers: request.headers,
            body: request.body,
          );
        }
      case 'PUT':
        if (request.form.isNotEmpty) {
          response = await _client.put(
            uri,
            headers: request.headers,
            body: request.form,
          );
        } else {
          response = await _client.put(
            uri,
            headers: request.headers,
            body: request.body,
          );
        }
      case 'PATCH':
        response = await _client.patch(
          uri,
          headers: request.headers,
          body: request.body,
        );
      case 'DELETE':
        response = await _client.delete(
          uri,
          headers: request.headers,
          body: request.body,
        );
      default:
        throw UnsupportedError('Unsupported HTTP method: $method');
    }

    return DiscordTransportResponse(
      statusCode: response.statusCode,
      body: response.body,
      headers: response.headers,
    );
  }
}
