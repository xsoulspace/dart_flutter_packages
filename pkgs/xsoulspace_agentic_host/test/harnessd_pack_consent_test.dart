// ignore_for_file: lines_longer_than_80_chars

/// P1 trusted-author tier on the DAEMON surface — packConsent wired.
///
/// Today's gate: a jail workspace whose
/// `.dart_tool/harnessd/edit_pack.json` carries an `authored_body` entry
/// (kind `authored_body`, the P1 trusted-author tier —
/// `registerPackExecutable`) plus a session consent plan allowing
/// `pack_write` over the pack path → `editSymbolTool`'s pack load loop
/// realizes the entry through the SYNC consent-plan answer (the async ACP
/// permission round-trip cannot reach a synchronous load loop) and a
/// scripted `apply_executable` lands the consented body.
///
/// Deny-by-default holds: no plan → the entry SKIPS at load (named data),
/// tool construction never crashes, and the apply bounces
/// `unknown edit executable`. Every plan answer lands in the consent
/// audit log.
library;

import 'dart:io';

import 'package:dart_acp_toolkit/dart_acp_toolkit.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_agentic_host/xsoulspace_agentic_host.dart';

const _packPath = '.dart_tool/harnessd/edit_pack.json';
const _executableId = 'dart/author_area';
const _authoredBody = 'return w * h; // trusted-authored';
// code_etl stableId: sym_<file with / → _>_<name>.
const _areaSymbolId = 'sym_lib_geometry.dart_area';

/// A covered Dart package: `area` is expected by the suite (the coverage
/// fence), `dart pub get` pre-pass resolves package:test for the oracles.
Future<Directory> _coveredJail() async {
  final dir = await Directory.systemTemp.createTemp('pack_consent_jail_');
  File('${dir.path}/pubspec.yaml').writeAsStringSync('''
name: span_jail
environment:
  sdk: ^3.0.0
dev_dependencies:
  test: any
''');
  File('${dir.path}/lib/geometry.dart')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('''
int area(int w, int h) {
  return w * h;
}
''');
  File('${dir.path}/test/geometry_test.dart')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('''
import 'package:test/test.dart';
import 'package:span_jail/geometry.dart';

void main() {
  test('area', () {
    expect(area(2, 3), 6);
  });
}
''');
  // The trusted-author PACK: an authored_body entry carried as data (the
  // model never sees the pack file; consent happens at pack-write).
  Directory('${dir.path}/.dart_tool/harnessd').createSync(recursive: true);
  File('${dir.path}/$_packPath').writeAsStringSync('''
{
  "packId": "edit_capture",
  "executables": [
    {
      "id": "$_executableId",
      "kind": "authored_body",
      "params": ["symbolId"],
      "verification": ["analyze", "test"],
      "scope": "lexical",
      "description": "trusted-author area body (consented at pack-write)",
      "authoredBody": "$_authoredBody"
    }
  ]
}
''');
  return dir;
}

Future<({AcpStopReason stop, String updates, String sessionId})> _prompt(
  HarnessAcpBackend backend,
  String text,
) async {
  final sid = await backend.createSession(AcpSessionNewRequest(cwd: _ws!.path));
  final updates = StringBuffer();
  final stop = await backend.prompt(
    AcpPromptRequest(sessionId: sid, prompt: [AcpTextBlock(text)]),
    isCancelled: () => false,
    emit: (u) {
      if (u is AgentMessageChunk) {
        updates.write(
          u.content is AcpTextBlock ? (u.content as AcpTextBlock).text : '',
        );
      }
    },
  );
  return (stop: stop, updates: updates.toString(), sessionId: sid);
}

Directory? _ws;

void main() {
  setUp(() async {
    _ws = await _coveredJail();
    // Host pre-pass: resolve the package before the loop runs (mechanical,
    // zero model tokens) — the oracles (scoped analyze + the workspace
    // convention) must be able to grade.
    final pub = await Process.run(
      'dart',
      ['pub', 'get'],
      workingDirectory: _ws!.path,
    );
    expect(pub.exitCode, 0, reason: '${pub.stdout}${pub.stderr}');
  });
  tearDown(() {
    try {
      _ws!.deleteSync(recursive: true);
    } on Object {
      // best effort
    }
  });

  test(
    'MAIN GATE: a consent plan allowing pack_write realizes the '
    'authored_body pack entry on the daemon edit tool — apply_executable '
    'lands the consented body, the answer is audited',
    () async {
      final backend = HarnessAcpBackend(
        backend: 'open_router',
        meaningProfile: true,
        scripted: true,
      );
      // No permission requester attached → no per-move edit approver —
      // the pack-write consent is plan-only (SYNC): it must realize the
      // entry without any ACP round-trip.
      final sid = await backend.createSession(
        AcpSessionNewRequest(cwd: _ws!.path),
      );
      backend.setConsentPlan(
        sid,
        const ConsentPlan(
          pathGlob: '^\\.dart_tool/harnessd/edit_pack\\.json\$',
          verbs: {'pack_write'},
          maxUses: 5,
        ),
      );
      final r = await _prompt(
        backend,
        '[scan] harness_edit {"action":"apply_executable",'
        '"executableId":"$_executableId","symbolId":"$_areaSymbolId"}',
      );
      expect(r.stop, AcpStopReason.endTurn, reason: r.updates);
      // The consented body LANDED re-indented under the verbatim
      // signature; the free oracles graded it (no revert).
      expect(
        File('${_ws!.path}/lib/geometry.dart').readAsStringSync(),
        contains(_authoredBody),
        reason: r.updates,
      );
      expect(r.updates, contains('[edit_symbol]'), reason: r.updates);
      expect(
        r.updates.contains('"reverted":true'),
        isFalse,
        reason: r.updates,
      );
      expect(r.updates, contains('"patches":1'), reason: r.updates);
      // The consent answer is AUDITED as named data.
      final audit = backend.consentAudit(r.sessionId);
      expect(
        audit.where((l) => l.contains('plan-allowed pack_write')),
        isNotEmpty,
        reason: 'audit: ${audit.join(" | ")}',
      );
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );

  test(
    'no plan → the entry SKIPS at pack load (named data), tool '
    'construction does not throw, apply bounces unknown-executable',
    () async {
      final backend = HarnessAcpBackend(
        backend: 'open_router',
        meaningProfile: true,
        scripted: true,
      );
      final r = await _prompt(
        backend,
        '[scan] harness_edit {"action":"apply_executable",'
        '"executableId":"$_executableId","symbolId":"$_areaSymbolId"}',
      );
      expect(
        r.stop,
        AcpStopReason.endTurn,
        reason: 'a refusal must end the turn as data — never crash '
            'tool construction: ${r.updates}',
      );
      expect(
        r.updates,
        contains('unknown edit executable'),
        reason: 'the unconsented entry never realized: ${r.updates}',
      );
      expect(
        File('${_ws!.path}/lib/geometry.dart').readAsStringSync(),
        isNot(contains(_authoredBody)),
        reason: 'deny-by-default: no body without consent',
      );
      // The refusal is audited too (every answer lands in the log).
      final audit = backend.consentAudit(r.sessionId);
      expect(
        audit.where((l) => l.contains('pack_write REFUSED')),
        isNotEmpty,
        reason: 'audit: ${audit.join(" | ")}',
      );
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
