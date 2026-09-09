// ignore_for_file: lines_longer_than_80_chars

/// ADR 0027 amendment — MECHANICAL EDITS gate: a directive-only
/// `harness_edit {…}` prompt in REMOTE-MOVER mode (the production pi path)
/// executes through the edit materializer — consent round-trip, the SAME
/// `edit_symbol` path a mover-approved edit uses, touched-file beat on the
/// goal actor's thread — with ZERO mover involvement.
///
/// Measured failure this locks out (surface_gaps.md, 2026-09-06): three
/// `harness_edit {insert_member …}` delegations through the remote-mover
/// daemon each ended `mover_refusal: empty move` (walls 103 / 117 / 183 s)
/// burning a root-convention fallback verify — the touched-file beat never
/// landed and the per-package verify derivation could not be exercised
/// end-to-end. The payload is DATA; the human is the approver; the mover
/// has nothing to decide.
library;

import 'dart:io';

import 'package:dart_acp_toolkit/dart_acp_toolkit.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_agentic_harness/src/tooling/verify_tiers.dart'
    show dartVerifyConvention, sessionTouchedFiles;
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_agentic_host/xsoulspace_agentic_host.dart';
import 'package:xsoulspace_agentic_workspace/xsoulspace_agentic_workspace.dart';

/// A fixture workspace whose COVERED member `area` is the edit target:
/// the suite pins area(2, 3) == 6, so a behavior-preserving body
/// replacement passes every fence AND the convention, while the comment
/// inside the body span proves the bytes changed.
Future<Directory> _coveredWorkspace(String prefix) async {
  final dir = await Directory.systemTemp.createTemp(prefix);
  File('${dir.path}/pubspec.yaml')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
      'name: mech_edit\nenvironment:\n  sdk: ^3.0.0\ndev_dependencies:\n  test: any\n',
    );
  File('${dir.path}/lib/geometry.dart')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
      'int area(int w, int h) {\n  return w * h; // PUNNY_COMMENT\n}\n',
    );
  File('${dir.path}/test/geometry_test.dart')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
      "import 'package:test/test.dart';\n"
      "import 'package:mech_edit/geometry.dart';\n"
      'void main() {\n'
      "  test('area', () {\n    expect(area(2, 3), 6);\n  });\n"
      '}\n',
    );
  await Process.run('dart', ['pub', 'get'], workingDirectory: dir.path);
  return dir;
}

/// Variant fixture: a FAILING convention (the suite demands `surfaceArea`,
/// which does not exist) — the graded mover-refusal fallback fixture. The
/// mechanical edit lands despite the red baseline; the edit itself is
/// behavior-preserving on the covered `area` member.
Future<Directory> _refusalWorkspace() async {
  final dir = await _coveredWorkspace('mech_edit_refusal_');
  File('${dir.path}/test/geometry_test.dart').writeAsStringSync(
    "import 'package:test/test.dart';\n"
    "import 'package:mech_edit/geometry.dart';\n"
    'void main() {\n'
    "  test('area', () {\n    expect(area(2, 3), 6);\n  });\n"
    "  test('surfaceArea', () {\n    expect(surfaceArea(2, 3, 4), 24);\n  });\n"
    '}\n',
  );
  return dir;
}

/// The behavior-preserving chain for `area`: load_arg w, load_arg h,
/// mul, return — the host compiles it to `return (w * h);`.
const _areaChain =
    '[{"label": "load_arg", "a": "w"}, '
    '{"label": "load_arg", "a": "h"}, '
    '{"label": "mul"}, '
    '{"label": "return"}]';

/// Resolves the `area` symbol id from the tree — the caller must NEVER
/// guess ids; the test derives it exactly like a delegator (scan, then
/// take the row).
Future<String> areaSymbolId(Directory ws) async {
  final world = World()..addPlugin(AgentPlugin());
  world.upsertResource(ToolRegistryResource());
  await repoEtlTool(world, ws).execute({'action': 'scan'});
  final index = world.getResource<MeaningIndex>();
  return index.byId.keys.where((id) => id.endsWith('_area')).first;
}

void main() {
  late Directory ws;

  setUp(() async {
    ws = await _coveredWorkspace('mech_edit_');
  });
  tearDown(() {
    try {
      ws.deleteSync(recursive: true);
    } on Object {
      // best effort
    }
  });

  Future<BackendPromptOutcome> delegate(
    HarnessAcpBackend backend,
    String text,
  ) async {
    final sid = await backend.createSession(
      AcpSessionNewRequest(cwd: ws.path),
    );
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

  test('classifier: pure edit payload → mechanical; mixed → never', () {
    expect(
      isMechanicalEditDirective(
        'harness_edit {"action": "replace_member_body", "symbolId": "sym_a", '
        '"opChain": [{"label": "return"}]}',
      ),
      isTrue,
    );
    expect(
      isMechanicalEditDirective(
        'harness_edit {"action": "replace_member_body", "symbolId": "sym_a", '
        '"opChain": [{"label": "return"}]} and then verify the package',
      ),
      isFalse,
      reason: 'leftover prose = a task — deny-by-default on ambiguity',
    );
    expect(
      isMechanicalEditDirective(
        'harness_edit {"action": "replace_member_body", "symbolId": "sym_a", '
        '"opChain": [{"label": "return"}]} harness_run {"command": ["ls"]}',
      ),
      isFalse,
      reason: 'any other directive form = a task',
    );
    expect(isMechanicalEditDirective('[scan]'), isFalse);
    // Pure-but-invalid payloads STILL take the mechanical path (the bounce
    // IS the answer — the mover is never reached for structurally invalid
    // directives).
    expect(
      isMechanicalEditDirective(
        'harness_edit {"action": "remove_member", "symbolId": "sym_a"}',
      ),
      isTrue,
    );
  });

  test('payload validation: the dart edit action union + symbolId', () {
    const chain = [
      {'label': 'return'},
    ];
    // The union (ADR 0034 dart actions) and its action-scoped slots.
    expect(
      validateMechanicalEditPayload({
        'action': 'replace_member_body',
        'symbolId': 'sym_a',
        'opChain': chain,
      }),
      isNotNull,
    );
    expect(
      validateMechanicalEditPayload({
        'action': 'insert_member',
        'symbolId': 'sym_hostclass',
        'name': 'doubled',
        'opChain': chain,
      }),
      isNotNull,
    );
    expect(
      validateMechanicalEditPayload({
        'action': 'apply_executable',
        'symbolId': 'sym_a',
        'executableId': 'exe_1',
      }),
      isNotNull,
    );
    // Out-of-union actions, missing symbolId, missing slots → null.
    expect(
      validateMechanicalEditPayload({
        'action': 'replace_section',
        'symbolId': 'sec_a',
        'body': 'x',
      }),
      isNull,
      reason: 'doc-tier actions never take the dart mechanical path',
    );
    expect(
      validateMechanicalEditPayload({'action': 'replace_member_body'}),
      isNull,
      reason: 'symbolId is required',
    );
    expect(
      validateMechanicalEditPayload({
        'action': 'replace_member_body',
        'symbolId': 'sym_a',
      }),
      isNull,
      reason: 'a body replacement without a chain is structurally incomplete',
    );
    expect(
      validateMechanicalEditPayload({
        'action': 'apply_executable',
        'symbolId': 'sym_a',
      }),
      isNull,
      reason: 'apply_executable needs executableId',
    );
    expect(
      validateMechanicalEditPayload({
        'action': 'insert_member',
        'symbolId': 'sym_hostclass',
        'opChain': chain,
      }),
      isNull,
      reason: 'insert_member needs a name',
    );
  });

  test(
    'remote mover + ALLOW: the edit lands through the materializer, the '
    'touched-file beat reaches the goal thread, the tree refreshes',
    () async {
      final backend = HarnessAcpBackend(
        meaningProfile: true,
        remoteMover: true,
      );
      // The mover is NEVER involved: any propose_move fails the gate.
      backend.attachMoveProposer(
        (proposal) async => fail('mover reached: ${proposal.prompt}'),
      );
      backend.attachPermissionRequester((request) async {
        expect(request.kind, 'edit');
        return AcpPermissionOutcome.allow;
      });
      final id = await areaSymbolId(ws);
      final r = await delegate(
        backend,
        'harness_edit {"action": "replace_member_body", '
        '"symbolId": "$id", "opChain": $_areaChain}',
      );
      expect(r.stop, AcpStopReason.endTurn, reason: r.updates);
      // The edit landed: the body span was rewritten (the comment inside
      // it is gone) and the behavior is unchanged.
      final lib = File('${ws.path}/lib/geometry.dart').readAsStringSync();
      expect(lib, isNot(contains('PUNNY_COMMENT')), reason: r.updates);
      expect(lib, contains('return (w * h);'), reason: lib);
      expect(r.updates, contains('[mechanical edit path] 1 applied'));
      expect(r.updates, contains('[repo_etl refresh]'));
      // THE TOUCHED-FILE BEAT: it lands on the GOAL actor's thread with
      // the same shape a mover-approved edit leaves — the verify-tier
      // derivation reads the touched set without a mover round-trip.
      final world = backend.sessionsDebugWorld(r.sessionId);
      expect(world, isNotNull);
      final touched = sessionTouchedFiles(world!, dartVerifyConvention);
      expect(touched, contains('lib/geometry.dart'), reason: '$touched');
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );

  test('malformed payload → named bounce, the mover is NEVER reached',
      () async {
    final backend = HarnessAcpBackend(
      meaningProfile: true,
      remoteMover: true,
    );
    backend.attachMoveProposer(
      (proposal) async => fail('mover reached: ${proposal.prompt}'),
    );
    backend.attachPermissionRequester(
      (request) async => AcpPermissionOutcome.allow,
    );
    final r = await delegate(
      backend,
      'harness_edit {"action": "remove_member", "symbolId": "sym_a"}',
    );
    expect(r.stop, AcpStopReason.endTurn, reason: 'the bounce IS the answer');
    expect(r.updates, contains('invalid payload(s) bounced'), reason: r.updates);
    expect(r.updates, contains('[mechanical edit path] 0 applied'));
    // Bytes untouched.
    expect(
      File('${ws.path}/lib/geometry.dart').readAsStringSync(),
      contains('PUNNY_COMMENT'),
    );
  });

  test('remote mover + REJECT: the edit NEVER lands', () async {
    final backend = HarnessAcpBackend(
      meaningProfile: true,
      remoteMover: true,
    );
    backend.attachMoveProposer(
      (proposal) async => fail('mover reached: ${proposal.prompt}'),
    );
    backend.attachPermissionRequester(
      (request) async => AcpPermissionOutcome.reject,
    );
    final id = await areaSymbolId(ws);
    final r = await delegate(
      backend,
      'harness_edit {"action": "replace_member_body", '
      '"symbolId": "$id", "opChain": $_areaChain}',
    );
    expect(r.stop, AcpStopReason.endTurn, reason: r.updates);
    expect(r.updates, contains('[mechanical edit path] 0 applied'));
    expect(
      File('${ws.path}/lib/geometry.dart').readAsStringSync(),
      contains('PUNNY_COMMENT'),
      reason: 'a reject NEVER lands',
    );
    // No beat: nothing was applied.
    final world = backend.sessionsDebugWorld(r.sessionId);
    if (world != null) {
      expect(
        sessionTouchedFiles(world, dartVerifyConvention),
        isEmpty,
        reason: 'no consent, no touched-file beat',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 6)));

  test(
    'mixed prose + directive → the graded path (mover decides); a graded '
    'edit task ending mover_refusal falls back to the single payload',
    () async {
      final backend = HarnessAcpBackend(
        meaningProfile: true,
        remoteMover: true,
      );
      backend.attachMoveProposer(
        // The mover refuses EVERY decision (the measured empty-move wall).
        (proposal) async => const AcpMoveResponse(),
      );
      backend.attachPermissionRequester(
        (request) async => AcpPermissionOutcome.allow,
      );
      final ws2 = await _refusalWorkspace();
      addTearDown(() => ws2.deleteSync(recursive: true));
      // The id comes from the FALLBACK workspace's own tree — never a
      // cross-workspace guess.
      final id = await areaSymbolId(ws2);
      final sid = await backend.createSession(
        AcpSessionNewRequest(cwd: ws2.path),
      );
      final updates = StringBuffer();
      final stop = await backend.prompt(
        AcpPromptRequest(
          sessionId: sid,
          prompt: [
            AcpTextBlock(
              'Fix the suite in this package. '
              'harness_edit {"action": "replace_member_body", '
              '"symbolId": "$id", "opChain": $_areaChain}',
            ),
          ],
        ),
        isCancelled: () => false,
        emit: (u) {
          if (u is! AgentMessageChunk) return;
          updates.write(
            u.content is AcpTextBlock ? (u.content as AcpTextBlock).text : '',
          );
        },
      );
      expect(stop, AcpStopReason.endTurn, reason: updates.toString());
      final u = updates.toString();
      // The mixed prompt went to the GRADED path (mover decided, refused),
      // and the fallback executed the single payload mechanically.
      expect(u, contains('mover_refusal'), reason: u);
      expect(
        u,
        contains('mover_refusal with a single well-formed harness_edit'),
        reason: u,
      );
      expect(u, contains('[mechanical edit path] 1 applied'), reason: u);
      // The edit landed despite the red baseline.
      final lib = File('${ws2.path}/lib/geometry.dart').readAsStringSync();
      expect(lib, isNot(contains('PUNNY_COMMENT')), reason: lib);
      // And the touched-file beat reached the goal actor's thread.
      final touched = sessionTouchedFiles(
        backend.sessionsDebugWorld(sid)!,
        dartVerifyConvention,
      );
      expect(touched, contains('lib/geometry.dart'), reason: '$touched');
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

typedef BackendPromptOutcome = ({AcpStopReason stop, String updates, String sessionId});
