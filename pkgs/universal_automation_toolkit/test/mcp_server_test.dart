import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:universal_automation_toolkit/universal_automation_toolkit.dart';
import 'package:universal_browser_cdp/universal_browser_cdp_testing.dart';

Future<Map<String, Object?>?> call(
  ToolkitMcpServer server,
  int id,
  String method, [
  Object? params,
]) =>
    server.handle({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      if (params != null) 'params': params,
    });

/// Decodes the text content payload of a tools/call result.
Map<String, Object?> payloadOf(Map<String, Object?>? response) =>
    jsonDecode(
      (((response!['result'] as Map<String, Object?>)['content']
              as List<Object?>)
          .single as Map<String, Object?>)['text'] as String,
    ) as Map<String, Object?>;

void main() {
  late FakeCdpServer fake;
  late Uri endpoint;

  setUp(() async {
    fake = FakeCdpServer();
    // Semantic clicks resolve through the AX path: give the canned
    // nodes backend ids the way real CDP reports them.
    fake.axNodes = [
      {
        'nodeId': '1',
        'role': {'value': 'root'},
        'name': {'value': 'document'},
        'bounds': {'x': 0, 'y': 0, 'width': 800, 'height': 600},
        'childIds': ['2', '4'],
      },
      {
        'nodeId': '2',
        'role': {'value': 'button'},
        'name': {'value': 'Submit'},
        'backendDOMNodeId': 42,
        'bounds': {'x': 40, 'y': 60, 'width': 200, 'height': 80},
      },
      {
        'nodeId': '4',
        'role': {'value': 'textbox'},
        'name': {'value': 'Email'},
        'backendDOMNodeId': 43,
        'value': {'value': ''},
        'childIds': ['5'],
      },
      {
        'nodeId': '5',
        'role': {'value': 'generic'},
        'name': {'value': 'hint'},
      },
    ];
    endpoint = await fake.start();
  });
  tearDown(() => fake.stop());

  test('initialize negotiates a supported protocol version', () async {
    final server = ToolkitMcpServer();
    final response = await call(server, 1, 'initialize', {
      'protocolVersion': '2025-03-26',
      'capabilities': {},
      'clientInfo': {'name': 'test', 'version': '0'},
    });
    final result = response!['result'] as Map<String, Object?>;
    expect(result['protocolVersion'], '2025-03-26');
    expect(
      (result['serverInfo'] as Map<String, Object?>)['name'],
      'universal-automation-toolkit',
    );
  });

  test('tools/list advertises the toolkit surface', () async {
    final server = ToolkitMcpServer();
    final response = await call(server, 2, 'tools/list');
    final result = response!['result'] as Map<String, Object?>;
    final names = [
      for (final tool in result['tools'] as List<Object?>)
        (tool as Map<String, Object?>)['name'],
    ];
    expect(
      names,
      containsAll([
        'automation_observe',
        'automation_act',
        'automation_verify',
        'automation_screenshot',
        'automation_validate_plan',
        'automation_run_plan',
      ]),
    );
  });

  test('notifications get no response; unknown methods get -32601',
      () async {
    final server = ToolkitMcpServer();
    expect(
      await server.handle({
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
      }),
      isNull,
    );
    final error = await call(server, 3, 'no/such/method');
    expect((error!['error'] as Map<String, Object?>)['code'], -32601);
  });

  test('automation_observe drives the default endpoint', () async {
    fake.axNodes = [
      {
        'nodeId': '1',
        'role': {'value': 'button'},
        'name': {'value': 'Buy'},
      },
    ];
    final server = ToolkitMcpServer(defaultEndpoint: endpoint);
    final response = await call(server, 4, 'tools/call', {
      'name': 'automation_observe',
      'arguments': {},
    });
    final result = response!['result'] as Map<String, Object?>;
    expect(result['isError'], isFalse);
    expect(payloadOf(response)['snapshot'], isNotNull);
  });

  test('automation_act clicks through the driver and reports ok',
      () async {
    final server = ToolkitMcpServer(defaultEndpoint: endpoint);
    final response = await call(server, 5, 'tools/call', {
      'name': 'automation_act',
      'arguments': {'action': 'click', 'name': 'Submit'},
    });
    expect(payloadOf(response), {'ok': true, 'action': 'click'});
    expect(
      fake.inputEvents.map((event) => event['method']),
      contains('Input.dispatchMouseEvent'),
    );
  });

  test('automation_act with humanPrior reports the behavior outcome',
      () async {
    final server = ToolkitMcpServer(defaultEndpoint: endpoint);
    final response = await call(server, 6, 'tools/call', {
      'name': 'automation_act',
      'arguments': {
        'action': 'click',
        'name': 'Submit',
        'profile': 'humanPrior',
        'seed': 11,
      },
    });
    final payload = payloadOf(response);
    expect(
      (payload['behavior'] as Map<String, Object?>)['verdict'],
      'complete',
    );
  });

  test('automation_verify returns structured failures', () async {
    final server = ToolkitMcpServer(defaultEndpoint: endpoint);
    final response = await call(server, 7, 'tools/call', {
      'name': 'automation_verify',
      'arguments': {
        'checks': [
          {'exists': {'role': 'button', 'name': 'Submit'}},
          {'exists': {'name': 'NoSuchThing'}},
        ],
      },
    });
    final payload = payloadOf(response);
    expect(payload['ok'], isFalse);
    expect(payload['failures'], hasLength(1));
  });

  test('unknown tool surfaces as isError', () async {
    final server = ToolkitMcpServer();
    final response = await call(server, 8, 'tools/call', {
      'name': 'nope',
      'arguments': {},
    });
    expect((response!['result'] as Map<String, Object?>)['isError'], isTrue);
  });

  test('automation_run_plan runs a document end-to-end', () async {
    final dir = Directory.systemTemp.createTempSync('uat-mcp-plan');
    addTearDown(() => dir.deleteSync(recursive: true));
    final plan = File('${dir.path}/plan.yaml');
    await plan.writeAsString('''
sessions:
  browser:
    transport: cdp
    uri: $endpoint
scenarios:
  s:
    steps:
      - observe: null
''');
    final server = ToolkitMcpServer();
    final response = await call(server, 9, 'tools/call', {
      'name': 'automation_run_plan',
      'arguments': {'plan': plan.path, 'scenario': 's'},
    });
    final payload = payloadOf(response);
    expect(payload['ok'], isTrue);
    expect(payload['scenario'], 's');
  });

  test('stdio loop answers newline-delimited requests', () async {
    final script = File(
      '${Directory.current.path}/.dart_tool/uat_stdio_probe.dart',
    );
    await script.parent.create(recursive: true);
    await script.writeAsString('''
import 'dart:io';
import 'package:universal_automation_toolkit/src/mcp/mcp_server.dart';
Future<void> main() async {
  await serveMcpStdio(defaultEndpoint: Uri.parse('$endpoint'));
}
''');
    addTearDown(() {
      if (script.existsSync()) script.deleteSync();
    });

    // Plain `dart <script>` exec through env: under `flutter test` the
    // resolved executable is flutter_tester (not a dart VM), so resolve
    // the real VM from PATH. No `dart run` pub machinery: fast and
    // stable under parallel load.
    final process = await Process.start('/usr/bin/env', [
      'dart',
      script.path,
    ]);
    final output = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    process.stdin.writeln(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {'protocolVersion': '2024-11-05'},
      }),
    );
    await process.stdin.flush();
    // Cold JIT start can take several seconds; await the first JSON-RPC
    // line (skipping any launcher banner lines) rather than a fixed
    // delay.
    Map<String, Object?>? response;
    await for (final line in output) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('{')) continue;
      response = jsonDecode(trimmed) as Map<String, Object?>;
      break;
    }
    process.stdin.close();
    process.kill();

    expect(response, isNotNull);
    final json = response!;
    expect(json['id'], 1);
    expect(
      (json['result'] as Map<String, Object?>)['protocolVersion'],
      '2024-11-05',
    );
  }, timeout: Timeout(Duration(minutes: 3)));

  test('desktop tier: osAccessibility default observes the focused app',
      () async {
    final server = ToolkitMcpServer(
      defaultTransport: AutomationTransport.osAccessibility,
      factories: {
        AutomationTransport.osAccessibility: (binding, endpoint, timeout) async {
          expect(endpoint, Uri.parse('oka:focused'));
          return _FakeOsResolvedSession(binding);
        },
      },
    );
    final response = await call(server, 10, 'tools/call', {
      'name': 'automation_observe',
      'arguments': {},
    });
    expect((response!['result'] as Map<String, Object?>)['isError'], isFalse);
    final payload = payloadOf(response);
    expect(payload['transport'], 'osAccessibility');
    expect(payload['endpoint'], 'oka:focused');
    final snapshot = payload['snapshot'] as Map<String, Object?>;
    expect(jsonEncode(snapshot), contains('Focused Fake'));
  });

  test('observe view renders; diff closes the loop; returnState on act',
      () async {
    final server = ToolkitMcpServer(defaultEndpoint: endpoint);
    final viewed = await call(server, 20, 'tools/call', {
      'name': 'automation_observe',
      'arguments': {
        'view': {'maxNodes': 2},
      },
    });
    final viewPayload = payloadOf(viewed!)['view'] as Map<String, Object?>;
    expect(viewPayload['render'], contains('# observation'));
    expect(viewPayload['refs'], contains('s_0'));

    final diffed = await call(server, 21, 'tools/call', {
      'name': 'automation_observe',
      'arguments': {
        'view': {'maxNodes': 2},
        'diff': true,
      },
    });
    expect(payloadOf(diffed!)['delta'], '# no change');

    final acted = await call(server, 22, 'tools/call', {
      'name': 'automation_act',
      'arguments': {'action': 'click', 'name': 'Submit', 'returnState': true},
    });
    expect((payloadOf(acted!)['state'] as String), contains('button "Submit"'));
  });

  test('per-call transport override switches tiers; unknown refuses',
      () async {
    final server = ToolkitMcpServer(
      factories: {
        AutomationTransport.osAccessibility: (binding, endpoint, timeout) async {
          return _FakeOsResolvedSession(binding);
        },
      },
    );
    final os = await call(server, 11, 'tools/call', {
      'name': 'automation_observe',
      'arguments': {'transport': 'osAccessibility'},
    });
    expect(payloadOf(os!)['transport'], 'osAccessibility');

    // No endpoint anywhere and no os transport: loud, not silent CDP.
    final missing = await call(server, 12, 'tools/call', {
      'name': 'automation_observe',
      'arguments': {},
    });
    expect((missing!['result'] as Map<String, Object?>)['isError'], isTrue);

    final unknown = await call(server, 13, 'tools/call', {
      'name': 'automation_observe',
      'arguments': {'transport': 'telepathy'},
    });
    expect(
      (((unknown!['result'] as Map<String, Object?>)['content'] as List)
              .single as Map<String, Object?>)['text'],
      contains('unknown transport'),
    );
  });
}

final class _FakeOsResolvedSession implements ResolvedSession {
  _FakeOsResolvedSession(this.binding);

  @override
  final SessionBinding binding;

  @override
  AutomationDriver get driver => _FakeOsDriver();

  @override
  Uri? get url => null;

  @override
  BehavioralDriver? asBehavioral() => null;

  @override
  Future<void> detach() async {}
}

final class _FakeOsDriver implements AutomationDriver {
  @override
  DriverCapabilities get capabilities => const DriverCapabilities(
    screenshot: true,
    a11yTree: true,
    inputSynthesis: true,
  );

  @override
  Future<Snapshot> snapshot() async => Snapshot(
    roots: const [AxNode(role: 'window', name: 'Focused Fake')],
    capturedAt: DateTime.now().toUtc(),
    revision: 1,
  );

  @override
  Future<void> perform(AutomationAction action) async {}

  @override
  Future<Uint8List> screenshot() async => Uint8List(0);

  @override
  Future<void> close() async {}
}
