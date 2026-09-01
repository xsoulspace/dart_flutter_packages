// ignore_for_file: lines_longer_than_80_chars

/// M4 bridge to agentic_executables (AE) — thin host shim over the typed
/// wire contract (PLAN Stage G3).
///
/// Tier semantics, the wire shape, and the gap-beat renderer now live in
/// `agentic_executables_wire` (AE-owned, pure Dart, zero deps). This module
/// keeps only what a *host* owns: CLI execution of `ae artifact verify` and
/// the model-facing `verify_pack` tool. Swap or mock the CLI freely — the
/// wire contract is schema-stable.
library;

import 'dart:convert';
import 'dart:io';

import 'package:agentic_executables_wire/agentic_executables_wire.dart'
    show VerifyEntryWire, hasBlockingGaps, parseVerifyEntries, renderGapBeats;
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

// Re-export the wire vocabulary so hosts touch ONE import surface.
export 'package:agentic_executables_wire/agentic_executables_wire.dart'
    show AeTier, VerifyEntryWire, hasBlockingGaps, parseVerifyEntries,
    renderGapBeats;

class AeVerifyException implements Exception {
  AeVerifyException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Runs `ae artifact verify --pack <id>` and returns parsed gaps.
///
/// Requires the AE CLI on PATH (installed via AE's install.sh). Unit tests
/// feed [parseVerifyEntries] directly with fixture JSON instead of shelling
/// out.
Future<List<VerifyEntryWire>> verifyPackViaCli(
  String packId, {
  String? projectRoot,
}) async {
  final result = await Process.run(
    'ae',
    ['artifact', 'verify', '--pack', packId, '--json'],
    workingDirectory: projectRoot ?? Directory.current.path,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (result.exitCode != 0) {
    throw AeVerifyException(
      'ae verify failed (${result.exitCode}): '
      '${result.stderr.toString().trim()}',
    );
  }
  final decoded = jsonDecode(result.stdout as String);
  return parseVerifyEntries(decoded);
}

/// Registers a `verify_pack` tool: deterministic, read-only, structured.
///
/// The tool result is the tier-ordered beat text plus a machine flag, so
/// downstream decisions can branch on `blocking` instead of parsing prose.
ToolDef verifyPackTool({String? projectRoot}) => ToolDef.encode(
      name: const ToolName('verify_pack'),
      description:
          'Verify an AE canonical pack against its realizations. Returns '
          'tier-classified gaps (T1 invariant violation > T2 upstream '
          'blocker > T3 partial). Read-only.',
      execute: (args) async {
        final map = args! as Map;
        final packArg = map['pack'];
        if (packArg is! String || packArg.isEmpty) {
          throw ArgumentError('args must carry non-empty string "pack"');
        }
        final packId = packArg;
        try {
          final gaps = await verifyPackViaCli(packId, projectRoot: projectRoot);
          return {
            'blocking': hasBlockingGaps(gaps),
            'total': gaps.length,
            'report': renderGapBeats(gaps),
          };
        } on AeVerifyException catch (e) {
          return {'blocking': true, 'error': e.message};
        }
      },
    );
