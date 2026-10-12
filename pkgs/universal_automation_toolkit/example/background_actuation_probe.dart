/// Live probe for ADR 0064 background actuation: anchors a real
/// TextEdit instance, reads and writes its accessibility tree WITHOUT
/// activating it, records the focus contract's refusal of a global
/// verb, captures the occluded window, and runs the same flow as a
/// resident background job through the MCP server.
///
/// Run from this package (macOS, Accessibility + Screen Recording
/// granted): `dart run example/background_actuation_probe.dart
/// <evidence-dir>`
import 'dart:convert';
import 'dart:io';

import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:universal_automation_toolkit/universal_automation_toolkit.dart';
import 'package:universal_driver_macos/universal_driver_macos.dart';

Future<void> main(List<String> args) async {
  final evidenceDir = args.isNotEmpty ? args[0] : 'build/bg-actuation-evidence';
  Directory(evidenceDir).createSync(recursive: true);
  // Real app trees front-load their menu bar (hundreds of nodes before
  // the window content); the probe needs room past them.
  final driver = MacosDriver(snapshotMaxNodes: 5000);
  final evidence = <String, Object?>{
    'schema': 'background-actuation-evidence/v1',
    'date': DateTime.now().toUtc().toIso8601String(),
  };
  final failures = <String>[];

  void check(String name, bool ok, [Object? detail]) {
    evidence[name] = {'ok': ok, if (detail != null) 'detail': detail};
    if (!ok) failures.add(name);
    stderr.writeln('${ok ? "PASS" : "FAIL"} $name');
  }

  if (!driver.axTrusted) {
    stderr.writeln('Accessibility not granted; the probe cannot run.');
    exit(2);
  }

  // -- 0. The focus baseline: whatever the user is using stays there. --
  final frontmostBefore = await driver.frontmost();
  evidence['frontmostBefore'] = frontmostBefore.name;

  // -- 1. Launch TextEdit on a known file WITHOUT activating it. --
  final doc = File('/tmp/uat-bg-evidence.txt');
  doc.writeAsStringSync('seed line\n');
  final open = await Process.run('open', ['-a', 'TextEdit', doc.path]);
  check('launchTextEdit', open.exitCode == 0, open.stderr.toString().trim());
  int? pid;
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (pid == null && DateTime.now().isBefore(deadline)) {
    final apps = await driver.runningApps();
    pid = apps
        .where((app) => app.bundleId == 'com.apple.TextEdit')
        .map((app) => app.pid)
        .firstOrNull;
    if (pid == null) await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  check('textEditRunning', pid != null, 'pid=$pid');
  if (pid == null) exit(1);

  try {
    // -- 2. Background observation: the anchored walk, focus untouched. --
    final snapshot = await driver.snapshotOfApp(pid);
    final textbox = snapshot.nodes.firstWhere(
      (node) => node.role == 'textbox',
      orElse: () => throw StateError('no textbox in the TextEdit tree'),
    );
    check(
      'backgroundObservation',
      true,
      {
        'pid': pid,
        'nodeCount': snapshot.nodes.length,
        'textboxName': textbox.name,
        'axActionsSample': [
          for (final node in snapshot.nodes.take(200))
            if (node.attributes['axActions'] case final actions?) actions,
        ].take(3).toList(),
      },
    );

    // -- 3. Background semantic write: setValue, then verify by diff. --
    final marker = 'bg-actuation ${DateTime.now().toUtc().toIso8601String()}';
    await driver.perform(SetValueAction(marker, role: 'textbox'));
    final after = await driver.snapshotOfApp(pid);
    final valueAfter = after.nodes
        .firstWhere((node) => node.role == 'textbox')
        .value;
    check('backgroundSetValue', valueAfter == marker, {
      'before': textbox.value,
      'after': valueAfter,
    });

    // -- 4. The focus contract: a global verb on the background anchor
    //       refuses instead of stealing focus or typing blind. --
    try {
      await driver.perform(const TypeAction('must not land'));
      check('focusContractRefusal', false, 'TypeAction did not refuse');
    } on ForegroundRequiredException catch (error) {
      check('focusContractRefusal', true, {
        'targetPid': error.targetPid,
        'frontmostPid': error.frontmostPid,
      });
    }

    // -- 5. Occluded window capture: pixels without raising the window. --
    final windows = await driver.windows(pid: pid);
    if (windows.isNotEmpty) {
      final png = await driver.windowScreenshot(windows.first.windowId);
      final path = '$evidenceDir/textedit-window.png';
      File(path).writeAsBytesSync(png);
      check('windowCapture', png.length > 1000, {
        'path': path,
        'bytes': png.length,
        'windowName': windows.first.name,
      });
    } else {
      check('windowCapture', false, 'no windows reported');
    }

    // -- 6. Focus never moved. --
    final frontmostAfter = await driver.frontmost();
    check(
      'focusUnchanged',
      frontmostAfter.pid == frontmostBefore.pid,
      {'before': frontmostBefore.name, 'after': frontmostAfter.name},
    );

    // -- 7. Resident job plane: the same write as a submitted, detached
    //       plan run; the client polls until the receipt is terminal. --
    final plan = File('$evidenceDir/bg-job-plan.yaml');
    final jobMarker = 'resident-job ${DateTime.now().toUtc().toIso8601String()}';
    plan.writeAsStringSync('''
sessions:
  textedit:
    transport: osAccessibility
    uri: ax://pid/$pid
scenarios:
  main:
    steps:
      - act:
          setValue: {role: textbox, value: "$jobMarker"}
          returnState: true
      - verify:
          - value: {locator: {role: textbox}, contains: "resident-job"}
''');
    final server = ToolkitMcpServer(
      defaultTransport: AutomationTransport.osAccessibility,
    );
    final submitted = await server.handle({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'tools/call',
      'params': {
        'name': 'automation_run_background',
        'arguments': {'plan': plan.path},
      },
    });
    final submittedPayload = jsonDecode(
      (((submitted!['result'] as Map)['content'] as List).single
          as Map)['text'] as String,
    ) as Map<String, Object?>;
    final jobId = submittedPayload['jobId'] as String;
    Map<String, Object?>? job;
    final jobDeadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(jobDeadline)) {
      final response = await server.handle({
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'tools/call',
        'params': {
          'name': 'automation_job',
          'arguments': {'jobId': jobId},
        },
      });
      job = jsonDecode(
        (((response!['result'] as Map)['content'] as List).single
            as Map)['text'] as String,
      ) as Map<String, Object?>;
      if (job['status'] == 'succeeded' || job['status'] == 'failed') break;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    final report = job?['report'] as Map<String, Object?>?;
    check('residentJobPlane', job?['status'] == 'succeeded', {
      'jobId': jobId,
      'status': job?['status'],
      'steps': report?['steps'],
    });
    final finalState = await driver.snapshotOfApp(pid);
    check(
      'residentJobEffect',
      finalState.nodes
              .firstWhere((node) => node.role == 'textbox')
              .value
              ?.contains('resident-job') ==
          true,
      {'marker': jobMarker},
    );
  } finally {
    await driver.close();
  }

  File('$evidenceDir/evidence.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(evidence),
  );
  stderr.writeln('evidence: $evidenceDir/evidence.json');
  exit(failures.isEmpty ? 0 : 1);
}
