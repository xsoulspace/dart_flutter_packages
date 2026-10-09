import 'dart:convert';
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

  test('runs a scenario end-to-end over CDP and reports structured steps',
      () async {
    final plan = AutomationPlan(
      sessions: [cdp('browser', uri: endpoint)],
      scenarios: [
        scenario('full', steps: [
          navigate(Uri.parse('$endpoint/#form')),
          waitFor([exists(role: 'button', name: 'Submit')]),
          typeText('antonio@example.com', css: '#email'),
          observe(save: 'form'),
          click(name: 'Submit'),
          verifyThat([
            exists(role: 'textbox', name: 'Email'),
            absent(name: 'Error'),
            urlContains('#form'),
          ]),
        ]),
      ],
    );

    final outDir = Directory.systemTemp.createTempSync('uat-runner');
    addTearDown(() => outDir.deleteSync(recursive: true));

    final report = await PlanRunner().run(
      plan,
      scenarioName: 'full',
      outDir: outDir.path,
    );

    expect(report.ok, isTrue);
    expect(report.scenario, 'full');
    expect(
      report.steps.map((step) => step.kind).toList(),
      ['act', 'wait', 'act', 'observe', 'act', 'verify'],
    );
    expect(report.steps.every((step) => step.ok), isTrue);
    // The css-locator type dispatches per-key events, the semantic click
    // lands at the element center: real input reached the fake.
    expect(
      fake.inputEvents.map((event) => event['method']),
      containsAll(['Input.dispatchKeyEvent', 'Input.dispatchMouseEvent']),
    );
    expect(fake.currentUrl, contains('#form'));
    // The observe step embedded the full snapshot under its save name.
    expect(report.steps[3].detail.containsKey('form'), isTrue);
  });

  test('a failed verify aborts remaining steps and marks the run failed',
      () async {
    final plan = AutomationPlan(
      sessions: [cdp('browser', uri: endpoint)],
      scenarios: [
        scenario('s', steps: [
          verifyThat([exists(name: 'NoSuchThing')]),
          navigate(Uri.parse('$endpoint/x')),
        ]),
      ],
    );

    final report = await PlanRunner().run(plan);
    expect(report.ok, isFalse);
    expect(report.steps[0].ok, isFalse);
    expect(report.steps[0].errorKind, 'verificationFailed');
    expect(report.steps[1].skipped, isTrue);
    expect(fake.methods, isNot(contains('Page.navigate')));
  });

  test('wait reports waitTimeout with the last reasons', () async {
    final plan = AutomationPlan(
      sessions: [cdp('browser', uri: endpoint)],
      scenarios: [
        scenario('s', steps: [
          waitFor(
            [exists(name: 'Never')],
            timeout: const Duration(milliseconds: 400),
            poll: const Duration(milliseconds: 80),
          ),
        ]),
      ],
    );

    final report = await PlanRunner().run(plan);
    expect(report.ok, isFalse);
    expect(report.steps.single.errorKind, 'waitTimeout');
  });

  test('continueOnFailure records and proceeds', () async {
    final plan = AutomationPlan(
      sessions: [cdp('browser', uri: endpoint)],
      scenarios: [
        scenario('s', steps: [
          soft(verifyThat([exists(name: 'NoSuchThing')])),
          navigate(Uri.parse('$endpoint/x')),
        ]),
      ],
    );

    final report = await PlanRunner().run(plan);
    expect(report.ok, isTrue);
    expect(report.steps[0].ok, isFalse);
    expect(report.steps[1].ok, isTrue);
  });

  test('profiled dispatch lowers through the behavior contract and writes '
      'receipts', () async {
    final outDir = Directory.systemTemp.createTempSync('uat-behavior');
    addTearDown(() => outDir.deleteSync(recursive: true));

    final plan = AutomationPlan(
      sessions: [cdp('browser', uri: endpoint)],
      profiles: {'humanish': BehaviorProfile.humanPrior(42)},
      scenarios: [
        scenario('s', steps: [
          click(name: 'Submit', profile: 'humanish', seed: 7),
        ]),
      ],
    );

    final report = await PlanRunner().run(plan, outDir: outDir.path);
    expect(report.ok, isTrue);
    expect(report.steps.single.detail['profile'], 'humanish');
    expect(report.steps.single.detail['verdict'], 'complete');
    expect(report.receipts, hasLength(2));
    final envelope = jsonDecode(
      File(report.receipts[1]).readAsStringSync().split('\n').first,
    ) as Map<String, Object?>;
    expect(envelope['schema'], 'behavior.receipts/v1');
    expect(envelope['profileHash'], isNotEmpty);
  });

  test('intent steps resolve through the registry and lower to actions',
      () async {
    final plan = AutomationPlan(
      sessions: [cdp('browser', uri: endpoint)],
      intents: IntentRegistry([
        IntentManifest(
          app: 'webshop',
          intents: [
            AppIntent(
              name: 'checkout',
              hint: IntentHint(
                driver: 'cdp',
                verb: IntentVerb.type,
                locator: {'css': '#email'},
              ),
            ),
          ],
        ),
      ]),
      scenarios: [
        scenario('s', steps: [
          intent('webshop', 'checkout', args: {'text': 'antonio@example.com'}),
        ]),
      ],
    );

    final report = await PlanRunner().run(plan);
    expect(report.ok, isTrue);
    expect(
      fake.inputEvents.map((event) => event['method']),
      contains('Input.dispatchKeyEvent'),
    );
  });

  test('a view hint closes the intent loop through the declared view',
      () async {
    final plan = AutomationPlan(
      sessions: [cdp('browser', uri: endpoint)],
      intents: IntentRegistry([
        IntentManifest(
          app: 'webshop',
          intents: [
            AppIntent(
              name: 'checkout',
              hint: IntentHint(
                driver: 'cdp',
                verb: IntentVerb.click,
                locator: {'name': 'Submit'},
                viewHint: const SemanticView(maxNodes: 3),
              ),
            ),
          ],
        ),
      ]),
      scenarios: [
        scenario('s', steps: [intent('webshop', 'checkout')]),
      ],
    );

    final report = await PlanRunner().run(plan);
    expect(report.ok, isTrue);
    // The step result carries the post-action state render.
    expect((report.steps.single.detail['state'] as String), contains('Submit'));
  });

  test('screenshot writes the PNG artifact under outDir', () async {
    final outDir = Directory.systemTemp.createTempSync('uat-shot');
    addTearDown(() => outDir.deleteSync(recursive: true));

    final plan = AutomationPlan(
      sessions: [cdp('browser', uri: endpoint)],
      scenarios: [
        scenario('s', steps: [shot('shot.png')]),
      ],
    );

    final report = await PlanRunner().run(plan, outDir: outDir.path);
    expect(report.ok, isTrue);
    final file = File('${outDir.path}/shot.png');
    expect(file.existsSync(), isTrue);
    expect(file.lengthSync(), greaterThan(0));
  });

  test('an unresolvable handle binding fails loudly with the override hint',
      () async {
    final plan = AutomationPlan(
      sessions: [cdp('browser', handle: 'session-browser-handle')],
      scenarios: [
        scenario('s', steps: [observe()]),
      ],
    );

    final report = await PlanRunner().run(plan);
    expect(report.ok, isFalse);
    expect(report.steps.single.errorKind, 'endpointUnreachable');
    expect(report.steps.single.errorMessage, contains('--set'));
  });

  test('a handle binding resolves through session overrides', () async {
    final plan = AutomationPlan(
      sessions: [cdp('browser', handle: 'session-browser-handle')],
      scenarios: [
        scenario('s', steps: [observe()]),
      ],
    );

    final report = await PlanRunner().run(
      plan,
      sessionOverrides: {'session-browser-handle': '$endpoint'},
    );
    expect(report.ok, isTrue);
    expect(report.steps.single.ok, isTrue);
  });
}
