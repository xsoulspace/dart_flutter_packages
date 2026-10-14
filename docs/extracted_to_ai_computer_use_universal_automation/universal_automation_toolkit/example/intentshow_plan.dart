import 'dart:convert';
import 'dart:io';

import 'package:universal_automation_toolkit/compose.dart';
import 'package:universal_automation_toolkit/universal_automation_toolkit.dart';

/// The intentshow: a works/breaks verification matrix for the intentcall
/// integration, driven live over real Chrome.
///
/// Data files (the "dat" half of the showcase):
/// - `showcase/intentshow.capture.json` — captured-shape MCP tools
///   payload (the dev.intentcall/automation projection); ingested via
///   [IntentRegistry.fromMcpToolsList].
/// - `showcase/intentshow.snapshot.json` — the exported plan snapshot
///   (planDocument), written on every run.
/// - `showcase/last-run.json` — the runner report, i.e. the works/breaks
///   matrix itself.
///
/// The plan self-verifies: every WORKS step must pass, every KNOWN-BREAK
/// step must fail with the expected error kind — a mismatch exits 1.
Future<void> main() async {
  final showcaseDir = '${Directory.current.path}/showcase';
  final registry = IntentRegistry.fromMcpToolsList(
    jsonDecode(
      File('$showcaseDir/intentshow.capture.json').readAsStringSync(),
    ),
    app: 'page',
  );

  final page = Uri.dataFromString(
    '<!DOCTYPE html><html><head><title>intentshow</title></head><body>'
    '<h1>intent showcase</h1>'
    '<input id="email" aria-label="Email" '
    'onkeydown="if (event.key === \'Enter\') stamp(\'submitted\')">'
    '<button aria-label="Buy" onclick="buy()">Buy</button>'
    '<div id="status" aria-live="polite"></div>'
    '<script>'
    'function buy() { stamp("bought"); }'
    'function stamp(text) {'
    '  document.getElementById("status").textContent = text;'
    '}'
    'window.__mcpActions = {'
    '  checkout: {'
    '    description: "checkout the cart",'
    '    invoke: async (args) => stamp("checked-out:" + args.sku),'
    '  },'
    '};'
    '</script></body></html>',
    mimeType: 'text/html',
  );
  final chrome = Uri.parse(
    Platform.environment['UAT_CDP'] ?? 'http://127.0.0.1:9333',
  );

  // —— WORKS: every step must pass ——————————————————————————————————
  final works = AutomationPlan(
    sessions: [cdp('chrome', uri: chrome)],
    intents: registry,
    scenarios: [
      scenario('works', steps: [
        navigate(page),
        waitFor([exists(role: 'heading', name: 'intent showcase')]),
        intent('page', 'page_fill_email', args: {'text': 'antonio@example.com'}),
        verifyThat([value('Email', equals: 'antonio@example.com')]),
        intent('page', 'page_buy'),
        verifyThat([exists(nameContains: 'bought')]),
        intent('page', 'page_checkout', args: {'sku': 'SKU-1'}),
        verifyThat([exists(nameContains: 'checked-out:SKU-1')]),
        intent('page', 'page_stamp'),
        verifyThat([exists(nameContains: 'stamped')]),
        intent('page', 'page_buy', session: 'chrome'),
        verifyThat([exists(nameContains: 'bought')]),
        intent('page', 'page_fill_email', args: {'text': 'x'}),
        intent('page', 'page_submit_email'),
        verifyThat([exists(nameContains: 'submitted')]),
      ]),
    ],
  );
  final worksReport = await PlanRunner(
    attachTimeout: const Duration(seconds: 20),
  ).run(works, scenarioName: 'works', outDir: '$showcaseDir/out');

  // —— KNOWN-BREAKS: every step must fail with its expected error ————
  final breaks = AutomationPlan(
    sessions: [cdp('chrome', uri: chrome)],
    intents: registry,
    scenarios: [
      scenario('breaks', steps: [
        navigate(page),
        soft(intent('page', 'page_ghost_click')),
        soft(intent('page', 'page_ghost_invoke')),
      ]),
    ],
  );
  final breaksReport = await PlanRunner(
    attachTimeout: const Duration(seconds: 20),
  ).run(breaks, scenarioName: 'breaks', outDir: '$showcaseDir/out');

  // —— Validate-level break: a type intent whose invocation forgot its
  // text must be refused before anything runs. ————————————————————————
  final validateBreaks = AutomationPlan(
    sessions: [cdp('chrome', uri: chrome)],
    intents: registry,
    scenarios: [
      scenario('s', steps: [intent('page', 'page_fill_email')]),
    ],
  );
  final validateViolations = validateBreaks.validate();
  final validateRefusal =
      validateViolations.isEmpty ? '' : validateViolations.first;

  // —— The matrix ————————————————————————————————————————————————————
  final expectedBreaks = {
    1: 'elementNotFound',
    2: 'protocol',
  };
  final matrix = <String, Object?>{
    'works': [
      for (final step in worksReport.steps)
        {
          'index': step.index,
          'kind': step.kind,
          'ok': step.ok,
          if (!step.ok) 'errorKind': step.errorKind,
        },
    ],
    'breaks': [
      for (final step in breaksReport.steps)
        {
          'index': step.index,
          'kind': step.kind,
          'ok': step.ok,
          'errorKind': step.errorKind,
        },
    ],
    'validateRefusal': validateRefusal,
  };
  File(
    '$showcaseDir/last-run.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(matrix));
  File(
    '$showcaseDir/intentshow.snapshot.json',
  ).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(planDocument(works)),
  );

  var failures = 0;
  for (final step in worksReport.steps) {
    if (!step.ok) {
      failures++;
      // ignore: avoid_print
      print('✗ WORKS step ${step.index} (${step.kind}) failed: '
          '${step.errorKind}: ${step.errorMessage}');
    }
  }
  for (final entry in expectedBreaks.entries) {
    final step = breaksReport.steps[entry.key];
    if (step.ok || step.errorKind != entry.value) {
      failures++;
      // ignore: avoid_print
      print('✗ BREAK step ${entry.key} expected ${entry.value}, got '
          '${step.ok ? "passed" : step.errorKind}');
    }
  }
  if (!validateRefusal.contains('text')) {
    failures++;
    // ignore: avoid_print
    print('✗ validate refusal missing: $validateRefusal');
  }

  // ignore: avoid_print
  print('matrix: '
      '${worksReport.steps.where((s) => s.ok).length} works / '
      '${expectedBreaks.length} known-breaks; '
      'refusal: $validateRefusal');
  if (failures > 0) {
    exit(1);
  }
  // ignore: avoid_print
  print('SHOWCASE OK — see showcase/last-run.json');
}
