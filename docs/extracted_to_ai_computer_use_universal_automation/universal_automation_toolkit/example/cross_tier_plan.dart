import 'dart:convert';
import 'package:universal_automation_toolkit/compose.dart';
import 'package:universal_automation_toolkit/universal_automation_toolkit.dart';

/// The "everything together" proof: one plan, two tiers — the macOS AX
/// tier observing the focused app while the CDP tier drives Chromium —
/// in a single scenario.
Future<void> main() async {
  final plan = AutomationPlan(
    sessions: [
      SessionBinding(name: 'mac', transport: AutomationTransport.osAccessibility),
      cdp('chrome', uri: Uri.parse('http://127.0.0.1:9333')),
    ],
    scenarios: [
      scenario('cross-tier', steps: [
        observe(session: 'mac', save: 'finder'),
        navigate(
          Uri.parse('data:text/html,<h1>browser tier</h1>'),
          session: 'chrome',
        ),
        waitFor(
          [exists(role: 'heading', name: 'browser tier')],
          session: 'chrome',
        ),
        code((context) async => {'tier': 'dart code step'}, session: 'chrome'),
        verifyThat([exists(role: 'application')], session: 'mac'),
      ]),
    ],
  );
  final report = await PlanRunner(
    attachTimeout: const Duration(seconds: 20),
  ).run(plan, scenarioName: 'cross-tier');
  // ignore: avoid_print
  print(const JsonEncoder.withIndent('  ').convert(report.toJson()));
}
