import 'dart:convert';
import 'package:universal_automation_toolkit/compose.dart';
import 'package:universal_automation_toolkit/universal_automation_toolkit.dart';

Future<void> main() async {
  final plan = AutomationPlan(
    sessions: [
      SessionBinding(name: 'mac', transport: AutomationTransport.osAccessibility),
    ],
    scenarios: [
      scenario('sense', steps: [
        observe(save: 'desktop'),
        code((context) async {
          final snapshot = await context.driver.snapshot();
          final roles = <String, int>{};
          for (final node in snapshot.nodes) {
            roles[node.role] = (roles[node.role] ?? 0) + 1;
          }
          return {'focusedApp': 'live', 'roles': roles};
        }),
      ]),
    ],
  );
  final report = await PlanRunner(attachTimeout: const Duration(seconds: 20)).run(
    plan,
    scenarioName: 'sense',
  );
  // ignore: avoid_print
  print(const JsonEncoder.withIndent('  ').convert(report.toJson()));
}
