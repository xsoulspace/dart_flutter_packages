import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_automation_toolkit/compose.dart';

void main() {
  group('AutomationPlan', () {
    test('accepts a valid document and exposes typed values', () async {
      final file = File(
        '${Directory.systemTemp.path}/uat-plan-ok-${DateTime.now().microsecondsSinceEpoch}.yaml',
      );
      await file.writeAsString('''
sessions:
  browser:
    transport: cdp
    uri: http://127.0.0.1:9222
profiles:
  humanish:
    rhythm:
      beforeAction: {kind: fixed, micros: 0}
    reaction: {floorUs: 0}
    pacing: {noiseEventGrid: 0, driftPerHourUs: 0}
    pointer:
      path: {kind: direct}
      moveDuration: {kind: fixed, micros: 0}
      buttonHold: {kind: fixed, micros: 0}
      maxStepPx: 24
    cadence:
      digraph: {kind: fixed, micros: 0}
      hold: {kind: fixed, micros: 0}
intents:
  - app: webshop
    intents:
      - name: checkout
        title: Checkout
        hint: {driver: cdp, action: click, locator: {name: Submit}}
scenarios:
  browse:
    steps:
      - navigate: {url: 'http://127.0.0.1:9222/#form'}
      - act: {click: {name: Submit}}
      - verify:
          - exists: {role: textbox, name: Email}
      - wait:
          checks: [{urlContains: done}]
          timeout: 2
      - screenshot: shot.png
  buy:
    extends: browse
    steps:
      - intent: {app: webshop, name: checkout}
''');
      addTearDown(() => file.deleteSync());

      final plan = await AutomationPlan.load(file.path);
      expect(plan.sessions.keys, ['browser']);
      expect(plan.profiles.keys, ['humanish']);
      expect(plan.intents.intent('webshop', 'checkout'), isNotNull);
      expect(plan.scenarios.keys, containsAll(['browse', 'buy']));
      final effective = plan.effectiveSteps('buy');
      expect(effective.length, 6);
      expect(effective.last.kind, 'intent');
      expect(plan.validate(), isEmpty);
    });

    test('collects every violation before anything runs (fail closed)',
        () async {
      final file = File(
        '${Directory.systemTemp.path}/uat-plan-bad-${DateTime.now().microsecondsSinceEpoch}.yaml',
      );
      await file.writeAsString('''
sessions:
  browser:
    transport: cdp
    uri: http://127.0.0.1:9222
  other:
    transport: webdriver
    uri: http://127.0.0.1:9515
scenarios:
  broken:
    steps:
      - act: {click: {}}
      - act: {click: {name: X}, session: ghost, profile: nope}
      - verify: []
      - intent: {app: webshop, name: missing}
''');
      addTearDown(() => file.deleteSync());

      await expectLater(
        AutomationPlan.load(file.path),
        throwsA(
          isA<SpecViolationException>().having(
            (error) => error.violations,
            'violations',
            containsAll([
              contains('click needs css, role, or name'),
              contains('unknown session "ghost"'),
              contains('unknown behavior profile "nope"'),
              contains('verify needs a non-empty list'),
              contains('unknown intent "webshop/missing"'),
              contains('does not declare exactly one session'),
            ]),
          ),
        ),
      );
    });

    test('include merges sections and conflicts are violations', () async {
      final dir = Directory.systemTemp.createTempSync('uat-include');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/base.yaml').writeAsStringSync('''
sessions:
  browser:
    transport: cdp
    uri: http://127.0.0.1:9222
''');
      final main = File('${dir.path}/main.yaml');
      await main.writeAsString('''
include: [base.yaml]
sessions:
  browser:
    transport: cdp
    uri: http://127.0.0.1:9999
scenarios:
  s:
    steps:
      - observe: null
''');
      await expectLater(
        AutomationPlan.load(main.path),
        throwsA(
          isA<SpecViolationException>().having(
            (error) => error.violations,
            'violations',
            everyElement(contains('redefines "sessions.browser"')),
          ),
        ),
      );
    });

    test('json round-trip: document values survive toJson → load', () async {
      final plan = AutomationPlan(
        sessions: [cdp('browser', uri: Uri.parse('http://127.0.0.1:1'))],
        intents: IntentRegistry([
          IntentManifest(
            app: 'app',
            intents: [
              AppIntent(
                name: 'go',
                hint: IntentHint(
                  driver: 'cdp',
                  verb: IntentVerb.navigate,
                  locator: {'route': 'http://127.0.0.1:1/x'},
                ),
              ),
            ],
          ),
        ]),
        scenarios: [
          scenario(
            's',
            steps: [
              observe(save: 'home'),
              navigate(Uri.parse('http://127.0.0.1:1/x')),
              click(name: 'Submit'),
              typeText('hi', css: '#q', submit: true),
              keyPress('Escape'),
              scrollBy(distance: 120),
              verifyThat([exists(role: 'button'), absent(name: 'Err'),
                  value('Email', contains: '@'), urlContains('/x')]),
              waitFor([exists(name: 'Done')], timeout: const Duration(seconds: 3)),
              shot('/tmp/x.png'),
              intent('app', 'go'),
            ],
          ),
        ],
      );
      final file = File(
        '${Directory.systemTemp.path}/uat-roundtrip-${DateTime.now().microsecondsSinceEpoch}.json',
      );
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(plan.toJson()),
      );
      addTearDown(() => file.deleteSync());

      final reloaded = await AutomationPlan.load(file.path);
      expect(reloaded.validate(), isEmpty);
      expect(
        reloaded.effectiveSteps('s').map((step) => step.kind).toList(),
        ['observe', 'act', 'act', 'act', 'act', 'act', 'verify', 'wait',
            'screenshot', 'intent'],
      );
    });

    test('intent hints lower to actions with invocation args', () {
      final hint = IntentHint(
        driver: 'cdp',
        verb: IntentVerb.type,
        locator: {'css': '#email'},
      );
      final action = hint.lowerToAction(
        args: {'text': 'a@b.c'},
        label: 'test',
      );
      expect(action, isA<TypeAction>());
      expect((action as TypeAction).css, '#email');

      final custom = IntentHint(
        driver: 'cdp',
        verb: IntentVerb.custom,
        locator: {'name': 'checkout'},
      );
      final invoked = custom.lowerToAction(args: {'sku': '42'}, label: 't');
      expect(invoked, isA<InvokeAction>());
      expect((invoked as InvokeAction).args, {'sku': '42'});

      expect(
        () => hint.lowerToAction(args: const {}, label: 'test'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
