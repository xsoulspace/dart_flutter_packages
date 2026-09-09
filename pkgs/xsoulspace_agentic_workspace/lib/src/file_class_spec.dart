// ignore_for_file: lines_longer_as_80_chars

/// ADR 0024 §2 / ADR 0026 §1 — a FILE-CLASS SPEC as data: the unit of
/// extension for the workspace meaning surface.
///
/// Adding a file class = registering a spec (extensions + optional
/// mechanical extractor) in [fileClassSpecs] — never a new loop, never a
/// new tool, never a hardcoded `dartFiles` field. The fs tier builds
/// dir/file nodes for EVERY class; a spec's `parse` adds the class's
/// sub-nodes to the code tier (dart: symbols+imports); a class without a
/// parse fn is owned by the fs tier's map builder through its registered
/// BINDING (md/yaml/json section/key anchors — ADR 0035 §2) and its EDIT
/// side is the binding's perform fn — until then edits route through the
/// review gate.
///
/// Whole-FILE creation is likewise binding-declared, never a raw write:
/// a binding's `fileCreation` capability (materializer_binding.dart)
/// declares the create action + the creation anchor currency, the router
/// addresses it at a DIR node, and the created file node + content
/// sub-nodes land in the map-graph through the same buildFsTier tick. A
/// class whose binding does not declare the capability has NO creation
/// route (a named bounce — never a silent raw-write fallback).
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

/// ADR 0035 §1 — the MaterializerSpec is FOLDED into the binding record
/// (`materializer_binding.dart`): the spec described the edit side as
/// dead strings; the binding carries the realizations (perform fn, map
/// parser, sub-node prefix) plus the same metadata view, validated at
/// registration. This file keeps the FILE-CLASS half: which extensions
/// exist, and the pure sub-node shape the map half stamps.

/// One mapped sub-node the fs tier should stamp (ADR 0035 §2 — pure
/// DATA): the binding's map parser parses; the ENGINE stamps ids, edges
/// and budget green-screen facts. [idTail] is unique within the owning
/// file (the node id is `<prefix><fileNodeId>_<idTail>`, prefix
/// binding-declared).
class MappedSubNode {
  const MappedSubNode({
    required this.kind,
    required this.label,
    required this.idTail,
    required this.props,
  });

  /// The node kind (`section`, `key`).
  final String kind;

  /// The zoom label (the human/mechanical handle).
  final String label;

  /// The id tail unique within the file.
  final String idTail;

  /// Structural props (spans, level/keypath/line — never file text).
  final Map<String, dynamic> props;
}

/// The binding's map-half parser type (parse → data; the engine stamps).
typedef MapParser = List<MappedSubNode> Function(String content);

/// The registry — DATA. Dart is realized today (symbols + imports);
/// md/yaml/json read-side anchors build through their registered
/// bindings' map parsers (materializer_binding.dart); md's edit side is
/// the md binding (md_materializer.dart); yaml and json share the ONE
/// keypath materializer across two bindings (yaml_json_materializer.dart:
/// keypath splice, comment-preserving, parse_semantic_diff oracle).
/// `other` is the implicit fallback (visible node, review-mode writes).
const fileClassSpecs = <FileClassSpec>[
  FileClassSpec(fileClass: 'dart', extensions: {'.dart'}, parse: scanDartFile),
  // md is the FIRST non-dart class with a registered materializer
  // binding (materializer_binding.dart): the realization is
  // md_materializer.dart (section splice + the zero_broken_links
  // oracle). yaml/json share the keypath materializer across two
  // bindings (PLAN §NOW).
  FileClassSpec(fileClass: 'md', extensions: {'.md', '.mdx'}),
  FileClassSpec(fileClass: 'yaml', extensions: {'.yaml', '.yml'}),
  FileClassSpec(fileClass: 'json', extensions: {'.json'}),
  // ts is the FIRST full-code non-dart class (ADR 0035 §6 Tier C v1):
  // the map half is the mechanical scanner (ts_materializer.dart
  // tsScanSymbols/tsMapParser — sym + member nodes, byte-precise spans);
  // the edit half is the ts binding (insert_member / remove_member /
  // apply_executable via pack executables; tsc_no_emit oracle).
  FileClassSpec(fileClass: 'ts', extensions: {'.ts', '.tsx'}),
  // cs is the SECOND full-code non-dart class (ADR 0035 §6 Tier C v1):
  // the map half is the mechanical scanner (cs_materializer.dart
  // csScanSymbols/csMapParser — sym + member nodes, byte-precise spans);
  // the edit half is the cs binding (same three actions; dotnet_build
  // oracle). *.csproj stays class `other` (Tier A: review-gate writes
  // only) — the xml binding is the named-not-built Tier B disposition
  // (PLAN ledger, ADR 0035 §6 Tier B decision 2026-09-08).
  FileClassSpec(fileClass: 'cs', extensions: {'.cs'}),
];

/// Registry lookup; unknown classes fall back to `other` (never a bounce —
/// every file is visible, only its EDIT power differs).
FileClassSpec specForRel(String rel) => fileClassSpecs
    .firstWhere((s) => s.matches(rel),
        orElse: () => const FileClassSpec(fileClass: 'other', extensions: {}));

/// The registry-derived class of [rel] (fs_etl consumes this — the class
/// mapping lives HERE, in the spec data, not in a hardcoded chain).
String fileClassOf(String relPath) => specForRel(relPath).fileClass;
