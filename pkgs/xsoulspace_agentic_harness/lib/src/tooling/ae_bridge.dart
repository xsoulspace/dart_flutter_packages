// ignore_for_file: lines_longer_than_80_chars

/// M4 bridge to agentic_executables (AE) — tier-classified verification.
///
/// AE owns spec↔code honesty; its `ae artifact verify` emits gap entries
/// whose wire shape is `VerifyEntry.toJson()` (see
/// `agentic_executables_core/lib/src/models/verify_report.dart`):
///
/// ```json
/// {"tier": 1, "tier_code": "invariant_violation", "artifact": "...",
///  "canonical": "...", "feature_id": "...", "message": "...",
///  "reason": "no_evidence_link"}
/// ```
///
/// This bridge parses that shape into [AeGap]s, renders them as compact
/// tier-ordered beats (so a tiny model learns *what kind* of fix is needed,
/// not just that something failed), and exposes a `verify_pack` tool.
///
/// Deliberately no compile-time AE dependency yet: the wire format is
/// schema-stable, and a typed port belongs inside AE first (Transformer
/// port, planned). Swap the parser for a typed import when that lands.
library;

import 'dart:convert';
import 'dart:io';

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

// ---------------------------------------------------------------------------
// Wire model (mirrors AE VerifyEntry.toJson)
// ---------------------------------------------------------------------------

enum AeTier {
  invariantViolation(1, 'invariant_violation'),
  upstreamBlocker(2, 'upstream_blocker'),
  partialFeature(3, 'partial_feature'),
  unreferencedCanonical(4, 'unreferenced_canonical');

  const AeTier(this.tier, this.code);
  final int tier;
  final String code;

  static AeTier fromCode(String code) => AeTier.values.firstWhere(
        (t) => t.code == code,
        orElse: () => AeTier.partialFeature,
      );
}

class AeGap {
  const AeGap({
    required this.tier,
    required this.artifact,
    required this.canonical,
    required this.message,
    this.featureId,
    this.reason,
    this.acceptedDrift = false,
  });

  factory AeGap.fromJson(Map<String, dynamic> json) => AeGap(
        tier: AeTier.fromCode(json['tier_code']?.toString() ?? 'partial_feature'),
        artifact: json['artifact']?.toString() ?? '',
        canonical: json['canonical']?.toString() ?? '',
        message: json['message']?.toString() ?? '',
        featureId: json['feature_id']?.toString(),
        reason: json['reason']?.toString(),
        acceptedDrift: json['accepted_drift'] == true,
      );

  final AeTier tier;
  final String artifact;
  final String canonical;
  final String message;
  final String? featureId;
  final String? reason;
  final bool acceptedDrift;

  /// Machine-actionable: agents branch on this, not on prose.
  bool get blocking =>
      !acceptedDrift &&
      (tier == AeTier.invariantViolation || tier == AeTier.upstreamBlocker);
}

List<AeGap> parseGaps(Object? payload) {
  final list = switch (payload) {
    final Map m when m['entries'] is List => m['entries'] as List,
    final List l => l,
    _ => const [],
  };
  return [
    for (final e in list)
      if (e is Map) AeGap.fromJson(e.cast<String, dynamic>()),
  ];
}

// ---------------------------------------------------------------------------
// Beat rendering — tier-ordered, one line per gap, blocking first
// ---------------------------------------------------------------------------

String renderGapBeats(List<AeGap> gaps) {
  if (gaps.isEmpty) return 'verify: clean';
  final sorted = [...gaps]
    ..sort((a, b) {
      if (a.blocking != b.blocking) return a.blocking ? -1 : 1;
      return a.tier.tier.compareTo(b.tier.tier);
    });
  final buf = StringBuffer()
    ..writeln('verify: ${gaps.where((g) => g.blocking).length} blocking / '
        '${gaps.length} total');
  for (final g in sorted) {
    final tag = g.acceptedDrift ? '${g.tier.code}(accepted)' : g.tier.code;
    buf.writeln(
      '[T${g.tier.tier} $tag] ${g.featureId ?? g.canonical}: '
      '${_clip(g.message)}${g.reason == null ? '' : ' (${g.reason})'}',
    );
  }
  return buf.toString().trimRight();
}

String _clip(String s, [int max = 140]) =>
    s.length <= max ? s : '${s.substring(0, max)}…';

bool hasBlockingGaps(List<AeGap> gaps) => gaps.any((g) => g.blocking);

// ---------------------------------------------------------------------------
// CLI executor + tool registration
// ---------------------------------------------------------------------------

class AeVerifyException implements Exception {
  AeVerifyException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Runs `ae artifact verify --pack <id>` and returns parsed gaps.
///
/// Requires the AE CLI on PATH (installed via AE's install.sh). Unit tests
/// feed [parseGaps] directly with fixture JSON instead of shelling out.
Future<List<AeGap>> verifyPackViaCli(
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
  return parseGaps(decoded);
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
      argsSchema: SchemaBundle.empty,
      execute: (args) async {
        final map = args as Map;
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
