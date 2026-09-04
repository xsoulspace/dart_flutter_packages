// ignore_for_file: lines_longer_as_80_chars

/// R7 production #3 — the ADR 0021 capture loop, wired to the EDIT tier
/// (ADR 0023 §3: "the capture loop records novel resolutions back into
/// the pack — self-improvement for code edits").
///
/// The economics (measured, results_r7.md): AFM authored 0/3 free-form
/// op-chains; the pack-fed path costs ZERO authored tokens (R7d). So the
/// model should rarely compose: when a MODEL-COMPOSED `replace_member_body`
/// passes all three fences AND the free oracles (analyze + workspace
/// convention, fully green — a move merely KEPT under a pre-existing red
/// baseline is not a proven resolution), the HOST captures it as a pack
/// entry: an [EditExecutableWire] (kind `replace_member_body`) plus the
/// op-chain as data, persisted in the project pack under
/// `<workspace>/.dart_tool/harnessd/edit_pack.json`.
///
/// The executable id is a MECHANICAL fingerprint of the repair class
/// (action + normalized op rows) — never model-authored, never prose. A
/// later task targeting a symbol with the SAME repair class consumes the
/// entry via `apply_executable {executableId, symbolId}` at zero authored
/// tokens; the integration fence still validates the chain against the
/// new symbol's declared signature (a wrong class bounces as data).
///
/// The model never sees the pack file; the pack is host data (the same
/// discipline as every snapshot/store in the harness).
library;

import 'dart:convert';
import 'dart:io';

import 'package:agentic_executables_wire/agentic_executables_wire.dart'
    show EditExecutableKind, EditExecutableWire, EditVerification;

/// One captured entry: the wire (the model-facing handle) + the op-chain
/// (the data that makes it zero-authored-tokens on reuse).
class CapturedEditExecutable {
  CapturedEditExecutable({required this.wire, required this.opChain});

  final EditExecutableWire wire;
  final List<Map<String, String?>> opChain;

  Map<String, Object?> toJson() => {
    ...wire.toJson(),
    'opChain': [
      for (final row in opChain)
        {
          'label': row['label'],
          if (row['a'] != null) 'a': row['a'],
          if (row['b'] != null) 'b': row['b'],
        },
    ],
  };

  static CapturedEditExecutable fromJson(Map<String, Object?> json) =>
      CapturedEditExecutable(
        wire: EditExecutableWire.fromJson(json),
        opChain: [
          if (json['opChain'] is List)
            for (final row in json['opChain'] as List)
              if (row is Map)
                {
                  'label': row['label'] as String?,
                  'a': row['a'] as String?,
                  'b': row['b'] as String?,
                },
        ],
      );
}

CapturedEditExecutable? _entryOrNull(Map<String, Object?> json) {
  try {
    return CapturedEditExecutable.fromJson(json);
  } on Object {
    return null;
  }
}

/// The project pack of captured edit resolutions (one per workspace).
class EditPackCapture {
  EditPackCapture(this.workspace);

  final Directory workspace;

  /// The pack persists in the daemon's per-workspace state (never in the
  /// model surface, never shipped as code).
  File get file => File('${workspace.path}/.dart_tool/harnessd/edit_pack.json');

  /// Loads every captured entry; missing or corrupt pack → empty (honest,
  /// never guessed — a corrupt entry is SKIPPED, not repaired into a guess).
  List<CapturedEditExecutable> load() {
    if (!file.existsSync()) return const [];
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) return const [];
      return [
        if (decoded['executables'] is List)
          for (final e in decoded['executables'] as List)
            if (e is Map)
              // Corrupt entry: skip as classified data (never realize a
              // shape the wire contract cannot validate).
              ?_entryOrNull(e.cast<String, Object?>()),
      ];
    } on Object {
      return const [];
    }
  }

  /// Captures a VERIFIED-GREEN novel resolution. Idempotent: an entry with
  /// the same fingerprint is not duplicated. Returns the executable id.
  String? captureVerified({
    required String action,
    required List<Map<String, String?>> opChain,
    required String description,
  }) {
    // v1 captures the one model-composed, reuse-bearing class: body
    // replacements over the closed vocabulary (renames are built-in,
    // inserts are one-off scaffolding).
    if (action != 'replace_member_body') return null;
    final chain = [
      for (final row in opChain)
        {'label': row['label'], 'a': row['a'], 'b': row['b']},
    ];
    if (chain.isEmpty) return null;
    final id = 'dart/captured/${fingerprint(action, chain)}';
    final entries = List<CapturedEditExecutable>.of(load());
    if (entries.any((e) => e.wire.id == id)) return id;
    final wire = EditExecutableWire(
      id: id,
      kind: EditExecutableKind.replaceMemberBody,
      params: const ['symbolId'],
      verification: const [EditVerification.analyze, EditVerification.test],
      scope: 'lexical',
      description: 'captured novel resolution: $description',
    );
    entries.add(CapturedEditExecutable(wire: wire, opChain: chain));
    file
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'packId': 'edit_capture',
          'executables': [for (final e in entries) e.toJson()],
        }),
        flush: true,
      );
    return id;
  }

  /// The mechanical repair-class fingerprint: action + normalized op rows
  /// (stable FNV-1a over the canonical JSON — data, never prose).
  static String fingerprint(String action, List<Map<String, String?>> chain) {
    final canonical = jsonEncode({
      'action': action,
      'chain': [
        for (final row in chain)
          {'label': row['label'], 'a': row['a'], 'b': row['b']},
      ],
    });
    var hash = 0xcbf29ce484222325;
    for (final code in canonical.codeUnits) {
      hash ^= code;
      hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return hash.toRadixString(16).padLeft(16, '0').substring(0, 12);
  }
}
