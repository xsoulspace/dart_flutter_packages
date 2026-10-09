import 'dart:io';

import 'package:oka_supervisor/oka_supervisor.dart';
import 'package:resource_composition/resource_composition.dart';
import 'package:supervisor_composition/desired.dart';
import 'package:test/test.dart';

void main() {
  test('desired state validates with zero side effects', () {
    final report = desiredComposition().validate(
      observeOnlyFactory(modelServePort: ModelServeFacts.port),
    );
    expect(report.ok, isTrue, reason: '${report.issues}');
  });

  test('validation fails without a wired probe (capability honesty)', () {
    final report = desiredComposition().validate(observeOnlyFactory());
    expect(report.ok, isFalse);
    expect(
      report.issues.map((final issue) => issue.code),
      contains('capabilityReadiness'),
    );
  });

  test('ObserveOnlyProvider.start throws; stop refuses', () async {
    final desired = desiredComposition();
    final component = desired
        .composition(observeOnlyFactory(modelServePort: ModelServeFacts.port))
        .components
        .first;
    const provider = ObserveOnlyProvider();
    await expectLater(
      provider.start(
        StartRequest(
          component: component,
          mode: StartMode.start,
          dependencies: ResolvedOutputs.empty,
          readinessBudget: const Duration(seconds: 1),
          cancellation: Cancellation(),
        ),
      ),
      throwsStateError,
    );
    final stop = await provider.stop(
      const ResourceRef(componentId: 'model-serve', handle: 'foreign'),
      grace: const Duration(seconds: 1),
    );
    expect(stop.disposition, StopDisposition.refused);
    expect(stop.stopped, isFalse);
  });

  test(
    'converge(apply: false) on a seeded registry plans no actions',
    () async {
      final desired = desiredComposition();
      final root = await Directory.systemTemp.createTemp(
        'supervisor_composition',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final registry = MachineRegistry(root: root.path);
      const projectRoot = '/tmp/supervisor-composition-seed';
      final scope = registry.scopeFor(projectRoot);
      final startedAt = DateTime.now().toUtc();
      for (final spec in desired.specs) {
        registry.upsert(
          SupervisorRecord(
            componentId: spec.id,
            providerName: spec.providerName,
            shape: spec.policy.shape.name,
            revisionHash: spec.revisionHash,
            epoch: 1,
            killPolicy: KillPolicy.none,
            startedAt: startedAt,
            restartCount: 0,
            windowStartedAt: startedAt,
            trigger: spec.trigger.describe(),
            pid: 4242,
          ),
          scope: scope,
        );
      }
      final supervisor = Supervisor(
        projectRoot: projectRoot,
        registry: registry,
      );
      final report = await supervisor.converge(
        desired: desired,
        factory: observeOnlyFactory(modelServePort: ModelServeFacts.port),
        apply: false,
      );
      expect(report.invalid, isFalse);
      expect(report.plan.actions, isEmpty);
      expect(report.started, 0);
      expect(report.restarted, 0);
      expect(report.failedStarts, 0);
      final findings = report.plan.findings
          .map((final finding) => finding.code)
          .toSet();
      expect(findings, isNot(contains('giveUp')));
    },
  );

  test(
    'converge(apply: false) on an empty registry surfaces the gap',
    () async {
      final desired = desiredComposition();
      final root = await Directory.systemTemp.createTemp(
        'supervisor_composition',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final registry = MachineRegistry(root: root.path);
      final supervisor = Supervisor(
        projectRoot: '/tmp/supervisor-composition-empty',
        registry: registry,
      );
      final report = await supervisor.converge(
        desired: desired,
        factory: observeOnlyFactory(modelServePort: ModelServeFacts.port),
        apply: false,
      );
      expect(report.invalid, isFalse);
      expect(report.plan.startCount, desired.specs.length);
      expect(report.started, 0);
      // Observe-only converge must not have written any record.
      expect(Directory('${root.path}/records').existsSync(), isFalse);
    },
  );

  test('model-serve readiness matches the discovered dialect', () {
    final spec = desiredComposition().byId()['model-serve']!;
    final readiness = spec.readiness;
    expect(readiness, isA<TcpConnect>());
    final tcp = readiness! as TcpConnect;
    expect(tcp.host, ModelServeFacts.host);
    expect(tcp.host, '127.0.0.1');
    expect(tcp.port, ModelServeFacts.port);
    expect(tcp.port, 8765);
    expect(
      tcp.describe(),
      'tcp connect ${ModelServeFacts.host}:${ModelServeFacts.port}',
    );
  });

  test('model-serve env declares the expected wire model ids', () {
    final spec = desiredComposition().byId()['model-serve']!;
    expect(spec.env['MODEL_ID_EXPECTED'], ModelServeFacts.qwenModelId);
    expect(spec.env['MODEL_ID_FALLBACK'], ModelServeFacts.lfm2ModelId);
    expect(spec.env['SERVE_PORT'], '${ModelServeFacts.port}');
  });

  test('nightly-model-audit is a record-only interval job', () {
    final spec = desiredComposition().byId()['nightly-model-audit']!;
    expect(spec.policy.shape, SupervisionShape.job);
    expect(spec.trigger, isA<IntervalTrigger>());
    final trigger = spec.trigger as IntervalTrigger;
    expect(trigger.period, const Duration(hours: 24));
    expect(spec.trigger.describe(), 'interval:86400s');
    expect(spec.env['AUDIT_CARRIER'], contains('cron'));
  });

  test('a port override re-hashes the declaration (drift is visible)', () {
    final defaultSpec = modelServeSpec();
    final overriddenSpec = modelServeSpec(port: 9999);
    expect(overriddenSpec.revisionHash, isNot(defaultSpec.revisionHash));
    final tcp = overriddenSpec.readiness! as TcpConnect;
    expect(tcp.port, 9999);
  });
}
