import 'package:http/http.dart' as http;

import 'models.dart';

abstract interface class VkPlayTransport {
  Future<VkPlayTransportResponse> send(VkPlayTransportRequest request);
}

final class HttpVkPlayTransport implements VkPlayTransport {
  HttpVkPlayTransport({final http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<VkPlayTransportResponse> send(
    final VkPlayTransportRequest request,
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
      default:
        throw UnsupportedError('Unsupported HTTP method: $method');
    }

    return VkPlayTransportResponse(
      statusCode: response.statusCode,
      body: response.body,
      headers: response.headers,
    );
  }
}
