import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_automation_toolkit/src/mcp/mcp_server.dart';
import 'package:universal_browser_cdp/universal_browser_cdp_testing.dart';

/// POSTs one JSON-RPC message to the loopback HTTP server.
Future<Map<String, Object?>?> post(
  HttpClient client,
  int port,
  Map<String, Object?> message,
) async {
  final request = await client.post('127.0.0.1', port, '/mcp');
  request.headers.contentType = ContentType.json;
  request.write(jsonEncode(message));
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  if (body.isEmpty) return null;
  return {'status': response.statusCode, ...jsonDecode(body) as Map<String, Object?>};
}

void main() {
  late FakeCdpServer fake;
  late Uri endpoint;

  setUp(() async {
    fake = FakeCdpServer();
    endpoint = await fake.start();
  });
  tearDown(() => fake.stop());

  test('HTTP transport: initialize, tools/list, tools/call, notification',
      () async {
    final httpServer = await startMcpHttp(port: 0, defaultEndpoint: endpoint);
    addTearDown(httpServer.close);
    final port = httpServer.port;

    final client = HttpClient();
    addTearDown(client.close);

    final initialize = await post(client, port, {
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'initialize',
      'params': {'protocolVersion': '2025-06-18'},
    });
    expect(initialize!['status'], 200);
    expect(
      (initialize['result'] as Map<String, Object?>)['protocolVersion'],
      '2025-06-18',
    );

    final notification =
        await post(client, port, {'jsonrpc': '2.0', 'method': 'notifications/initialized'});
    expect(notification, isNull);
    final ping = await client
        .post('127.0.0.1', port, '/mcp')
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'jsonrpc': '2.0', 'method': 'notifications/initialized'}));
    final pingResponse = await ping.close();
    expect(pingResponse.statusCode, 202);

    final tools = await post(client, port, {
      'jsonrpc': '2.0',
      'id': 2,
      'method': 'tools/list',
    });
    expect(
      (tools!['result'] as Map<String, Object?>)['tools'],
      hasLength(6),
    );

    final call = await post(client, port, {
      'jsonrpc': '2.0',
      'id': 3,
      'method': 'tools/call',
      'params': {
        'name': 'automation_observe',
        'arguments': {},
      },
    });
    final payload = jsonDecode(
      (((call!['result'] as Map<String, Object?>)['content'] as List<Object?>)
              .single as Map<String, Object?>)['text'] as String,
    ) as Map<String, Object?>;
    expect(payload['snapshot'], isNotNull);
  });

  test('HTTP transport rejects wrong method and path', () async {
    final httpServer = await startMcpHttp(port: 0);
    addTearDown(httpServer.close);
    final port = httpServer.port;
    final client = HttpClient();
    addTearDown(client.close);

    final get = await client.get('127.0.0.1', port, '/mcp');
    expect((await get.close()).statusCode, 405);
    final wrongPath = await client.post('127.0.0.1', port, '/nope')
      ..headers.contentType = ContentType.json
      ..write('{}');
    expect((await wrongPath.close()).statusCode, 404);
  });

  test('CLI serve --http answers on POST /mcp (process-level proof)', () async {
    final script = File('${Directory.current.path}/.dart_tool/uat_http_probe.dart');
    await script.parent.create(recursive: true);
    await script.writeAsString('''
import 'dart:io';
import 'package:universal_automation_toolkit/src/cli/toolkit_cli.dart';
Future<void> main() async {
  await runToolkitCli(['serve', '--http', '0', '--cdp', '$endpoint']);
}
''');
    addTearDown(() {
      if (script.existsSync()) script.deleteSync();
    });

    final process = await Process.start('/usr/bin/env', [
      'dart',
      script.path,
    ]);
    addTearDown(process.kill);
    // The banner line on stderr carries the resolved ephemeral port.
    final banner = await process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first;
    final url =
        (jsonDecode(banner) as Map<String, Object?>)['url'] as String;
    final port = Uri.parse(url).port;

    final client = HttpClient();
    addTearDown(client.close);
    final response = await post(client, port, {
      'jsonrpc': '2.0',
      'id': 7,
      'method': 'tools/call',
      'params': {
        'name': 'automation_verify',
        'arguments': {
          'checks': [
            {'exists': {'role': 'button', 'name': 'Submit'}},
          ],
        },
      },
    });
    final payload = jsonDecode(
      (((response!['result'] as Map<String, Object?>)['content'] as List<Object?>)
              .single as Map<String, Object?>)['text'] as String,
    ) as Map<String, Object?>;
    expect(payload['ok'], isTrue);
  }, timeout: Timeout(Duration(minutes: 3)));
}
