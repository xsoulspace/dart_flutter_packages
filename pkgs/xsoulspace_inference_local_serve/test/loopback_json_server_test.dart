import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:xsoulspace_inference_local_serve/xsoulspace_inference_local_serve.dart';

void main() {
  late LoopbackJsonServer server;
  late http.Client client;

  Future<http.Response> post(
    Uri url,
    Object? body, {
    Map<String, String> headers = const {},
  }) => client.post(
    url,
    headers: {'content-type': 'application/json', ...headers},
    body: body == null ? '' : jsonEncode(body),
  );

  setUp(() {
    client = http.Client();
  });

  tearDown(() async {
    client.close();
    await server.stop();
  });

  test('health route stays open and echoes the composed payload', () async {
    server = LoopbackJsonServer(
      healthPayload: () => {'status': 'ok', 'model': 'fake'},
    );
    await server.start();

    final response = await client.get(server.url.replace(path: '/health'));
    expect(response.statusCode, 200);
    expect(jsonDecode(response.body), {'status': 'ok', 'model': 'fake'});
  });

  test('routes receive decoded JSON bodies and their replies ride the wire',
      () async {
    final seen = <LoopbackRequest>[];
    server = LoopbackJsonServer(
      route: (request) async {
        seen.add(request);
        return LoopbackReply(200, {'echo': request.jsonBody!['text']});
      },
    );
    await server.start();

    final response = await post(server.url.replace(path: '/v1/echo'), {
      'text': 'hi',
    });

    expect(response.statusCode, 200);
    expect(jsonDecode(response.body), {'echo': 'hi'});
    expect(seen.single.method, 'POST');
    expect(seen.single.path, '/v1/echo');
  });

  test('a route returning null declines with 404', () async {
    server = LoopbackJsonServer();
    await server.start();

    final response = await client.get(server.url.replace(path: '/nope'));
    expect(response.statusCode, 404);
  });

  test('auth guards routes but never the health route', () async {
    server = LoopbackJsonServer(
      apiKey: 'k',
      route: (_) async => LoopbackReply(200, {'ok': true}),
    );
    await server.start();

    final denied = await post(server.url.replace(path: '/v1/x'), {});
    expect(denied.statusCode, 401);

    final wrongKey = await post(server.url.replace(path: '/v1/x'), {},
        headers: {'authorization': 'Bearer wrong'});
    expect(wrongKey.statusCode, 401);

    final allowed = await post(server.url.replace(path: '/v1/x'), {},
        headers: {'authorization': 'Bearer k'});
    expect(allowed.statusCode, 200);

    final health = await client.get(server.url.replace(path: '/health'));
    expect(health.statusCode, 200);
  });

  test('malformed JSON is a 400, non-object JSON a 422', () async {
    server = LoopbackJsonServer(
      route: (_) async => LoopbackReply(200, {'ok': true}),
    );
    await server.start();

    final bad = await client.post(
      server.url.replace(path: '/v1/x'),
      headers: {'content-type': 'application/json'},
      body: '{not json',
    );
    expect(bad.statusCode, 400);

    final nonObject = await client.post(
      server.url.replace(path: '/v1/x'),
      headers: {'content-type': 'application/json'},
      body: '[1,2]',
    );
    expect(nonObject.statusCode, 422);

    final empty = await client.post(
      server.url.replace(path: '/v1/x'),
      headers: {'content-type': 'application/json'},
      body: '',
    );
    expect(empty.statusCode, 200);
  });

  test('a throwing route lands a 500 and the server keeps serving', () async {
    server = LoopbackJsonServer(
      route: (_) async => throw StateError('route bug'),
    );
    await server.start();

    final boom = await post(server.url.replace(path: '/v1/x'), {});
    expect(boom.statusCode, 500);

    // The isolate survived: a later request still routes.
    final health = await client.get(server.url.replace(path: '/health'));
    expect(health.statusCode, 200);
  });

  test('servedRequests counts non-health traffic only', () async {
    server = LoopbackJsonServer(route: (_) async => LoopbackReply(200, {}));
    await server.start();

    await client.get(server.url.replace(path: '/health'));
    await post(server.url.replace(path: '/v1/a'), {});
    await post(server.url.replace(path: '/v1/b'), {});
    expect(server.servedRequests, 2);
  });
}
