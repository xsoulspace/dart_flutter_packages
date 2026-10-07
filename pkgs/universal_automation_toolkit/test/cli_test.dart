import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_automation_toolkit/src/cli/toolkit_cli.dart';
import 'package:universal_browser_cdp/universal_browser_cdp_testing.dart';

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

  test('observe prints the snapshot JSON and exits 0', () async {
    final code = await runToolkitCli([
      'observe',
      '--cdp',
      '$endpoint',
    ]);
    expect(code, exitOk);
  });

  test('act click exits 0 and synthesizes input at the fake', () async {
    final code = await runToolkitCli([
      'act',
      '--cdp',
      '$endpoint',
      '--click-name',
      'Submit',
    ]);
    expect(code, exitOk);
    expect(
      fake.inputEvents.map((event) => event['method']),
      contains('Input.dispatchMouseEvent'),
    );
  });

  test('act without a verb is a usage error (exit 2)', () async {
    final code = await runToolkitCli([
      'act',
      '--cdp',
      '$endpoint',
    ]);
    expect(code, exitUsage);
  });

  test('verify passes when checks hold and fails (exit 1) when not',
      () async {
    final ok = await runToolkitCli([
      'verify',
      '--cdp',
      '$endpoint',
      '--exists',
      'role=button,name=Submit',
    ]);
    expect(ok, exitOk);

    final fail = await runToolkitCli([
      'verify',
      '--cdp',
      '$endpoint',
      '--exists',
      'name=Missing',
    ]);
    expect(fail, exitFailure);
  });

  test('screenshot writes the PNG (exit 0)', () async {
    final out =
        '${Directory.systemTemp.path}/uat-cli-${DateTime.now().microsecondsSinceEpoch}.png';
    addTearDown(() {
      if (File(out).existsSync()) File(out).deleteSync();
    });
    final code = await runToolkitCli([
      'screenshot',
      '--cdp',
      '$endpoint',
      '--out',
      out,
    ]);
    expect(code, exitOk);
    expect(File(out).existsSync(), isTrue);
  });

  test('validate reports violations without attaching (exit 1)', () async {
    final file = File(
      '${Directory.systemTemp.path}/uat-cli-plan-${DateTime.now().microsecondsSinceEpoch}.yaml',
    );
    await file.writeAsString('''
sessions:
  browser:
    transport: webdriver
    uri: http://127.0.0.1:9515
scenarios:
  s:
    steps:
      - act: {click: {}}
''');
    addTearDown(() => file.deleteSync());

    // A bad step is a validation failure even before transport linking.
    final bad = await runToolkitCli(['validate', '--plan', file.path]);
    expect(bad, exitFailure);

    await file.writeAsString('''
sessions:
  browser:
    transport: cdp
    uri: $endpoint
scenarios:
  s:
    steps:
      - observe: null
''');
    final good = await runToolkitCli(['validate', '--plan', file.path]);
    expect(good, exitOk);
  });

  test('run executes the scenario and prints a report (exit 0)', () async {
    final file = File(
      '${Directory.systemTemp.path}/uat-cli-run-${DateTime.now().microsecondsSinceEpoch}.yaml',
    );
    await file.writeAsString('''
sessions:
  browser:
    transport: cdp
    uri: $endpoint
scenarios:
  s:
    steps:
      - navigate: {url: '$endpoint/#x'}
      - wait: {checks: [{exists: {role: button, name: Submit}}], timeout: 2}
''');
    addTearDown(() => file.deleteSync());

    final code = await runToolkitCli([
      'run',
      '--plan',
      file.path,
      '--out',
      Directory.systemTemp.path,
    ]);
    expect(code, exitOk);
  });

  test('run with a handle override resolves through --set', () async {
    final file = File(
      '${Directory.systemTemp.path}/uat-cli-set-${DateTime.now().microsecondsSinceEpoch}.yaml',
    );
    await file.writeAsString('''
sessions:
  browser:
    transport: cdp
    handle: session-browser-handle
scenarios:
  s:
    steps:
      - observe: null
''');
    addTearDown(() => file.deleteSync());

    final code = await runToolkitCli([
      'run',
      '--plan',
      file.path,
      '--set',
      'session-browser-handle=$endpoint',
    ]);
    expect(code, exitOk);
  });
}
