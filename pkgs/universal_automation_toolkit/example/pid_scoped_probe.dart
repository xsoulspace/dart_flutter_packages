/// Live probe for the ADR 0064 pid-scoped event rung: anchors a real
/// TextEdit instance (the `ax://pid/<n>` session shape), writes it in
/// the background via `setValue`, then TYPES into it with
/// `CGEventPostToPid` while another application owns the user's focus —
/// the typed text must land in the target and the focus must never
/// move. Pointer verbs stay focus-bound; the probe records that
/// refusal too.
///
/// Run from this package (macOS, Accessibility + Screen Recording
/// granted): `dart run example/pid_scoped_probe.dart <evidence-dir>`
import 'dart:convert';
import 'dart:io';

import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:universal_driver_macos/universal_driver_macos.dart';

Future<void> main(List<String> args) async {
  final evidenceDir = args.isNotEmpty ? args[0] : 'build/pid-scoped-evidence';
  Directory(evidenceDir).createSync(recursive: true);
  final evidence = <String, Object?>{
    'schema': 'pid-scoped-rung-evidence/v1',
    'date': DateTime.now().toUtc().toIso8601String(),
  };
  final failures = <String>[];

  void check(String name, bool ok, [Object? detail]) {
    evidence[name] = {'ok': ok, if (detail != null) 'detail': detail};
    if (!ok) failures.add(name);
    stderr.writeln('${ok ? "PASS" : "FAIL"} $name');
  }

  // -- 0. The focus baseline. --
  final observer = MacosDriver(snapshotMaxNodes: 5000);
  if (!observer.axTrusted) {
    stderr.writeln('Accessibility not granted; the probe cannot run.');
    exit(2);
  }
  final frontmostBefore = await observer.frontmost();

  // -- 1. Launch TextEdit on a known file WITHOUT ever touching the
  //       focus: `open -g` opens in background. A leftover TextEdit
  //       from an earlier probe (possibly frontmost) is quit first —
  //       activation dances cannot move focus away from it reliably,
  //       and a mid-transition app drops pid-posted events. --
  await Process.run('pkill', ['-x', 'TextEdit']);
  await Future<void>.delayed(const Duration(milliseconds: 500));
  final doc = File('/tmp/uat-pid-scoped.txt');
  doc.writeAsStringSync('seed line\n');
  final open = await Process.run('open', ['-g', '-a', 'TextEdit', doc.path]);
  check(
    'launchTextEditBackground',
    open.exitCode == 0,
    open.stderr.toString().trim(),
  );
  int? pid;
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (pid == null && DateTime.now().isBefore(deadline)) {
    final apps = await observer.runningApps();
    pid = apps
        .where((app) => app.bundleId == 'com.apple.TextEdit')
        .map((app) => app.pid)
        .firstOrNull;
    if (pid == null)
      await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  check('textEditRunning', pid != null, 'pid=$pid');
  if (pid == null) exit(1);
  evidence['frontmostBefore'] = {
    'name': frontmostBefore.name,
    'pid': frontmostBefore.pid,
  };
  evidence['textEditPid'] = pid;

  try {
    // The anchored session: same shape as `ax://pid/<pid>` over MCP.
    final driver = MacosDriver(targetPid: pid, snapshotMaxNodes: 5000);
    check(
      'capabilitiesDeclarePidScopedEvents',
      driver.capabilities.pidScopedEvents,
    );

    // -- 2. Anchored observation: the background read. The document
    //       window builds asynchronously — poll until the textarea
    //       exists rather than sleeping unconditionally. --
    Snapshot? snapshot;
    for (var attempt = 0; attempt < 30 && snapshot == null; attempt++) {
      final candidate = await driver.snapshot();
      snapshot = candidate.nodes.any((node) => node.role == 'textbox')
          ? candidate
          : null;
      if (snapshot == null) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }
    if (snapshot == null) {
      throw StateError('no textbox appeared in the TextEdit tree');
    }
    final textbox = snapshot.nodes.firstWhere((node) => node.role == 'textbox');
    check('anchoredObservation', true, {
      'nodeCount': snapshot.nodes.length,
      'textboxName': textbox.name,
    });

    // -- 3. Background semantic write: setValue, verified by diff. --
    final marker = 'pid-scoped ${DateTime.now().toUtc().toIso8601String()}';
    await driver.perform(SetValueAction(marker, role: 'textbox'));
    var after = await driver.snapshot();
    var value = after.nodes.firstWhere((node) => node.role == 'textbox').value;
    check('backgroundSetValue', value == marker, {'after': value});

    // -- 4. THE RUNG: typed text posts to the target's event queue
    //       while another app owns the focus. Fire-and-forget delivery;
    //       the AX read-back is the proof. --
    const suffix = ' + pid-typed';
    await driver.perform(const TypeAction(suffix));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    after = await driver.snapshot();
    value =
        after.nodes.firstWhere((node) => node.role == 'textbox').value ?? '';
    check('pidScopedTyping', value.contains('$marker$suffix'), {
      'after': value,
      'expectedSuffix': suffix,
    });

    // -- 5. The rung does not extend to pointer verbs: scroll still
    //       refuses on the anchored session. --
    try {
      await driver.perform(const ScrollAction(distance: 3));
      check('pointerVerbsStayFocusBound', false, 'ScrollAction did not refuse');
    } on ForegroundRequiredException catch (error) {
      check('pointerVerbsStayFocusBound', true, {
        'targetPid': error.targetPid,
        'frontmostPid': error.frontmostPid,
      });
    }

    // -- 6. Occluded window capture: pixels without raising the window. --
    final windows = await driver.windows(pid: pid);
    if (windows.isNotEmpty) {
      final png = await driver.windowScreenshot(windows.first.windowId);
      final path = '$evidenceDir/textedit-window.png';
      File(path).writeAsBytesSync(png);
      check('windowCapture', png.length > 1000, {
        'path': path,
        'bytes': png.length,
      });
    } else {
      check('windowCapture', false, 'no windows reported');
    }

    // -- 7. The user's focus never moved through any of this. --
    final frontmostAfter = await driver.frontmost();
    check('focusUnchanged', frontmostAfter.pid == frontmostBefore.pid, {
      'before': '${frontmostBefore.name} (${frontmostBefore.pid})',
      'after': '${frontmostAfter.name} (${frontmostAfter.pid})',
    });
  } finally {
    // The probe owns its TextEdit instance; leave the machine clean.
    await Process.run('pkill', ['-x', 'TextEdit']);
    await observer.close();
  }

  evidence['allOk'] = failures.isEmpty;
  File(
    '$evidenceDir/evidence.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(evidence));
  // ignore: avoid_print
  print('evidence: ${File('$evidenceDir/evidence.json').absolute.path}');
  exit(failures.isEmpty ? 0 : 1);
}
