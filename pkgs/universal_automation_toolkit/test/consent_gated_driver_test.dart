import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:universal_automation_toolkit/universal_automation_toolkit.dart';
import 'package:universal_driver_macos/universal_driver_macos.dart';
import 'package:xsoulspace_permission_core/xsoulspace_permission_core.dart';

/// A driver that counts calls and can refuse like a real TCC-gated one.
final class _CountingDriver implements AutomationDriver {
  int snapshots = 0;
  int screenshots = 0;
  final performs = <AutomationAction>[];

  @override
  DriverCapabilities get capabilities => const DriverCapabilities(
    a11yTree: true,
    inputSynthesis: true,
    screenshot: true,
  );

  @override
  Future<Snapshot> snapshot() async {
    snapshots++;
    return Snapshot(
      roots: const [AxNode(role: 'application', name: 'app')],
      capturedAt: DateTime.now().toUtc(),
      revision: 1,
    );
  }

  @override
  Future<void> perform(AutomationAction action) async {
    performs.add(action);
  }

  @override
  Future<Uint8List> screenshot() async {
    screenshots++;
    return Uint8List.fromList(const [1, 2, 3]);
  }

  @override
  Future<void> close() async {}
}

/// A policy that answers every request with [decision].
final class _ScriptedPolicy implements PermissionPolicy {
  _ScriptedPolicy(this.decision);

  final PermissionDecision decision;

  @override
  PermissionDecision decide(PermissionRequest request) => decision;
}

void main() {
  test('deny refuses before the driver is touched', () async {
    final driver = _CountingDriver();
    final gated = ConsentGatedDriver(
      driver,
      gate: PermissionGate(
        policies: [
          _KindScriptedPolicy(const {
            PermissionKind.screenRecording: PermissionDeny(
              'screen capture off-limits',
            ),
            PermissionKind.accessibility: PermissionAllow(
              PermissionGrantScope.session,
            ),
          }),
        ],
      ),
    );
    await expectLater(
      gated.screenshot(),
      throwsA(
        isA<ConsentRequiredException>()
            .having((e) => e.kind, 'kind', 'consentRequired')
            .having(
              (e) => e.details['permissionKind'],
              'permissionKind',
              'screenRecording',
            )
            .having((e) => e.message, 'message', contains('off-limits')),
      ),
    );
    expect(driver.screenshots, 0, reason: 'the refusal precedes the call');
    // The accessibility kind was never asked and never refused.
    await gated.snapshot();
    expect(driver.snapshots, 1);
  });

  test('allow passes through and caches per kind', () async {
    final driver = _CountingDriver();
    var asked = 0;
    final gated = ConsentGatedDriver(
      driver,
      gate: PermissionGate(
        policies: [
          _PermissionRecordingPolicy((request) {
            asked++;
            return const PermissionAllow(PermissionGrantScope.session);
          }),
        ],
      ),
    );
    await gated.snapshot();
    await gated.snapshot();
    await gated.perform(const ClickAction(name: 'Save'));
    expect(asked, 1, reason: 'one accessibility allow covers both verbs');
    expect(driver.snapshots, 2);
    expect(driver.performs, hasLength(1));

    await gated.screenshot();
    expect(asked, 2, reason: 'screenRecording is a separate consent');
    expect(driver.screenshots, 1);
  });

  test('once-scope allow authorizes exactly one call', () async {
    final driver = _CountingDriver();
    final gated = ConsentGatedDriver(
      driver,
      gate: PermissionGate(
        policies: [
          _ScriptedPolicy(const PermissionAllow(PermissionGrantScope.once)),
        ],
      ),
    );
    await gated.snapshot();
    await gated.snapshot();
    expect(driver.snapshots, 2, reason: 'each call re-asked and passed');
  });

  test(
    'escalation resolves through the sink; an escaped one refuses',
    () async {
      final driver = _CountingDriver();
      var escalated = false;
      final gated = ConsentGatedDriver(
        driver,
        gate: PermissionGate(
          policies: [_ScriptedPolicy(PermissionEscalate(to: 'user'))],
          onEscalate: (request) async {
            escalated = true;
            expect(request.kind, PermissionKind.accessibility);
            return const PermissionAllow(PermissionGrantScope.session);
          },
        ),
      );
      await gated.snapshot();
      expect(escalated, isTrue);
      expect(driver.snapshots, 1);
    },
  );

  test('an allow is not a TCC grant — the driver refusal surfaces', () async {
    // A driver whose OS grant is missing still refuses on its own.
    final gated = ConsentGatedDriver(
      _NoTccDriver(),
      gate: PermissionGate(
        policies: [
          _ScriptedPolicy(PermissionAllow(PermissionGrantScope.always)),
        ],
      ),
    );
    await expectLater(
      gated.snapshot(),
      throwsA(isA<AccessibilityPermissionRequiredException>()),
    );
  });
}

final class _NoTccDriver implements AutomationDriver {
  @override
  DriverCapabilities get capabilities =>
      const DriverCapabilities(a11yTree: true, inputSynthesis: true);

  @override
  Future<Snapshot> snapshot() async =>
      throw const AccessibilityPermissionRequiredException();

  @override
  Future<void> perform(AutomationAction action) async {}

  @override
  Future<Uint8List> screenshot() async => Uint8List(0);

  @override
  Future<void> close() async {}
}

/// Records each request, then answers with the scripted decision.
final class _PermissionRecordingPolicy implements PermissionPolicy {
  _PermissionRecordingPolicy(this._decide);

  final PermissionDecision Function(PermissionRequest request) _decide;
  final requests = <PermissionRequest>[];

  @override
  PermissionDecision decide(PermissionRequest request) {
    requests.add(request);
    return _decide(request);
  }
}

/// Answers exactly the kinds in the table; escalates everything else so
/// the structural deny-by-default (no sink) covers the rest.
final class _KindScriptedPolicy implements PermissionPolicy {
  const _KindScriptedPolicy(this.table);

  final Map<PermissionKind, PermissionDecision> table;

  @override
  PermissionDecision decide(PermissionRequest request) =>
      table[request.kind] ??
      PermissionEscalate(reason: 'not in the scripted table');
}
