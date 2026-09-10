// ignore_for_file: lines_longer_than_80_chars

/// Server-side tier enforcement (follow-up 1) — the DAEMON honors the tier
/// a client declares at `session/new` (`_meta.sessionTier`), so
/// non-extension clients get tier-sourced read-program defaults (the pi
/// extension already sources the same numbers client-side; the toolkit
/// carries `_meta` through `AcpSessionNewRequest`).
///
/// Gate rows:
/// 1. a valid declared tier → the read world's `meaning_program` op
///    defaults are TIER-SOURCED, asserted through a probe READ op WITHOUT
///    an explicit budget: a ~650-token read result is served WHOLE under
///    the hosted tier (per-op budget 4,096) and CLIPPED under the 512
///    default;
/// 2. absent `_meta` → bit-identical current behavior (the same probe
///    clips at the hardcoded 512 default);
/// 3. malformed `_meta.sessionTier` → NAMED bounce (createSession throws
///    naming `_meta.sessionTier.<field>`), defaults unchanged;
/// 4. the extension's exact SESSION_TIER JSON shape parses (the TS ladder
///    mirror: AFM window 4,096 → 512/1,200; hosted 131,072 → 4,096/8,192).
///
/// LLM-free: scripted daemon, mechanical read path, zero model.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dart_acp_toolkit/dart_acp_toolkit.dart';
import 'package:test/test.dart';
import 'package:xsoulspace_agentic_host/src/session_tier.dart'
    show parseSessionTierMeta;
import 'package:xsoulspace_agentic_host/xsoulspace_agentic_host.dart';

/// The probe body: ~2,600 chars (~650 tokens) — over the AFM per-op
/// default (512) but far under the hosted tier's 4,096, so the SAME
/// budget-less read op clips on the default tier and serves whole on the
/// hosted one. The differential IS the assertion.
const probeBody = 'x';

Future<Directory> _fixture() async {
  final dir = await Directory.systemTemp.createTemp('tier_server_');
  final body = probeBody * 2600;
  File('${dir.path}/probe.md')
      .writeAsStringSync('# Tier Probe Section\n\n$body\n');
  return dir;
}

Future<String> _probeRead(
  HarnessAcpBackend backend,
  String sid,
) async {
  final chunks = StringBuffer();
  final stop = await backend.prompt(
    AcpPromptRequest(
      sessionId: sid,
      prompt: [
        const AcpTextBlock(
          '[scan] harness_meaning_program '
          '{"ops":[{"op":"locate","query":"Tier Probe"},{"op":"read"}]}',
        ),
      ],
    ),
    emit: (u) {
      if (u is AgentMessageChunk) {
        chunks.write(
          u.content is AcpTextBlock
              ? (u.content as AcpTextBlock).text
              : '',
        );
      }
    },
    isCancelled: () => false,
  );
  expect(stop, AcpStopReason.endTurn);
  return chunks.toString();
}

/// Extracts the `meaning_program` verdict JSON from the streamed chunks
/// (the read path emits `\n[meaning_program] {json}\n`).
Map<String, dynamic> _verdict(String chunks) {
  final match = RegExp(r'\[meaning_program\] (.*)\n').firstMatch(chunks);
  expect(match, isNotNull, reason: 'chunks: ${chunks.length} chars');
  final raw = match!.group(1)!;
  expect(raw.endsWith('…'), isFalse,
      reason: 'the probe verdict must not hit the 4,000-char chunk cap: '
          '${raw.length} chars');
  final decoded = jsonDecode(raw);
  expect(decoded, isA<Map<String, dynamic>>(),
      reason: 'the meaning_program chunk must be the verdict JSON object');
  return (decoded as Map).cast<String, dynamic>();
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

  test('a valid declared tier: the read world op defaults are '
      'TIER-SOURCED — a budget-less read serves the whole span',
      () async {
    final backend = HarnessAcpBackend(
      meaningProfile: true,
      scripted: true,
    );
    // The extension's exact wire shape (r7_harnessd_extension.ts
    // `SESSION_TIER`, the hosted big-window row).
    final sid = await backend.createSession(
      AcpSessionNewRequest(
        cwd: ws.path,
        meta: {
          'sessionTier': {
            'backend': 'open_router',
            'windowTokens': 131072,
            'outputReserveTokens': 1024,
            'perOpReadBudget': 4096,
            'verdictBudget': 8192,
          },
        },
      ),
    );
    final chunks = await _probeRead(backend, sid);
    final verdict = _verdict(chunks);
    expect(verdict['ok'], true, reason: 'chunks: $chunks');
    expect(verdict['truncated'], isNull,
        reason: 'the hosted verdict budget (8,192) must not truncate');
    final results = verdict['results'] as List;
    final readResult = (results[1] as Map)['read'] as Map?;
    expect(readResult, isNotNull,
        reason: 'the budget-less read must SERVE (not clip) under the '
            'hosted per-op budget: $chunks');
    expect(readResult!['ok'], true);
  });

  test('absent _meta: bit-identical current behavior — the same '
      'budget-less read CLIPS at the hardcoded 512 default', () async {
    final backend = HarnessAcpBackend(
      meaningProfile: true,
      scripted: true,
    );
    final sid = await backend.createSession(
      AcpSessionNewRequest(cwd: ws.path),
    );
    final chunks = await _probeRead(backend, sid);
    final verdict = _verdict(chunks);
    expect(verdict['ok'], true, reason: 'chunks: $chunks');
    final results = verdict['results'] as List;
    expect(results, hasLength(2));
    final clipMarker = results[1] as Map;
    expect(clipMarker['read'], isNull,
        reason: 'the fat body never enters context (512 default)');
    expect(clipMarker['clipped'], true);
    expect('${clipMarker['hint']}', contains('exceeded the per-op budget'));
  });

  test('malformed _meta.sessionTier: NAMED bounce, defaults unchanged',
      () async {
    final backend = HarnessAcpBackend(
      meaningProfile: true,
      scripted: true,
    );
    // A non-object tier…
    expect(
      () => backend.createSession(
        AcpSessionNewRequest(
          cwd: ws.path,
          meta: {'sessionTier': 'afm'},
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('_meta.sessionTier'),
        ),
      ),
    );
    // …and a malformed field: the error NAMES the field, and the session
    // is NOT created (the client sees the bounce, not silent defaults).
    final ws2 = await Directory.systemTemp.createTemp('tier_server_');
    addTearDown(() {
      try {
        ws2.deleteSync(recursive: true);
      } on Object {
        // best effort
      }
    });
    expect(
      () => backend.createSession(
        AcpSessionNewRequest(
          cwd: ws2.path,
          meta: {
            'sessionTier': {
              'windowTokens': 'abc',
              'perOpReadBudget': 512,
              'verdictBudget': 1200,
            },
          },
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('_meta.sessionTier.windowTokens'),
        ),
      ),
    );
    // The defaults stay unchanged: a plain session on the SAME workspace
    // still clips at 512 (the bounce created no session, mutated nothing).
    final sid = await backend.createSession(
      AcpSessionNewRequest(cwd: ws.path),
    );
    final chunks = await _probeRead(backend, sid);
    final verdict = _verdict(chunks);
    expect(verdict['ok'], true);
    final clipMarker = (verdict['results'] as List)[1] as Map;
    expect(clipMarker['clipped'], true);
  });

  test('the extension ladder shape parses: AFM 4096 → 512/1200; hosted '
      '131072 → 4096/8192', () {
    final afm = parseSessionTierMeta({
      'sessionTier': {
        'backend': 'apple_foundation_afm',
        'windowTokens': 4096,
        'outputReserveTokens': 1024,
        'perOpReadBudget': 512,
        'verdictBudget': 1200,
      },
    });
    expect(afm!.backend, 'apple_foundation_afm');
    expect(afm.windowTokens, 4096);
    expect(afm.outputReserveTokens, 1024);
    // The ADR 0033 cut terms the wire omits default to the MEASURED
    // constants — the extension resolved its tier through the same
    // equation; the daemon never re-derives a declared tier.
    expect(afm.nativeTruthFactor, 1.45);
    expect(afm.marginFraction, closeTo(0.10, 1e-9));
    expect(afm.minCutTokens, 600);
    expect(afm.perOpReadBudget, 512);
    expect(afm.verdictBudget, 1200);

    final hosted = parseSessionTierMeta({
      'sessionTier': {
        'backend': 'open_router',
        'windowTokens': 131072,
        'outputReserveTokens': 1024,
        'perOpReadBudget': 4096,
        'verdictBudget': 8192,
      },
    });
    expect(hosted!.windowTokens, 131072);
    expect(hosted.perOpReadBudget, 4096);
    expect(hosted.verdictBudget, 8192);
  });

  test('absent / incomplete _meta → null (current defaults); non-object '
      'sessionTier → named error', () {
    expect(parseSessionTierMeta(null), isNull);
    expect(parseSessionTierMeta({'other': 1}), isNull);
    expect(parseSessionTierMeta(const {}), isNull);
    expect(
      () => parseSessionTierMeta({'sessionTier': 4096}),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('_meta.sessionTier must be a JSON object'),
        ),
      ),
    );
  });
}
