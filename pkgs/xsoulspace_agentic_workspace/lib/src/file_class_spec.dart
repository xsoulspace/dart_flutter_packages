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

/// ADR 0024 §2 — a materializer spec as DATA: the edit-side registration
/// of one file class. A class WITH a registered spec has (a) a map format
/// (the fs tier builds its typed sub-nodes in the same mechanical pass)
/// and (b) ONE uniform edit verb with a named oracle. A class WITHOUT one
/// routes edits through the review gate (`write_review`) — never raw.
/// Registering a spec is DATA + the materializer file, never a new loop
/// (ADR 0026 §1). md is the first non-dart class registered (PLAN item 4);
/// yaml/json land next (item 5).
class MaterializerSpec {
  const MaterializerSpec({
    required this.fileClass,
    required this.spanCurrency,
    required this.mapFormat,
    required this.emitter,
    required this.oracle,
    required this.anchors,
    required this.actions,
  });

  /// The registry key (must equal a [FileClassSpec.fileClass]).
  final String fileClass;

  /// The span currency the emitter splices (md: `section`).
  final String spanCurrency;

  /// The tree sub-structure the map half builds (`heading_tree`).
  final String mapFormat;

  /// The host-spliced emitter realization (`section_splice`).
  final String emitter;

  /// The named mechanical oracle (`zero_broken_links`). A class with NO
  /// oracle has NO edit actions (ADR 0024 §6) — its writes route through
  /// the review gate, never raw.
  final String oracle;

  /// The required anchor slot's currency (`heading_path`).
  final String anchors;

  /// ADR 0034 §2 — the class's legal EDIT ACTION names (the closed union
  /// served by the ONE edit verb, class-scoped). Was `verb` (one
  /// per-format verb — the format leak): the surface is one verb; the
  /// registry declares which actions a class answers. Adding a format =
  /// registering this spec (+ materializer), never a new verb.
  final List<String> actions;
}

/// The materializer registry — DATA. One entry per file class with edit
/// actions; the fs tier stamps `edit_actions` on file nodes (`edit_verb`
/// was the per-format verb — ADR 0034 §4) so the tick itself surfaces
/// what a class can do.
const materializerSpecs = <String, MaterializerSpec>{
  'md': MaterializerSpec(
    fileClass: 'md',
    spanCurrency: 'section',
    mapFormat: 'heading_tree',
    emitter: 'section_splice',
    oracle: 'zero_broken_links',
    anchors: 'heading_path',
    actions: ['replace_section', 'insert_section', 'append_to_section'],
  ),
  'yaml': MaterializerSpec(
    fileClass: 'yaml',
    spanCurrency: 'keypath',
    mapFormat: 'keypath_tree',
    emitter: 'keypath_splice',
    oracle: 'parse_semantic_diff',
    anchors: 'keypath',
    actions: ['set_key', 'replace_value', 'delete_key', 'append_list_item'],
  ),
  'json': MaterializerSpec(
    fileClass: 'json',
    spanCurrency: 'keypath',
    mapFormat: 'keypath_tree',
    emitter: 'keypath_splice',
    oracle: 'parse_semantic_diff',
    anchors: 'keypath',
    actions: ['set_key', 'replace_value', 'delete_key', 'append_list_item'],
  ),
};

/// Registry lookup; null → the class has no edit verb yet (review gate
/// only — named, never silent).
MaterializerSpec? materializerSpecFor(String fileClass) =>
    materializerSpecs[fileClass];

/// The registry — DATA. Dart is realized today (symbols + imports);
/// md/yaml/json read-side anchors live in the fs tier's map builder;
/// md's EDIT-side spec is `edit_section` (md_materializer.dart); yaml and
/// json share the `edit_key` verb (yaml_json_materializer.dart: keypath
/// splice, comment-preserving, parse_semantic_diff oracle).
/// `other` is the implicit fallback (visible node, review-mode writes).
const fileClassSpecs = <FileClassSpec>[
  FileClassSpec(fileClass: 'dart', extensions: {'.dart'}, parse: scanDartFile),
  // md is the FIRST non-dart class with a registered materializer spec
  // (the registry map above): the realization is md_materializer.dart
  // (edit_section + the zero_broken_links oracle). yaml/json follow
  // (PLAN §NOW).
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
