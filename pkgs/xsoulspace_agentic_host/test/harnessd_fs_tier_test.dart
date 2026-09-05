// ignore_for_file: lines_longer_than_80_chars

/// FS-TIER e2e GATE (PLAN §NOW #3, ADR 0024) — the daemon's meaning profile
/// covers EVERY file class through ONE map-graph:
///
///   map-read (repo_etl scan) → zoom (meaning_zoom over fs nodes, incl.
///   zoom=file) → CONSENTED review write (write_review →
///   session/request_permission → allow → lands)
///   and REJECT → the write NEVER lands (deny-by-default is structural).
///
/// LLM-free: the scripted daemon mover carries the structured payloads
/// (`harness_zoom {…}`, `harness_fs_write {path, content}`) verbatim to the
/// registry. The consent round-trip is the REAL ACP path
/// (attachPermissionRequester → writeApprover → WriteGateMode.review).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_agentic_workspace/xsoulspace_agentic_workspace.dart'
    show editSymbolTool, repoEtlTool;
import 'package:xsoulspace_agentic_host/xsoulspace_agentic_host.dart';

import 'package:dart_acp_toolkit/dart_acp_toolkit.dart';

/// A green-convention fixture (D8: pubspec + tests → `dart test`) with
/// non-code files the fs tier must cover.
Future<Directory> _fixture() async {
  final dir = await Directory.systemTemp.createTemp('r7_fs_tier_');
  File('${dir.path}/pubspec.yaml')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
      'name: fs_tier_e2e\nenvironment:\n  sdk: ^3.0.0\ndev_dependencies:\n  test: any\n',
    );
  File('${dir.path}/lib/greet.dart')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync("String greet(String name) => 'hello ' + name;\n");
  File('${dir.path}/test/greet_test.dart')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(
      "import 'package:test/test.dart';\n"
      "import 'package:fs_tier_e2e/greet.dart';\n"
      "void main() { test('greet', () { expect(greet('x'), 'hello x'); }); }\n",
    );
  File('${dir.path}/notes.md').writeAsStringSync('# Notes\n\nscratch\n');
  await Process.run('dart', ['pub', 'get'], workingDirectory: dir.path);
  return dir;
}

void main() {
  late Directory ws;

  setUp(() async {
    ws = await _fixture();
  });
  tearDown(() {
    try {
      ws.deleteSync(recursive: true);
    } on Object {
      // best effort
    }
  });

  test('fs-tier e2e: map-read → zoom → consented review write LANDS',
      () async {
    final backend = HarnessAcpBackend(
      backend: 'open_router',
      meaningProfile: true,
      scripted: true,
    );
    final permissionCalls = <AcpPermissionRequest>[];
    backend.attachPermissionRequester((request) async {
      permissionCalls.add(request);
      // Consent surfaces as a REAL session/request_permission round-trip;
      // this client allows ONCE (the human said yes).
      return AcpPermissionOutcome.allow;
    });
    final sid = await backend.createSession(AcpSessionNewRequest(cwd: ws.path));
    final updates = StringBuffer();
    final stop = await backend.prompt(
      AcpPromptRequest(
        sessionId: sid,
        prompt: [
          AcpTextBlock(
            '[scan] '
            'harness_zoom {"query": "notes", "zoom": "local", "budget": 512} '
            'harness_fs_write {"path": "notes.md", "content": "# Notes\\n\\n'
            'fs-tier write landed through the review gate\\n"}',
          ),
        ],
      ),
      emit: (u) {
        if (u is AgentMessageChunk) updates.write(u.content is AcpTextBlock ? (u.content as AcpTextBlock).text : '');
      },
      isCancelled: () => false,
    );
    expect(stop, AcpStopReason.endTurn);

    // Map-read happened: the fs node exists (the zoom found it).
    expect(updates.toString(), contains('f_notes.md'));
    // The write went through the CONSENT round-trip (deny-by-default held
    // until the client allowed).
    expect(permissionCalls, hasLength(1));
    expect(permissionCalls.single.title, contains('notes.md'));
    // The consented write LANDED.
    expect(
      File('${ws.path}/notes.md').readAsStringSync(),
      contains('fs-tier write landed through the review gate'),
    );
    // The tool result streamed the review ack.
    expect(updates.toString(), contains('[write_review]'));
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('fs-tier e2e: a REJECTED review write NEVER lands', () async {
    final backend = HarnessAcpBackend(
      backend: 'open_router',
      meaningProfile: true,
      scripted: true,
    );
    backend.attachPermissionRequester((request) async {
      // The human said NO.
      return AcpPermissionOutcome.reject;
    });
    final sid = await backend.createSession(AcpSessionNewRequest(cwd: ws.path));
    final before = File('${ws.path}/notes.md').readAsStringSync();
    await backend.prompt(
      AcpPromptRequest(
        sessionId: sid,
        prompt: [
          AcpTextBlock(
            '[scan] '
            'harness_fs_write {"path": "notes.md", "content": "# OVERWRITTEN"}',
          ),
        ],
      ),
      emit: (u) {},
      isCancelled: () => false,
    );
    // The mutation NEVER landed — the file is untouched.
    expect(File('${ws.path}/notes.md').readAsStringSync(), before);
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('fs-tier surface law: the meaning profile never carries generic fs '
      'tools; write_review rides the review gateway only', () async {
    // The EXACT meaning-profile registry runCodingAgentOnce wires —
    // WITHOUT an approver (the daemon attaches none in this variant): no
    // read/write/glob/grep, no write_review (no approver → no verb).
    final world = World()..addPlugin(AgentPlugin());
    world.upsertResource(ToolRegistryResource());
    final jail = Directory.systemTemp.createTempSync('fs_surface_');
    addTearDown(() => jail.deleteSync(recursive: true));
    final registry = ToolRegistry();
    registry.register(repoEtlTool(world, jail));
    registry.register(meaningZoomTool(world));
    registry.register(meaningImpactTool(world));
    registry.register(editSymbolTool(world, jail));
    final names = registry.tools.keys.map((t) => t.value).toSet();
    for (final banned in ['read', 'write', 'glob', 'grep', 'write_review']) {
      expect(names.contains(banned), isFalse,
          reason: 'generic fs tools never return to the meaning profile '
              '(ADR 0023/0024) — and the escape hatch needs an approver');
    }
    // The zoom vocabulary stays CLOSED (ADR 0018) — span cuts ride point
    // zoom; the schema must not have grown a raw-text level.
    final zoomSchema =
        registry.get(const ToolName('meaning_zoom'))!.argsSchema.toJson();
    expect(jsonEncode(zoomSchema), contains('"point","local","region","summary"'));
  });
}
