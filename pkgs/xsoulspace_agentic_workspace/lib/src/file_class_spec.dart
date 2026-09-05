// ignore_for_file: lines_longer_as_80_chars

/// ADR 0024 §2 / ADR 0026 §1 — a FILE-CLASS SPEC as data: the unit of
/// extension for the workspace meaning surface.
///
/// Adding a file class = registering a spec (extensions + optional
/// mechanical extractor) in [fileClassSpecs] — never a new loop, never a
/// new tool, never a hardcoded `dartFiles` field. The fs tier builds
/// dir/file nodes for EVERY class; a spec's `parse` adds the class's
/// sub-nodes to the code tier (dart: symbols+imports); a class without a
/// parse fn is owned by the fs tier's map builder (md/yaml/json
/// section/key anchors) and its EDIT side lands as a materializer spec
/// (ADR 0024 §2) — until then edits route through the review gate.
library;

import 'dart:io';

import 'code_etl.dart' show CodeFileScan, scanDartFile;

class FileClassSpec {
  const FileClassSpec({
    required this.fileClass,
    required this.extensions,
    this.parse,
  });

  /// The registry key (fs node `class` prop; materializer-registry key).
  final String fileClass;

  /// Lowercase extensions WITH the dot.
  final Set<String> extensions;

  /// Mechanical extractor for the code tier (symbols/imports). Null → the
  /// fs tier's map builder owns this class's sub-nodes and the edit side
  /// routes through the review gate until a materializer spec lands.
  final CodeFileScan Function(File file, String rel)? parse;

  bool matches(String rel) {
    final lower = rel.toLowerCase();
    return extensions.any(lower.endsWith);
  }
}

/// The registry — DATA. Dart is realized today (symbols + imports);
/// md/yaml/json read-side anchors live in the fs tier's map builder;
/// their EDIT-side materializer specs are the P2 work (PLAN §NOW).
/// `other` is the implicit fallback (visible node, review-mode writes).
const fileClassSpecs = <FileClassSpec>[
  FileClassSpec(fileClass: 'dart', extensions: {'.dart'}, parse: scanDartFile),
  FileClassSpec(fileClass: 'md', extensions: {'.md', '.mdx'}),
  FileClassSpec(fileClass: 'yaml', extensions: {'.yaml', '.yml'}),
  FileClassSpec(fileClass: 'json', extensions: {'.json'}),
];

/// Registry lookup; unknown classes fall back to `other` (never a bounce —
/// every file is visible, only its EDIT power differs).
FileClassSpec specForRel(String rel) => fileClassSpecs
    .firstWhere((s) => s.matches(rel),
        orElse: () => const FileClassSpec(fileClass: 'other', extensions: {}));

/// The registry-derived class of [rel] (fs_etl consumes this — the class
/// mapping lives HERE, in the spec data, not in a hardcoded chain).
String fileClassOf(String relPath) => specForRel(relPath).fileClass;
