import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:universal_automation_toolkit/universal_automation_toolkit.dart';
import 'package:universal_driver_macos/universal_driver_macos.dart';

void main() {
  test('every committed declarative plan loads and validates', () async {
    final plansDir = Directory('plans');
    final files =
        plansDir
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.yaml'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    expect(files, isNotEmpty, reason: 'the declarative suite must not empty');

    for (final file in files) {
      final plan = await AutomationPlan.load(file.path);
      expect(
        plan.scenarios,
        isNotEmpty,
        reason: '${file.path} declares no scenario',
      );
      for (final scenario in plan.scenarios.values) {
        expect(scenario.steps, isNotEmpty);
      }
    }
  });

  test('handle-bound sessions take their anchor from the --set override; '
      'without one they fall back to the focused app', () async {
    final plan = await AutomationPlan.load('plans/desktop-smoke.yaml');
    final anchored = SessionRegistry(
      bindings: plan.sessions,
      overrides: const {'app': 'ax://pid/999999999'},
    );
    final session = await anchored.attach('app');
    // The pid anchor binds directly (no running-apps probe); the driver
    // carries it as the ADR 0064 anchor.
    expect(
      (session.asBehavioral()! as MacosDriver).targetPid,
      999999999,
      reason: 'the environment override supplies the anchor',
    );
    await session.detach();

    final fallback = SessionRegistry(bindings: plan.sessions);
    final unfocused = await fallback.attach('app');
    expect(
      (unfocused.asBehavioral()! as MacosDriver).targetPid,
      isNull,
      reason: 'no override = focused-app binding, never a silent guess',
    );
    await unfocused.detach();
  });

  test(
    'the semantic-write wire forms round-trip through the plan model',
    () async {
      final plan = await AutomationPlan.load('plans/semantic-write.yaml');
      final steps = plan.onlyScenario!.steps;
      final act = steps.whereType<ActStep>().toList();
      expect(act, hasLength(1));
      final action = act.single.action;
      expect(action, isA<SetValueAction>());
      final setValue = action as SetValueAction;
      expect(setValue.value, 'declarative write');
      expect(setValue.role, 'textbox');
    },
  );
}
