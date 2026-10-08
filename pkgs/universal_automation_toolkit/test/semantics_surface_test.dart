import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_automation_toolkit/compose.dart';
import 'package:universal_automation_toolkit/src/mcp/mcp_server.dart';
import 'package:universal_automation_toolkit/src/runner/runner.dart';
import 'package:universal_browser_cdp/universal_browser_cdp_testing.dart';

void main() {
  late FakeCdpServer fake;
  late Uri endpoint;

  setUp(() async {
    fake = FakeCdpServer();
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

  AutomationPlan _plan(List<PlanStep> steps) => AutomationPlan(
    sessions: [cdp('browser', uri: endpoint)],
    scenarios: [scenario('s', steps: steps)],
  );

  test('observe renders through a view; act returnState closes the loop',
      () async {
    final report = await PlanRunner().run(
      _plan([
        observe(view: const SemanticView(maxNodes: 3)),
        click(name: 'Submit', returnState: true),
      ]),
    );
    expect(report.ok, isTrue);
    final viewDetail = report.steps[0].detail['view'] as Map<String, Object?>;
    expect(viewDetail['render'], contains('# observation'));
    expect(viewDetail['refs'], contains('s_0'));
    final state = report.steps[1].detail['state'] as String;
    expect(state, contains('button "Submit"'));
  });

  test('scope opens, runs children, closes with the delta as evidence',
      () async {
    final report = await PlanRunner().run(
      _plan([
        scope(
          const SemanticView(subtreeOf: 's_1'),
          [click(name: 'Submit')],
        ),
      ]),
    );
    expect(report.ok, isTrue);
    final scopeResult = report.steps.single;
    expect(scopeResult.kind, 'scope');
    expect((scopeResult.detail['open'] as String), contains('"Submit"'));
    expect(scopeResult.detail['delta'], '# no change');
    expect(scopeResult.children.single.kind, 'act');
  });

  test('scope refuses code steps at validation (fail-closed, both faces)',
      () async {
    final plan = _plan([
      scope(const SemanticView(), [
        code((context) async => {'x': 1}),
      ]),
    ]);
    expect(
      PlanRunner().run(plan),
      throwsA(
        isA<SpecViolationException>().having(
          (error) => error.violations.join(' '),
          'violations',
          contains('cannot cross the snapshot boundary'),
        ),
      ),
    );
    expect(() => planDocument(plan), throwsA(isA<UnsupportedError>()));
  });

  test('documents parse and round-trip scope/observe-view/returnState',
      () async {
    final yaml = '''
sessions:
  browser:
    transport: cdp
    uri: $endpoint
scenarios:
  s:
    steps:
      - observe:
          view:
            maxNodes: 3
      - scope:
          view:
            subtreeOf: s_1
          steps:
            - click: {name: Submit, returnState: true}
''';
    final file = File(
      '${Directory.systemTemp.createTempSync('uat-sem').path}/plan.yaml',
    );
    addTearDown(() => file.parent.deleteSync(recursive: true));
    await file.writeAsString(yaml);
    final plan = await AutomationPlan.load(file.path);
    final report = await PlanRunner().run(plan);
    expect(report.ok, isTrue);
    expect(report.steps[0].detail['view'], isNotNull);
    expect(report.steps[1].children.single.kind, 'act');
    // And the exported document keeps the new shapes.
    final exported = planDocument(plan);
    expect(jsonEncode(exported), contains('returnState'));
  });

  test('coordinate verbs ride plan documents and the MCP act tool',
      () async {
    final yaml = '''
sessions:
  browser:
    transport: cdp
    uri: $endpoint
scenarios:
  s:
    steps:
      - clickAt: {x: 120, y: 80}
      - drag: {fromX: 10, fromY: 20, toX: 300, toY: 400}
      - moveTo: {x: 50, y: 60}
''';
    final file = File(
      '${Directory.systemTemp.createTempSync('uat-coord').path}/plan.yaml',
    );
    addTearDown(() => file.parent.deleteSync(recursive: true));
    await file.writeAsString(yaml);
    final plan = await AutomationPlan.load(file.path);
    final report = await PlanRunner().run(plan);
    expect(report.ok, isTrue);
    final pressed = fake.inputEvents
        .where((event) => event['type'] == 'mousePressed')
        .toList();
    expect(pressed.first['x'], 120);
    expect(pressed.last['x'], 10);

    // The MCP act tool exposes the same verbs.
    final server = ToolkitMcpServer(defaultEndpoint: endpoint);
    final response = await server.handle({
      'jsonrpc': '2.0',
      'id': 30,
      'method': 'tools/call',
      'params': {
        'name': 'automation_act',
        'arguments': {'action': 'clickAt', 'x': 42, 'y': 24},
      },
    });
    expect((response!['result'] as Map<String, Object?>)['isError'], isFalse);
    final lastPressed = fake.inputEvents.lastWhere(
      (event) => event['type'] == 'mousePressed',
    );
    expect(lastPressed['x'], 42);
    expect(lastPressed['y'], 24);
  });
}
