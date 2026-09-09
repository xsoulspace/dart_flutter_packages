// ignore_for_file: lines_longer_as_80_chars

/// WEB stub for the `xsoulspace_agentic_workspace` barrel (ADR 0003).
///
/// The real workspace tier is dart:io-bound (repo ETL over the file tree,
/// span materializers writing bytes, process oracles) — it cannot compile
/// into the web graph, and the web peer (viewer/answerer) never runs it.
/// The three host files that import the workspace barrel do so via a
/// conditional import: VM/macOS gets the real barrel, the web target gets
/// THIS file. Only the symbols those files actually use are provided; the
/// tool builders refuse with a named [UnsupportedError] when called —
/// no fake success, ever.
library;

import 'dart:io';

import 'package:agentic_executables_wire/agentic_executables_wire.dart'
    show EditExecutableWire;
// ignore: implementation_imports
import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart'
    show FsToolsRoot, JailWriteGateway;
// ignore: implementation_imports
import 'package:xsoulspace_agentic_harness/src/tools/meaning_query_tools.dart'
    show MeaningSpanReader;
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart'
    show World;
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart'
    show ToolDef;

/// ETL scan bookkeeping. Opaque on web: only ever constructed and handed
/// back to [repoEtlTool], which refuses.
class RepoEtlState {
  RepoEtlState();
}

/// An edit plan. Opaque surface on web: only referenced as a callback
/// parameter type (the host edit approver), never constructed.
class SpanEditPlan {
  SpanEditPlan({required this.patches, required this.description});

  final List<SpanPatch> patches;
  final String description;

  bool get isAtomic => patches.length > 1;
}

/// One span patch. Opaque surface on web: the host reads only `.file`
/// (the workspace-relative target) for consent-plan matching.
class SpanPatch {
  SpanPatch({
    required this.file,
    required this.startLine,
    required this.endLine,
    required this.replacement,
    required this.reason,
  });

  final String file;
  final int startLine;
  final int endLine;
  final String replacement;
  final String reason;
}

/// Span materializer. Opaque on web: constructed by the meaning-profile
/// surface only to be handed to [editSymbolTool], which refuses.
class SpanEditMaterializer {
  SpanEditMaterializer({
    required this.world,
    required this.workspace,
    this.approver,
    this.packConsent,
  });

  final World world;
  final Directory workspace;

  /// Host edit approver (deny-by-default on the VM path).
  final Future<bool> Function(SpanEditPlan plan)? approver;

  /// Pack-write consent gate (deny-by-default on the VM path).
  final bool Function(EditExecutableWire wire, String authoredBodyDiff)?
  packConsent;
}

/// repo_etl (scan/refresh over the workspace tree) — dart:io; refuses.
ToolDef repoEtlTool(World world, Directory workspace, {RepoEtlState? state}) =>
    _refuse('repo_etl');

/// Meaning span reader over an fs jail — dart:io; refuses when called.
MeaningSpanReader meaningSpanReader(FsToolsRoot root) =>
    (props, budgetTokens) => _refuse('meaning_span_reader');

/// The consent-gated escape-hatch write — dart:io; refuses.
ToolDef writeReviewTool(FsToolsRoot root, JailWriteGateway gateway) =>
    _refuse('write_review');

/// The one edit verb (symbol edits) — refuses.
ToolDef editSymbolTool(
  World world,
  Directory workspace, {
  SpanEditMaterializer? materializer,

  /// Host edit approver (consent-gated mechanical edits); the verb itself
  /// still refuses — the web peer never runs the dart:io edit tier.
  Future<bool> Function(SpanEditPlan plan)? approver,
}) => _refuse('edit_symbol');

/// Legacy doc-section verb (surface parity only) — refuses.
ToolDef editMdTool(World world, Directory workspace) => _refuse('edit_md');

/// Legacy config-key verb (surface parity only) — refuses.
ToolDef editKeyTool(World world, Directory workspace) => _refuse('edit_key');

/// The honest refusal every stub tool carries: the web peer never runs
/// the workspace tier (ADR 0003), so any call is a caller bug surfaced as
/// named data instead of a silent fake success.
Never _refuse(String tool) => throw UnsupportedError(
  '$tool requires the dart:io workspace tier (repo ETL / span '
  'materializers) — unavailable on the web platform (ADR 0003: the web '
  'peer is a viewer/answerer)',
);
