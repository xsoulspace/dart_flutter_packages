import 'package:universal_automation_toolkit/compose.dart';
import 'package:universal_automation_toolkit/universal_automation_toolkit.dart';
import 'package:universal_browser_cdp/universal_browser_cdp_testing.dart';

/// The toolkit showcase: a Dart-composed plan driving the family's fake
/// CDP server end-to-end — the mcp_flutter showcase-drives precedent.
///
/// Everything is typed and checked by the compiler: sessions, steps,
/// checks, intents, behavior profiles. The same plan values round-trip
/// through the YAML/JSON wire form (see `plan_to_yaml.json` in the
/// package tests); the CLI and MCP server execute the textual face.
///
/// Run: `dart run example/showcase.dart`
Future<void> main() async {
  final fake = FakeCdpServer();
  // Semantic clicks resolve through the AX path: give the canned nodes
  // backend ids the way real CDP reports them.
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
  final endpoint = await fake.start();

  // An app's intent surface — in production this manifest is exported by
  // intentcall; apps own their locators, plans reference intents.
  final intents = IntentRegistry([
    IntentManifest(
      app: 'webshop',
      intents: [
        AppIntent(
          name: 'checkout',
          title: 'Checkout the cart',
          hint: IntentHint(
            driver: 'cdp',
            verb: IntentVerb.click,
            locator: {'name': 'Submit'},
          ),
        ),
      ],
    ),
  ]);

  // The plan, composed in Dart (the primary face).
  final plan = AutomationPlan(
    sessions: [cdp('browser', uri: endpoint)],
    profiles: {'humanish': BehaviorProfile.humanPrior(7)},
    intents: intents,
    scenarios: [
      scenario('browsing', steps: [
        navigate(Uri.parse('$endpoint/#form')),
        waitFor([exists(role: 'textbox', name: 'Email')]),
        typeText('antonio@example.com', css: '#email'),
        verifyThat([exists(role: 'textbox', name: 'Email')]),
        shot('/tmp/uat-showcase-browsing.png'),
      ]),
      scenario('checkout', extend: 'browsing', steps: [
        intent('webshop', 'checkout'),
        verifyThat([absent(name: 'Error')]),
      ]),
      scenario('humanlike', steps: [
        navigate(Uri.parse('$endpoint/#human')),
        soft(click(name: 'Submit', profile: 'humanish', seed: 42)),
      ]),
    ],
  );

  // Validate first (fail closed), then run.
  final violations = plan.validate();
  if (violations.isNotEmpty) {
    // ignore: avoid_print
    print('plan rejected: $violations');
    return;
  }

  final runner = PlanRunner();
  for (final name in ['browsing', 'checkout', 'humanlike']) {
    final report = await runner.run(
      plan,
      scenarioName: name,
      outDir: '/tmp/uat-showcase',
    );
    // ignore: avoid_print
    print('${report.ok ? "PASS" : "FAIL"} $name: '
        '${report.steps.length} steps, receipts: ${report.receipts.length}');
  }

  // The same values as the agent wire form:
  // ignore: avoid_print
  print(plan.toJson().keys.toList());

  await fake.stop();
}
