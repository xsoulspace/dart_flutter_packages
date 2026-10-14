import 'dart:typed_data';
import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_automation_toolkit/compose.dart';
import 'package:universal_automation_toolkit/universal_automation_toolkit.dart';
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
        'childIds': ['2'],
      },
      {
        'nodeId': '2',
        'role': {'value': 'button'},
        'name': {'value': 'Submit'},
        'backendDOMNodeId': 42,
        'bounds': {'x': 40, 'y': 60, 'width': 200, 'height': 80},
      },
    ];
    endpoint = await fake.start();
  });
  tearDown(() => fake.stop());

  test('code steps run first-class Dart (driver access + results)', () async {
    final plan = AutomationPlan(
      sessions: [cdp('browser', uri: endpoint)],
      scenarios: [
        scenario('s', steps: [
          code(
            (context) async {
              final snapshot = await context.driver.snapshot();
              return {'nodes': snapshot.nodes.length};
            },
            label: 'count-nodes',
          ),
        ]),
      ],
    );

    final report = await PlanRunner().run(plan);
    expect(report.ok, isTrue);
    expect(report.steps.single.detail['nodes'], greaterThan(0));
  });

  test('exec runs terminal commands; non-zero exit fails the step', () async {
    final ok = AutomationPlan(
      sessions: [cdp('browser', uri: endpoint)],
      scenarios: [
        scenario('s', steps: [exec('true', session: 'browser')]),
      ],
    );
    expect((await PlanRunner().run(ok)).ok, isTrue);

    final failing = AutomationPlan(
      sessions: [cdp('browser', uri: endpoint)],
      scenarios: [
        scenario('s', steps: [exec('false', session: 'browser')]),
      ],
    );
    final report = await PlanRunner().run(failing);
    expect(report.ok, isFalse);
    expect(report.steps.single.errorKind, 'codeStepFailed');
    expect(
      (report.steps.single.errorMessage ?? '').contains('exited'),
      isTrue,
    );
  });

  test('planDocument refuses snapshots carrying code steps', () async {
    final plan = AutomationPlan(
      sessions: [cdp('browser', uri: endpoint)],
      scenarios: [
        scenario('s', steps: [
          observe(),
          exec('true', session: 'browser'),
        ]),
      ],
    );
    expect(
      () => planDocument(plan),
      throwsA(
        isA<SpecViolationException>().having(
          (error) => error.violations,
          'violations',
          everyElement(contains('Dart-only code steps')),
        ),
      ),
    );
    // Without the code step the snapshot exports cleanly.
    final exportable = AutomationPlan(
      sessions: plan.sessions.values.toList(),
      scenarios: [scenario('s', steps: [observe()])],
    );
    expect(planDocument(exportable)['scenarios'], isNotNull);
  });

  test('document parsing refuses "code" keys loudly', () async {
    final file = File(
      '${Directory.systemTemp.path}/uat-code-${DateTime.now().microsecondsSinceEpoch}.yaml',
    );
    await file.writeAsString('''
sessions:
  browser:
    transport: cdp
    uri: $endpoint
scenarios:
  s:
    steps:
      - code: {run: anything}
''');
    addTearDown(() => file.deleteSync());
    await expectLater(
      AutomationPlan.load(file.path),
      throwsA(
        isA<SpecViolationException>().having(
          (error) => error.violations,
          'violations',
          everyElement(contains('Dart-only')),
        ),
      ),
    );
  });

  test('record captures the fake screencast stream into artifacts',
      () async {
    final outDir = Directory.systemTemp.createTempSync('uat-record');
    addTearDown(() => outDir.deleteSync(recursive: true));

    final plan = AutomationPlan(
      sessions: [cdp('browser', uri: endpoint)],
      scenarios: [
        scenario('s', steps: [
          record(
            const Duration(milliseconds: 300),
            outDir.path,
            base: 'demo',
          ),
        ]),
      ],
    );

    final report = await PlanRunner().run(plan);
    expect(report.ok, isTrue);
    expect(report.steps.single.detail['frames'], greaterThanOrEqualTo(1));
    expect(
      File('${outDir.path}/demo.mjpeg').existsSync(),
      isTrue,
    );
    expect(
      File('${outDir.path}/demo.meta.jsonl').existsSync(),
      isTrue,
    );
  });

  test('handles-dir artifacts resolve handle bindings', () async {
    final handles = Directory.systemTemp.createTempSync('uat-handles');
    addTearDown(() => handles.deleteSync(recursive: true));
    File(
      '${handles.path}/session-staged-handle',
    ).writeAsStringSync('$endpoint\n');

    final plan = AutomationPlan(
      sessions: [cdp('staged', handle: 'session-staged-handle')],
      scenarios: [scenario('s', steps: [observe()])],
    );

    final report = await PlanRunner(
      handleBaseDirectory: handles.path,
    ).run(plan);
    expect(report.ok, isTrue);
  });

  test('injected DriverFactory extends the registry (the Flutter-tier seam)',
      () async {
    final plan = AutomationPlan(
      sessions: [
        SessionBinding(
          name: 'app',
          transport: AutomationTransport.vmService,
          uri: Uri.parse('ws://127.0.0.1:12345/ws'),
        ),
      ],
      scenarios: [scenario('s', steps: [observe()])],
    );

    // Without a factory: loud.
    final loud = await PlanRunner().run(plan);
    expect(loud.ok, isFalse);
    expect(loud.steps.single.errorKind, 'transportNotLinked');

    // With a composition-registered factory: the tier participates.
    // (PlanRunner does not expose the registry; drive the registry API
    // directly for the seam proof.)
    final registry = SessionRegistry(
      bindings: plan.sessions,
    )..registerFactory(AutomationTransport.vmService, (
        binding,
        endpoint,
        timeout,
      ) async {
        expect(endpoint, plan.sessions['app']!.uri);
        return _FakeResolvedSession();
      });
    final session = await registry.attach('app');
    expect(session.binding.name, 'app');
    await registry.detachAll();
  });

  test('attachFocused caches the endpoint-free desktop session', () async {
    var builds = 0;
    final registry = SessionRegistry(
      bindings: const {},
    )..registerFactory(AutomationTransport.osAccessibility, (
        binding,
        endpoint,
        timeout,
      ) async {
        expect(endpoint, Uri.parse('oka:focused'));
        builds += 1;
        return _FakeResolvedSession();
      });
    final first = await registry.attachFocused(
      AutomationTransport.osAccessibility,
    );
    final second = await registry.attachFocused(
      AutomationTransport.osAccessibility,
    );
    expect(identical(first, second), isTrue);
    expect(builds, 1);
    await registry.detachAll();
  });
}

final class _FakeResolvedSession implements ResolvedSession {
  @override
  SessionBinding get binding => SessionBinding(
    name: 'app',
    transport: AutomationTransport.vmService,
    uri: Uri.parse('ws://127.0.0.1:12345/ws'),
  );

  @override
  AutomationDriver get driver => _Driver();

  @override
  Uri? get url => null;

  @override
  BehavioralDriver? asBehavioral() => null;

  @override
  Future<void> detach() async {}
}

final class _Driver implements AutomationDriver {
  @override
  DriverCapabilities get capabilities => const DriverCapabilities(a11yTree: true);

  @override
  Future<Snapshot> snapshot() async => Snapshot(
    roots: const [AxNode(role: 'root')],
    capturedAt: DateTime.now(),
    revision: 1,
  );

  @override
  Future<void> perform(AutomationAction action) async {}

  @override
  Future<Uint8List> screenshot() => throw UnimplementedError();

  @override
  Future<void> close() async {}
}
