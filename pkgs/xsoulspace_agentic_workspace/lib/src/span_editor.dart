// ignore_for_file: lines_longer_than_80_chars

/// R7b — the span-edit materializer (ADR 0023 §2): the actor's ACT verb for
/// EXISTING code.
///
/// The model composes ONE tool call (`edit_symbol`); the HOST computes the
/// span-anchored patches, applies them, verifies with the mechanical tier
/// (`dart analyze` + the workspace convention) and auto-reverts on any
/// failure. The model never sees the old body text, never writes code
/// tokens, never holds a file.
///
/// Move vocabulary (ONE tool, minimal closed enum — B4 lesson: rename was
/// deleted twice, as a surface duplication (ADR 0016 era) and as a parallel
/// text-patch path (`tree_patch.dart`, B4 2026-09-01); do not rebuild either
/// mistake):
///
/// - `replace_member_body{symbolId, opChain}` — host-compiled body via the
///   R6 compiler ([compileOpChainBody]); the ONLY model-composed move for
///   existing code.
/// - `insert_member{classSymbolId, params, returns, opChain}` — the other
///   model-composed move (new member; the workspace suite grades it).
/// - `apply_executable{executableId, symbolId, params}` — pack-fed edits
///   (R7d; the default pack ships the lexical rename executable).
///
/// Cross-file operations (`rename_symbol`) are DEFAULT-PACK edit
/// executables, not core enum cases (ADR 0019 §4: growth is pack/data-driven,
/// never hand-added verbs). The v1 rename is `scope: lexical`: identifier
/// replacement over the refs-frontier only; getter/setter pairs, named
/// constructors, operators and named-parameter API breaks BOUNCE as named
/// data (analyzer-grade rename is P4/J3).
///
/// The three host-enforced fences (gate-asserted, never silently downgraded):
/// - (a) expressiveness: the compiled body must stay inside the closed pure
///   vocabulary — state ops, backward jumps, undeclared load_args bounce;
/// - (b) ORACLE COVERAGE: a legacy member may be replaced only when the
///   workspace-oracle ETL (test_etl) derives expectations covering it —
///   the actor never sees the old body, so an uncovered replacement would
///   destroy untested behavior with nothing in the pipeline noticing;
/// - (c) integration: the compiled body must reference only declared params
///   and known workspace identifiers, and carry a `return` when the member
///   is non-void — validated BEFORE generation.
///
/// Batches are atomic: a move expanding to N patches is all-or-nothing
/// (in-memory revert, no git) with a mandatory lock pre-check over the
/// single-writer `FileLockTable`. Batch is a property of the executable,
/// never a second tool.
library;

import 'dart:io';

import 'package:agentic_executables_wire/agentic_executables_wire.dart'
    show EditExecutableKind, EditExecutableWire;
import 'package:ecsly/ecsly.dart';
import 'package:source_span/source_span.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart'
    show FM, SchemaBundle, ToolDef, ToolName;
import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart'
    show FileLockTable;
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart'
    show
        MeaningIndex,
        MeaningNode,
        MeaningProps,
        resolveWorkspaceCheck,
        impactFrontier,
        meaningComponentOf;

import 'dart_materializer.dart' show compileOpChainBody;
import 'edit_pack_capture.dart' show EditPackCapture;
import 'test_etl.dart' show deriveWorkspaceIntents;

// ---------------------------------------------------------------------------
// Data shapes
// ---------------------------------------------------------------------------

/// One host-computed span patch: replace [startLine]..[endLine] (1-based,
/// inclusive) of [file] with [replacement]. Line anchors come from the
/// meaning tree (`file`/`line` props) + the host's own brace matching —
/// never from the model.
class SpanPatch {
  SpanPatch({
    required this.file,
    required this.startLine,
    required this.endLine,
    required this.replacement,
    required this.reason,
  });
  final String file; // workspace-relative
  final int startLine;
  final int endLine;
  final String replacement;
  final String reason;
}

/// A validated edit plan: every patch present, non-overlapping, in-range.
class SpanEditPlan {
  SpanEditPlan({required this.patches, required this.description});
  final List<SpanPatch> patches;
  final String description;

  bool get isAtomic => patches.length > 1;
}

/// The verify-state baseline of a workspace, cached as a WORLD RESOURCE
/// (the ECS discipline: state lives in the world, not in process reruns).
/// The post-state of a green move IS the next move's pre-state — one
/// oracle run per STATE CHANGE, never per move. This is what keeps the
/// edit tier microseconds-cheap in the tree work and seconds-only in the
/// free oracle tier (whole-package runs happen once per session baseline,
/// never per move).
class SpanVerifyBaseline extends Resource {
  /// null = unknown (not yet measured). True = full analyze + workspace
  /// convention were green at the last state change.
  bool? clean;
}

/// The outcome of applying a plan. Failures are classified data — never
/// dropped ([failureClass]).
class SpanEditOutcome {
  SpanEditOutcome({
    required this.ok,
    required this.reverted,
    required this.detail,
    this.patchesApplied = 0,
    this.filesTouched = const [],
    this.analyzeExit,
    this.checkExit,
    this.analyzeMs,
    this.checkMs,
    this.failureClass = '',
  });
  final bool ok;

  /// True when bytes were written and then restored (verify tier failed).
  final bool reverted;
  final int patchesApplied;
  final List<String> filesTouched;
  final int? analyzeExit;
  final int? checkExit;

  /// Per-phase wall-clock (transparency: the profiler reads these — the
  /// ECS/projection work is microseconds; the oracle tier is seconds).
  final int? analyzeMs;
  final int? checkMs;
  final String detail;
  final String failureClass;

  bool get appliedClean => ok && !reverted;

  Map<String, dynamic> toJson() => {
    'ok': ok,
    'reverted': reverted,
    'patches': patchesApplied,
    'files': filesTouched,
    if (analyzeExit != null) 'analyze_exit': analyzeExit,
    if (checkExit != null) 'check_exit': checkExit,
    if (analyzeMs != null) 'analyze_ms': analyzeMs,
    if (checkMs != null) 'check_ms': checkMs,
    'detail': detail,
    if (failureClass.isNotEmpty) 'failure_class': failureClass,
  };
}

/// A structured bounce: the exact repair move (B2 dialect), before ANY
/// bytes are touched.
class SpanEditBounce implements Exception {
  SpanEditBounce(this.error, this.repair, {this.fence});
  final String error;
  final String repair;

  /// Which host-enforced fence fired: 'expressiveness' | 'coverage' |
  /// 'integration' | null (plain validation).
  final String? fence;

  Map<String, dynamic> toJson() => {
    'ok': false,
    'bounce': true,
    'error': error,
    'repair': repair,
    if (fence != null) 'fence': fence,
  };

  @override
  String toString() =>
      fence == null ? '$error — $repair' : '[$fence] $error — $repair';
}

/// The default (built-in) edit executables. Growth is pack/data-driven
/// (ADR 0019 §4 / ADR 0023 §3): never a hand-added core verb. The rename
/// executable lives HERE, as data, exactly so it cannot become a hardcoded
/// core sub-action again (the B4 hard cut).
const defaultEditExecutables = <String, Map<String, dynamic>>{
  'rename_symbol': {
    'scope': 'lexical',
    'atomic': true,
    'args': ['newName'],
    'description':
        'Lexical rename across the refs frontier (whole-identifier '
        'replacement in files that reference the symbol). Bounces on '
        'getters/setters, operators, named constructors and same-name '
        'ambiguity (scope: lexical; analyzer-grade is P4/J3).',
  },
};

/// State-carrying / non-pure ops: the v1 dart target compiles pure,
/// static-like bodies only (fence a) — never silently downgrade a working
/// member.
const _impureOps = {
  'load_state',
  'store_state',
  'push_state',
  'drop_from_state',
  'error',
};

// ---------------------------------------------------------------------------
// The materializer
// ---------------------------------------------------------------------------

class SpanEditMaterializer {
  SpanEditMaterializer({
    required this.world,
    required this.workspace,

    /// Single-writer lock table (squad discipline). A move claims every
    /// file it touches BEFORE bytes are written; any conflict bounces the
    /// whole move.
    FileLockTable? locks,
    this.owner = 'span_editor',

    /// Lazy oracle-coverage provider (fence b). Default: derived from the
    /// workspace's own test suite (zero host-authored expectations).
    Set<String> Function()? coverage,

    /// R7c: the HOST approver (deny-by-default). When wired, every applied
    /// move asks the approver before ANY byte lands — the daemon routes
    /// this to the ACP client's permission round-trip.
    Future<bool> Function(SpanEditPlan plan)? approver,

    /// R7d: PACK-DECLARED edit executables (ADR 0023 §3) — know packs and
    /// project repair packs supply parameterized moves as DATA; the model
    /// picks an id and fills bounded slots (for body-kind executables the
    /// op-chain itself travels with the pack, so a pack-fed move costs
    /// ZERO authored tokens). The host validates every wire shape and
    /// realizes the kinds it knows; unknown kinds bounce as named data.
    List<EditExecutableWire>? packExecutables,
  }) : locks = locks ?? FileLockTable(),
       _coverageProvider = coverage,
       _approver = approver,
       _packExecutables = {
         for (final e in packExecutables ?? const <EditExecutableWire>[])
           e.id: e,
       };

  final World world;
  final Directory workspace;
  final FileLockTable locks;
  final Object owner;
  final Set<String> Function()? _coverageProvider;
  final Future<bool> Function(SpanEditPlan plan)? _approver;
  final Map<String, EditExecutableWire> _packExecutables;
  Set<String>? _coverageCache;

  /// The op-chains a pack's body-kind executables carry (data, per pack —
  /// this is the R7d zero-authored-tokens seam; the wire shape carries the
  /// verification + scope, the chain rides on the same pack entry).
  final Map<String, List<Map<String, String?>>> _packOpChains = {};

  /// Symbol names the workspace oracle has expectations for (fence b).
  Set<String> coverageSet() => _coverageCache ??=
      _coverageProvider?.call() ??
      {for (final i in deriveWorkspaceIntents(workspace).intents) i.intent};

  String _abs(String rel) => '${workspace.path}/$rel';

  MeaningIndex _index() {
    try {
      return world.getResource<MeaningIndex>();
    } on StateError {
      throw StateError(
        'no meaning tree in this world — repo_etl scan first (the tree is '
        'the only code interface)',
      );
    }
  }

  ({String id, String kind, String label, Map<String, dynamic> props})? _node(
    String id,
  ) {
    final index = _index();
    final entity = index.byId[id];
    if (entity == null) return null;
    final node = meaningComponentOf<MeaningNode>(world, entity);
    if (node == null) return null;
    final props =
        meaningComponentOf<MeaningProps>(world, entity)?.props ??
        const <String, dynamic>{};
    return (id: node.id, kind: node.kind, label: node.label, props: props);
  }

  ({String id, String kind, String label, Map<String, dynamic> props})
  _requireSymbol(String? id) {
    if (id == null || id.isEmpty) {
      throw SpanEditBounce(
        'missing symbolId',
        're-send the move with symbolId as a TOP-LEVEL edit_symbol arg '
            '(the id from meaning_zoom, e.g. "sym_lib_loop.dart_inBounds") '
            '— NOT inside executableParams and NOT as name; executableParams '
            'carries only the executable\'s own slots (e.g. newName)',
      );
    }
    final n = _node(id);
    if (n == null || n.kind != 'symbol') {
      // Fail with navigable data: suffix-match hints.
      final index = _index();
      final hints = [
        for (final key in index.byId.keys)
          if (id.length > 3 && key.contains(id)) key,
      ].take(5).toList();
      throw SpanEditBounce(
        'unknown symbol id: $id',
        'zoom to find the symbol, then re-send with a valid symbolId'
            '${hints.isEmpty ? "" : " (candidates: ${hints.join(", ")})"}',
      );
    }
    return n;
  }

  Set<String> _knownSymbolLabels() {
    final index = _index();
    final out = <String>{};
    for (final entry in index.byId.entries) {
      final node = meaningComponentOf<MeaningNode>(world, entry.value);
      if (node != null && node.kind == 'symbol') out.add(node.label);
    }
    return out;
  }

  // -------------------------------------------------------------------------
  // PLAN — pure validation; never touches bytes
  // -------------------------------------------------------------------------

  SpanEditPlan plan({
    String? action,
    String? symbolId,
    String? classSymbolId,
    String? executableId,
    String? name,
    String? returns,
    List<String> params = const [],
    List<Map<String, String?>> opChain = const [],
    Map<String, dynamic> executableParams = const {},
  }) {
    switch (action) {
      case 'replace_member_body':
        return _planReplaceMemberBody(symbolId: symbolId, opChain: opChain);
      case 'insert_member':
        return _planInsertMember(
          classSymbolId: classSymbolId,
          name: name,
          returns: returns,
          params: params,
          opChain: opChain,
        );
      case 'apply_executable':
        return _planApplyExecutable(
          executableId: executableId,
          symbolId: symbolId,
          params: executableParams,
        );
      case 'remove_member':
        return _planRemoveMember(symbolId: symbolId);
      default:
        throw SpanEditBounce(
          'unknown edit action: $action',
          'valid actions: replace_member_body, insert_member, '
              'apply_executable, remove_member',
        );
    }
  }

  SpanEditPlan _planReplaceMemberBody({
    String? symbolId,
    required List<Map<String, String?>> opChain,
  }) {
    final sym = _requireSymbol(symbolId);
    final decl = sym.props['decl'] as String?;
    const bodyKinds = {'method', 'function', 'getter'};
    if (!bodyKinds.contains(decl)) {
      throw SpanEditBounce(
        '${sym.id} is a $decl — only methods, functions and getters have '
            'replaceable bodies',
        'target a method/function symbol (see meaning_zoom), or use '
            'insert_member for new members',
      );
    }
    final file = sym.props['file'] as String?;
    final declLine = (sym.props['line'] as num?)?.toInt();
    if (file == null || declLine == null) {
      throw SpanEditBounce(
        '${sym.id} carries no file/line props — re-run repo_etl scan',
        'action scan, then retry the move',
      );
    }
    if (opChain.isEmpty) {
      throw SpanEditBounce(
        'empty opChain',
        're-send with specs (op rows {label, a?, b?}) — the host compiles '
            'the body, you compose meaning only',
      );
    }
    final site = _memberSite(file, sym.label, declLine);

    // FENCE (c) — integration, BEFORE generation: op-level checks against
    // the declared signature and the file's identifiers.
    for (final row in opChain) {
      final label = row['label'] ?? '';
      // Fence (a) pre-check: state ops are named data, never downgraded.
      if (_impureOps.contains(label)) {
        throw SpanEditBounce(
          'op "$label" has no pure-dart realization — the v1 dart target '
              'compiles pure/static-like bodies only',
          'express the logic as pure ops over the declared params '
              '(${site.paramNames.join(", ")}), or target a different member; '
              'never replace working stateful code with a downgrade',
          fence: 'expressiveness',
        );
      }
      if (label == 'call') {
        final callee = row['a'] ?? '';
        if (callee.isNotEmpty &&
            !site.paramNames.contains(callee) &&
            !_knownSymbolLabels().contains(callee)) {
          throw SpanEditBounce(
            'call target "$callee" is neither a declared param nor a '
                'known symbol of this workspace',
            'call an existing intent/symbol (check with meaning_zoom) or '
                'a param',
            fence: 'integration',
          );
        }
      }
      if (label == 'load_arg' && !site.paramNames.contains(row['a'] ?? '')) {
        throw SpanEditBounce(
          'load_arg "${row['a']}" is not a declared param of '
              '${sym.label}(${site.paramNames.join(", ")})',
          'use exactly the declared params: '
              '${site.paramNames.join(", ")}',
          fence: 'integration',
        );
      }
    }
    final needsReturn = site.returnType.isNotEmpty && site.returnType != 'void';
    final hasReturn = opChain.any((r) => r['label'] == 'return');
    if (needsReturn && !hasReturn) {
      throw SpanEditBounce(
        '${sym.label} returns ${site.returnType} — the chain must end at a '
            'return op',
        'append {label: return} after pushing the result value',
        fence: 'integration',
      );
    }

    // FENCE (a) — expressiveness, via the compiler (the named-problem
    // surface: backward jumps, stack underflow, unknown ops).
    final compiled = compileOpChainBody(opChain, paramNames: site.paramNames);
    if (compiled.problem != null) {
      throw SpanEditBounce(
        'chain does not compile to pure dart: ${compiled.problem}',
        're-compose the chain within the closed pure vocabulary '
            '(load_arg, literal, add, sub, mul, lt, gt, eq, not, starts_with, '
            'list_len, get_item, call, jump_if_false, return)',
        fence: 'expressiveness',
      );
    }

    // FENCE (b) — ORACLE COVERAGE: a legacy member may be replaced only
    // when the workspace ETL derived expectations covering it.
    if (!coverageSet().contains(sym.label)) {
      throw SpanEditBounce(
        'no oracle coverage for "${sym.label}": the workspace suite derives '
            'no expectations for it, so a replacement would destroy untested '
            'behavior with nothing in the pipeline noticing',
        'add suite coverage first (expect(${sym.label}(...), ...) in '
            'test/) — the coverage routes to the pack/operator capture loop',
        fence: 'coverage',
      );
    }

    final indent = site.declIndent;
    final bodyIndent = '$indent  ';
    final body = compiled.code!
        .trim()
        .split('\n')
        .map((l) => l.trim().isEmpty ? '' : '$bodyIndent$l')
        .join('\n');
    final replacement =
        '${site.signatureText}\n'
        '$body\n'
        '$indent}';
    return SpanEditPlan(
      description:
          'replace_member_body ${sym.label} (${sym.id}) in $file '
          '[${site.declLine0 + 1}..${site.closeLine0 + 1}]',
      patches: [
        SpanPatch(
          file: file,
          startLine: site.declLine0 + 1,
          endLine: site.closeLine0 + 1,
          replacement: replacement,
          reason: 'host-compiled op chain (${opChain.length} ops)',
        ),
      ],
    );
  }

  SpanEditPlan _planInsertMember({
    String? classSymbolId,
    String? name,
    String? returns,
    required List<String> params,
    required List<Map<String, String?>> opChain,
  }) {
    final sym = _requireSymbol(classSymbolId);
    final decl = sym.props['decl'] as String?;
    if (!{'class', 'mixin', 'extension'}.contains(decl)) {
      throw SpanEditBounce(
        '${sym.id} is a $decl — insert_member targets a class/mixin/'
            'extension symbol',
        'zoom to find the enclosing class symbol id',
      );
    }
    if (name == null || !RegExp(r'^[A-Za-z_$][\w$]*$').hasMatch(name)) {
      throw SpanEditBounce(
        'invalid member name: $name',
        're-send with a legal Dart identifier as name',
        fence: 'integration',
      );
    }
    final parsedParams = <(String, String)>[]; // (name, type)
    for (final p in params) {
      final m = RegExp(r'^\s*([A-Za-z_$][\w$]*)\s*:\s*(.+?)\s*$').firstMatch(p);
      if (m == null) {
        throw SpanEditBounce(
          'invalid param "$p" (expected "name:type")',
          're-send params as ["name:type", ...]',
          fence: 'integration',
        );
      }
      parsedParams.add((m.group(1)!, m.group(2)!));
    }
    final paramNames = parsedParams.map((p) => p.$1).toSet();

    // Fence checks shared with replace_member_body (state ops, call
    // targets, load_args).
    for (final row in opChain) {
      final label = row['label'] ?? '';
      if (_impureOps.contains(label)) {
        throw SpanEditBounce(
          'op "$label" has no pure-dart realization — the v1 dart target '
              'compiles pure/static-like bodies only',
          'express the logic as pure ops over the declared params',
          fence: 'expressiveness',
        );
      }
      if (label == 'call') {
        final callee = row['a'] ?? '';
        if (callee.isNotEmpty &&
            !paramNames.contains(callee) &&
            !_knownSymbolLabels().contains(callee)) {
          throw SpanEditBounce(
            'call target "$callee" is neither a declared param nor a known '
                'symbol of this workspace',
            'call an existing intent/symbol (check with meaning_zoom) or a '
                'param',
            fence: 'integration',
          );
        }
      }
      if (label == 'load_arg' && !paramNames.contains(row['a'] ?? '')) {
        throw SpanEditBounce(
          'load_arg "${row['a']}" is not a declared param of $name',
          'use exactly the declared params: ${parsedParams.map((p) => p.$1).join(", ")}',
          fence: 'integration',
        );
      }
    }
    final ret = returns ?? 'void';
    if (ret != 'void' && !opChain.any((r) => r['label'] == 'return')) {
      throw SpanEditBounce(
        '$name returns $ret — the chain must end at a return op',
        'append {label: return} after pushing the result value',
        fence: 'integration',
      );
    }
    final compiled = compileOpChainBody(opChain, paramNames: paramNames);
    if (compiled.problem != null) {
      throw SpanEditBounce(
        'chain does not compile to pure dart: ${compiled.problem}',
        're-compose the chain within the closed pure vocabulary',
        fence: 'expressiveness',
      );
    }

    // Duplicate member check (ambiguity is data, never a silent overwrite).
    final index = _index();
    final className = sym.label;
    for (final entry in index.byId.entries) {
      final node = meaningComponentOf<MeaningNode>(world, entry.value);
      if (node == null || node.kind != 'symbol' || node.label != name) {
        continue;
      }
      final props =
          meaningComponentOf<MeaningProps>(world, entry.value)?.props ??
          const <String, dynamic>{};
      if (props['member_of'] == className) {
        throw SpanEditBounce(
          'class $className already has a member named $name',
          'pick another name or replace the existing member with '
              'replace_member_body (symbolId: ${entry.key})',
          fence: 'integration',
        );
      }
    }

    final file = sym.props['file'] as String?;
    final declLine = (sym.props['line'] as num?)?.toInt();
    if (file == null || declLine == null) {
      throw SpanEditBounce(
        '${sym.id} carries no file/line props — re-run repo_etl scan',
        'action scan, then retry the move',
      );
    }
    final text = File(_abs(file)).readAsStringSync();
    final lines = text.split('\n');
    final declLine0 = declLine - 1;
    final declIndent =
        RegExp(r'^\s*').firstMatch(lines[declLine0])?.group(0) ?? '';
    final bodyIndent = '$declIndent  ';
    final openLine0 = _findClassBodyOpen(lines, declLine0, className);
    if (openLine0 == null) {
      throw SpanEditBounce(
        'cannot locate the class body brace of $className in $file',
        're-run repo_etl scan; if the file is not dart-formatted it is '
            'outside the v1 scanner scope',
      );
    }
    final closeLine0 = _matchBrace(lines, openLine0);
    if (closeLine0 == null || lines[closeLine0].trim() != '}') {
      throw SpanEditBounce(
        'cannot locate the closing brace line of $className in $file',
        'the v1 materializer expects dart-formatted sources (closing brace '
            'on its own line)',
      );
    }
    final paramStr = parsedParams.map((p) => '${p.$2} ${p.$1}').join(', ');
    final body = compiled.code!
        .trim()
        .split('\n')
        .map((l) => l.trim().isEmpty ? '' : '$bodyIndent  $l')
        .join('\n');
    final member =
        '\n'
        '$bodyIndent$ret $name($paramStr) {\n'
        '$body\n'
        '$bodyIndent}\n';
    return SpanEditPlan(
      description: 'insert_member $name into $className ($file)',
      patches: [
        SpanPatch(
          file: file,
          startLine: closeLine0 + 1,
          endLine: closeLine0 + 1,
          replacement: '$member${lines[closeLine0]}',
          reason: 'insert member before class closing brace',
        ),
      ],
    );
  }

  SpanEditPlan _planApplyExecutable({
    String? executableId,
    String? symbolId,
    required Map<String, dynamic> params,
  }) {
    final spec = defaultEditExecutables[executableId];
    if (spec == null) {
      // R7d: pack-declared executables — the primary verb; growth is
      // pack/data-driven (ADR 0019 §4 / ADR 0023 §3).
      final pack = _packExecutables[executableId];
      if (pack == null) {
        throw SpanEditBounce(
          'unknown edit executable: $executableId',
          'built-ins: ${defaultEditExecutables.keys.join(", ")}; project '
              'packs supply more (register via registerPackExecutable)',
        );
      }
      switch (pack.kind) {
        case EditExecutableKind.replaceMemberBody:
          final chain = _packOpChains[executableId];
          if (chain == null || chain.isEmpty) {
            throw SpanEditBounce(
              'pack executable "$executableId" carries no op-chain '
                  '(the host realizes body-kind packs from pack data)',
              'register the op-chain with the pack entry (data, never '
                  'authored by the model)',
            );
          }
          return _planReplaceMemberBody(symbolId: symbolId, opChain: chain);
        case EditExecutableKind.renameSymbol:
          return _planRename(symbolId, params);
        default:
          throw SpanEditBounce(
            'pack executable kind "${pack.kind.wire}" has no host '
                'realization in this span editor',
            'realize the kind host-side (the wire stays syntax-only)',
          );
      }
    }
    switch (executableId) {
      case 'rename_symbol':
        return _planRename(symbolId, params);
      default:
        throw SpanEditBounce(
          'executable "$executableId" has no host realization registered',
          'register it in a project pack with a host-side expansion',
        );
    }
  }

  /// R7d — registers a pack-declared executable with its (optional) body
  /// op-chain. The chain travels with the PACK as data; the model never
  /// authors it (zero authored tokens for known classes).
  void registerPackExecutable(
    EditExecutableWire wire, {
    List<Map<String, String?>>? opChain,
  }) {
    _packExecutables[wire.id] = wire;
    if (opChain != null) _packOpChains[wire.id] = opChain;
  }

  /// The lexical rename executable: expand over the impact frontier into
  /// per-file whole-identifier patches. Ambiguity bounces — never guess
  /// (ADR 0023 §2).
  SpanEditPlan _planRename(String? symbolId, Map<String, dynamic> params) {
    final sym = _requireSymbol(symbolId);
    final oldName = sym.label;
    final newName = params['newName'] as String?;
    if (newName == null || !RegExp(r'^[A-Za-z_$][\w$]*$').hasMatch(newName)) {
      throw SpanEditBounce(
        'invalid newName: $newName',
        're-send params: {newName: <legal dart identifier>}',
      );
    }
    final decl = sym.props['decl'] as String?;
    if (decl == 'getter') {
      throw SpanEditBounce(
        '"$oldName" is a getter — getter/setter pairs break under a '
            'lexical rename',
        'bounce accepted: use scope analyzer (P4/J3) or rename both '
            'accessors via separate covered moves',
        fence: 'integration',
      );
    }
    final declLine = (sym.props['line'] as num?)?.toInt();
    final file = sym.props['file'] as String?;
    if (file != null && declLine != null) {
      final line = File(
        _abs(file),
      ).readAsStringSync().split('\n')[declLine - 1];
      if (RegExp(r'\w+\.\w+\s*\(').hasMatch(line)) {
        throw SpanEditBounce(
          '"$oldName" looks like a named constructor/tear-off — file '
              'conventions break under a lexical rename',
          'bounce accepted: named constructors are out of the lexical '
              'scope (P4/J3)',
          fence: 'integration',
        );
      }
      if (line.contains('operator')) {
        throw SpanEditBounce(
          '"$oldName" is an operator — operators cannot be renamed',
          'bounce accepted',
          fence: 'integration',
        );
      }
    }

    // Ambiguity: another symbol with the SAME name anywhere in the tree —
    // the lexical scope cannot tell them apart. Bounce as data.
    final index = _index();
    final twins = <String>[];
    for (final entry in index.byId.entries) {
      if (entry.key == sym.id) continue;
      final node = meaningComponentOf<MeaningNode>(world, entry.value);
      if (node != null && node.kind == 'symbol' && node.label == oldName) {
        twins.add(entry.key);
      }
    }
    if (twins.isNotEmpty) {
      throw SpanEditBounce(
        'ambiguous rename: ${twins.length} other symbol(s) named '
            '"$oldName": ${twins.join(", ")}',
        'disambiguate first (rename the others away or narrow the scan), '
            'then retry — the analyzer is the oracle, guessing is banned',
      );
    }
    // Collision with an existing name.
    if (_knownSymbolLabels().contains(newName)) {
      throw SpanEditBounce(
        'rename collides with an existing symbol named "$newName"',
        'pick a free name (check with meaning_zoom query)',
      );
    }

    // Frontier expansion: refs edges (hard-capped, degree-ranked).
    final frontier = impactFrontier(world, sym.id, maxDepth: 2, maxNodes: 256);
    final files = <String>{if (file != null) file};
    var capped = false;
    for (final id in frontier) {
      final n = _node(id);
      if (n == null) continue;
      if (n.kind == 'file') {
        files.add(n.label);
      } else if (n.props['file'] is String) {
        files.add(n.props['file'] as String);
      }
    }
    if (frontier.length >= 256) capped = true;

    final patches = <SpanPatch>[];
    for (final f in files) {
      final text = File(_abs(f)).readAsStringSync();
      final lines = text.split('\n');
      for (var i = 0; i < lines.length; i++) {
        final modified = _replaceWholeIdentifiers(lines[i], oldName, newName);
        if (modified == null) continue;
        patches.add(
          SpanPatch(
            file: f,
            startLine: i + 1,
            endLine: i + 1,
            replacement: modified,
            reason: 'lexical rename $oldName → $newName',
          ),
        );
      }
    }
    if (patches.isEmpty) {
      throw SpanEditBounce(
        'no references to "$oldName" found on the frontier',
        'refresh the tree (repo_etl action refresh) — the refs edges may '
            'be stale',
      );
    }
    return SpanEditPlan(
      description:
          'rename_symbol $oldName → $newName (${patches.length} line '
          'patches across ${files.length} candidate files'
          '${capped ? ", FRONTIER CAPPED at 256" : ""})',
      patches: patches,
    );
  }

  /// ADR 0027 amendment — RETIRE (meaning-first deletion): the model
  /// never addresses files. Removing a member is a meaning decision
  /// ("this intent is dead"); the HOST derives the fs consequence (the
  /// member's line range plus its doc comment pruned) and the
  /// refs-frontier fence proves the model retired the referencers first
  /// (multi-op decision, composable). The scoped post-analyze is the
  /// nothing-dangles oracle — a lexical miss (strings, comments) still
  /// bounces as named data.
  SpanEditPlan _planRemoveMember({String? symbolId}) {
    final sym = _requireSymbol(symbolId);
    final decl = sym.props['decl'] as String?;
    final file = sym.props['file'] as String?;
    final declLine = (sym.props['line'] as num?)?.toInt();
    if (file == null || declLine == null) {
      throw SpanEditBounce(
        '${sym.id} carries no file/line props — re-run repo_etl scan',
        'action scan, then retry the move',
      );
    }
    // v1 scope: brace-bodied members with a paren list (the same shape
    // replace_member_body realizes). Everything else bounces honestly.
    final site = _memberSite(file, sym.label, declLine);
    if (decl != null && !{'method', 'function', 'getter'}.contains(decl)) {
      throw SpanEditBounce(
        '${sym.id} is a $decl — remove_member v1 targets methods, '
            'functions and getters (brace-bodied, single-line signature)',
        'retire the enclosing class/intent instead, or express the '
            'removal as a refactor executable in the project pack',
      );
    }

    // REFS FENCE — every remaining whole-identifier reference OUTSIDE the
    // member's own span bounces as named data. The model composes the
    // retire as a multi-op decision (referencers first).
    final frontier = impactFrontier(world, sym.id, maxDepth: 2, maxNodes: 256);
    final files = <String>{if (file != null) file};
    for (final id in frontier) {
      final n = _node(id);
      if (n == null) continue;
      if (n.kind == 'file') {
        files.add(n.label);
      } else if (n.props['file'] is String) {
        files.add(n.props['file'] as String);
      }
    }
    final refs = <String>[];
    for (final f in files) {
      final lines = File(_abs(f)).readAsStringSync().split('\n');
      for (var i = 0; i < lines.length; i++) {
        final onOwnSpan =
            f == file &&
            i + 1 >= site.declLine0 + 1 &&
            i + 1 <= site.closeLine0 + 1;
        if (onOwnSpan) continue; // the member's own span goes away with it
        if (_replaceWholeIdentifiers(lines[i], sym.label, '\u0000') != null) {
          refs.add('$f:${i + 1}');
          if (refs.length >= 10) break;
        }
      }
      if (refs.length >= 10) break;
    }
    if (refs.isNotEmpty) {
      throw SpanEditBounce(
        '"${sym.label}" still has ${refs.length}+ reference(s): '
            '${refs.join(", ")}',
        'retire the referencers first (one decision may carry the whole '
            'op chain), then re-send this move',
        fence: 'integration',
      );
    }

    // Doc-comment pruning: contiguous `///` lines above the decl die with
    // the member (the materializer prunes, it never leaves skeletons).
    final lines = File(_abs(file)).readAsStringSync().split('\n');
    var startLine0 = site.declLine0;
    while (startLine0 > 0 &&
        lines[startLine0 - 1].trimLeft().startsWith('///')) {
      startLine0--;
    }

    return SpanEditPlan(
      description:
          'remove_member ${sym.label} (${sym.id}) in $file '
          '[${startLine0 + 1}..${site.closeLine0 + 1}] (retired — fs '
          'layout re-derives)',
      patches: [
        SpanPatch(
          file: file,
          startLine: startLine0 + 1,
          endLine: site.closeLine0 + 1,
          replacement: '',
          reason: 'retired: orphan pruning by re-derivation (ADR 0027 '
              'amendment — the model never addresses files)',
        ),
      ],
    );
  }

  /// Whole-identifier replacement on one line; null when the name does not
  /// occur as a standalone identifier.
  String? _replaceWholeIdentifiers(String line, String from, String to) {
    if (!line.contains(from)) return null;
    final buf = StringBuffer();
    var changed = false;
    var i = 0;
    while (i < line.length) {
      if (line.startsWith(from, i)) {
        final before = i == 0 ? '' : line[i - 1];
        final after = i + from.length >= line.length
            ? ''
            : line[i + from.length];
        final boundaryBefore = !RegExp(r'[\w$]').hasMatch(before);
        final boundaryAfter = !RegExp(r'[\w$]').hasMatch(after);
        if (boundaryBefore && boundaryAfter) {
          buf.write(to);
          changed = true;
          i += from.length;
          continue;
        }
      }
      buf.write(line[i]);
      i++;
    }
    return changed ? buf.toString() : null;
  }

  // -------------------------------------------------------------------------
  // APPLY — atomic write + mechanical verification + in-memory revert
  // -------------------------------------------------------------------------

  Future<SpanEditOutcome> apply(SpanEditPlan plan) async {
    // Lock pre-check over the single-writer table: claim EVERY file, or
    // nothing (all-or-nothing is a property of the move).
    final files = plan.patches.map((p) => p.file).toSet().toList()..sort();
    final claimed = <String>[];
    for (final f in files) {
      if (!locks.claim(f, owner)) {
        for (final c in claimed) {
          locks.release(c, owner);
        }
        final holder = locks.ownerOf(f);
        return SpanEditOutcome(
          ok: false,
          reverted: false,
          detail:
              'lock conflict on $f (held by $holder) — the move is atomic '
              'and claimed no bytes',
          failureClass: 'lock_conflict',
        );
      }
      claimed.add(f);
    }

    // Capture pre-patch bytes (in-memory revert; no git) and pre-patch
    // verify state (FAILURE ATTRIBUTION, R7b): an edit move may only be
    // auto-reverted for failures it CAUSED. A workspace whose suite is
    // already red (the failing suite IS the task spec) must not revert
    // every intermediate move — the goal loop grades the end state.
    // R7c: the HOST approver gates the move BEFORE any byte lands
    // (deny-by-default — no approver wired means the caller chose
    // apply-mode; a wired approver that refuses blocks the move).
    final approver = _approver;
    if (approver != null && !await approver(plan)) {
      for (final f in files) {
        locks.release(f, owner);
      }
      return SpanEditOutcome(
        ok: false,
        reverted: false,
        detail:
            'edit not approved: ${plan.description} — no bytes were '
            'touched',
        failureClass: 'permission_denied',
      );
    }
    final originals = <String, String>{};
    for (final f in files) {
      originals[f] = File(_abs(f)).readAsStringSync();
    }

    // FAILURE ATTRIBUTION (R7b) with a WORLD-CACHED baseline (the ECS
    // discipline): the workspace's verify state is a resource on the world
    // — the post-state of a green move IS the next move's pre-state, so
    // the full-package oracle runs ONCE per session (when unknown), never
    // per move. A workspace whose suite is already red (the failing suite
    // IS the task spec) must not revert every intermediate move — the
    // goal loop grades the end state.
    final baseline = _baselineResource();
    final swAnalyze = Stopwatch();
    final swCheck = Stopwatch();
    int preAnalyzeExit;
    int preCheckExit;
    if (baseline.clean == null) {
      final preAnalyze = await Process.run('dart', [
        'analyze',
      ], workingDirectory: workspace.path);
      preAnalyzeExit = preAnalyze.exitCode;
      preCheckExit = 0;
      final preCheckCmd = resolveWorkspaceCheck(workspace);
      if (preCheckCmd != null) {
        preCheckExit = (await _runCheck(preCheckCmd)).exitCode;
      }
      baseline.clean = preAnalyzeExit == 0 && preCheckExit == 0;
    } else {
      preAnalyzeExit = baseline.clean! ? 0 : 1;
      preCheckExit = baseline.clean! ? 0 : 1;
    }
    final preClean = preAnalyzeExit == 0 && preCheckExit == 0;

    // Validate + splice. All patches or none: any validation failure
    // bounces before the first write.
    try {
      final newContents = <String, String>{};
      for (final f in files) {
        final text = originals[f]!;
        final sf = SourceFile.fromString(text);
        final filePatches = plan.patches.where((p) => p.file == f).toList()
          ..sort((a, b) => a.startLine.compareTo(b.startLine));
        final lineCount = text.split('\n').length;
        // In-range + non-overlap checks (source_span coordinates; the
        // bounce carries the offending FileSpan so failures land in patch
        // coordinates, analyzer-interop style).
        for (final p in filePatches) {
          if (p.startLine < 1 || p.endLine < p.startLine) {
            throw SpanEditBounce(
              'invalid patch range ${p.startLine}..${p.endLine} in $f',
              'host bug — report the move as failed data',
            );
          }
          if (p.endLine > lineCount) {
            final span = sf.span(0, text.length);
            throw SpanEditBounce(
              'patch range ${p.startLine}..${p.endLine} exceeds the '
                  '$lineCount lines of $f — re-run repo_etl refresh '
                  '(file span: ${span.start.toolString})',
              'the tree is stale; refresh then retry',
            );
          }
        }
        for (var i = 1; i < filePatches.length; i++) {
          if (filePatches[i].startLine <= filePatches[i - 1].endLine) {
            final a = filePatches[i - 1];
            throw SpanEditBounce(
              'overlapping patches in $f '
                  '(${a.startLine}..${a.endLine} vs '
                  '${filePatches[i].startLine}..${filePatches[i].endLine}) '
                  '[span ${sf.getOffset(a.startLine - 1)}..'
                  '${a.endLine < lineCount ? sf.getOffset(a.endLine) : text.length}]',
              'host bug — report the move as failed data',
            );
          }
        }
        // Splice bottom-up so line anchors stay valid. Line → offset goes
        // through the SourceFile (the patch currency, ADR 0023 §2).
        var out = text;
        for (final p in filePatches.reversed) {
          final start = sf.getOffset(p.startLine - 1); // 0-based line
          final end = p.endLine >= lineCount
              ? text.length
              : sf.getOffset(p.endLine);
          // ADR 0027 amendment (retire): an EMPTY replacement deletes the
          // line range outright (no blank-line residue) — the materializer
          // prunes, it never leaves skeleton gaps.
          out = out.replaceRange(
            start,
            end,
            p.replacement.isEmpty ? '' : '${p.replacement}\n',
          );
        }
        newContents[f] = out;
      }

      // Write every file (still all-or-nothing: revert below on failure).
      for (final entry in newContents.entries) {
        File(_abs(entry.key)).writeAsStringSync(entry.value);
      }

      // Mechanical verification tier (ADR 0021): the free oracle re-run.
      // SCOPED to the touched files (the blast radius the tree already
      // knows — sub-second) instead of the whole package; the FULL
      // analyzer + workspace convention run at the goal gate (once per
      // turn) and in the once-per-session baseline above.
      swAnalyze.start();
      final analyze = await Process.run('dart', [
        'analyze',
        ...files.map(_abs),
      ], workingDirectory: workspace.path);
      swAnalyze.stop();
      final analyzeExit = analyze.exitCode;
      if (analyzeExit != 0 && preClean) {
        _revert(files, originals);
        baseline.clean = false;
        return SpanEditOutcome(
          ok: false,
          reverted: true,
          detail:
              'dart analyze (scoped to touched files) exit=$analyzeExit '
              'after ${plan.description}; ALL patches reverted\n'
              '${_tail("${analyze.stdout}${analyze.stderr}")}',
          patchesApplied: plan.patches.length,
          filesTouched: files,
          analyzeExit: analyzeExit,
          analyzeMs: swAnalyze.elapsedMilliseconds,
          failureClass: 'analyze_failed',
        );
      }
      final checkCmd = resolveWorkspaceCheck(workspace);
      int? checkExit;
      var checkDetail = 'no workspace convention (analyze only)';
      if (checkCmd != null) {
        swCheck.start();
        final check = await _runCheck(checkCmd);
        swCheck.stop();
        checkExit = check.exitCode;
        checkDetail = '${checkCmd.join(" ")} exit=$checkExit';
        if (checkExit != 0 && preClean) {
          _revert(files, originals);
          baseline.clean = false;
          return SpanEditOutcome(
            ok: false,
            reverted: true,
            detail:
                '$checkDetail after ${plan.description}; ALL patches '
                'reverted\n${_tail("${check.stdout}${check.stderr}")}',
            patchesApplied: plan.patches.length,
            filesTouched: files,
            analyzeExit: analyzeExit,
            checkExit: checkExit,
            analyzeMs: swAnalyze.elapsedMilliseconds,
            checkMs: swCheck.elapsedMilliseconds,
            failureClass: 'workspace_check_failed',
          );
        }
      }
      // The workspace's new state: green → the baseline carries forward
      // (the next move's pre-state costs nothing); red → cached as red so
      // no further move re-pays for the measurement.
      baseline.clean =
          analyzeExit == 0 && (checkExit == null || checkExit == 0);
      // Patches KEPT: any remaining red state pre-dated the move (or was
      // not attributable) — the goal loop grades the end state.
      return SpanEditOutcome(
        ok: true,
        reverted: false,
        detail:
            '${plan.description} — scoped analyze exit=$analyzeExit '
            '(baseline: ${baseline.clean == true ? "clean" : "pre-existing red"}), '
            '$checkDetail; patches kept',
        patchesApplied: plan.patches.length,
        filesTouched: files,
        analyzeExit: analyzeExit,
        checkExit: checkExit,
        analyzeMs: swAnalyze.elapsedMilliseconds,
        checkMs: swCheck.elapsedMilliseconds,
      );
    } on SpanEditBounce catch (b) {
      // Validation failed before/without writes; bytes untouched.
      return SpanEditOutcome(
        ok: false,
        reverted: false,
        detail: b.error,
        failureClass: 'validation',
      );
    } finally {
      for (final f in files) {
        locks.release(f, owner);
      }
    }
  }

  void _revert(List<String> files, Map<String, String> originals) {
    for (final f in files) {
      File(_abs(f)).writeAsStringSync(originals[f]!, flush: true);
    }
  }

  /// The workspace verify baseline as world state (persisted with the
  /// session world; re-derived measurements, cached verdicts).
  SpanVerifyBaseline _baselineResource() {
    try {
      return world.getResource<SpanVerifyBaseline>();
    } on StateError {
      final r = SpanVerifyBaseline();
      world.upsertResource(r);
      world.flush();
      return r;
    }
  }

  Future<ProcessResult> _runCheck(List<String> cmd) async {
    if (!File(
      '${workspace.path}/.dart_tool/package_config.json',
    ).existsSync()) {
      await Process.run('dart', [
        'pub',
        'get',
      ], workingDirectory: workspace.path);
    }
    return Process.run(
      cmd.first,
      cmd.sublist(1),
      workingDirectory: workspace.path,
    );
  }

  /// One move, plan + apply. Bounces surface as the outcome's structured
  /// detail (the tool layer prefers this non-throwing shape).
  Future<SpanEditOutcome> perform({
    String? action,
    String? symbolId,
    String? classSymbolId,
    String? executableId,
    String? name,
    String? returns,
    List<String> params = const [],
    List<Map<String, String?>> opChain = const [],
    Map<String, dynamic> executableParams = const {},
  }) async {
    try {
      final plan = this.plan(
        action: action,
        symbolId: symbolId,
        classSymbolId: classSymbolId,
        executableId: executableId,
        name: name,
        returns: returns,
        params: params,
        opChain: opChain,
        executableParams: executableParams,
      );
      return await apply(plan);
    } on SpanEditBounce catch (b) {
      return SpanEditOutcome(
        ok: false,
        reverted: false,
        detail: b.error,
        failureClass: 'bounce${b.fence == null ? "" : ":${b.fence}"}',
      );
    }
  }

  // -------------------------------------------------------------------------
  // Source parsing helpers (structural, dart-formatted scope — the same
  // contract as the scanner; the analyzer is the oracle downstream)
  // -------------------------------------------------------------------------

  _MemberSite _memberSite(String file, String name, int declLine1) {
    final text = File(_abs(file)).readAsStringSync();
    final lines = text.split('\n');
    final declLine0 = declLine1 - 1;
    if (declLine0 < 0 || declLine0 >= lines.length) {
      throw SpanEditBounce(
        'decl line $declLine1 out of range for $file',
        're-run repo_etl refresh (the tree is stale)',
      );
    }
    final line = lines[declLine0];
    final nameIdx = line.indexOf(name);
    if (nameIdx < 0) {
      throw SpanEditBounce(
        'symbol $name not found on its recorded decl line $declLine1 of '
            '$file',
        're-run repo_etl refresh (the tree is stale)',
      );
    }
    // Multi-line-safe offsets: absolute offset of the decl line start.
    var lineStart = 0;
    for (var i = 0; i < declLine0; i++) {
      lineStart += lines[i].length + 1;
    }
    final parenRel = line.indexOf('(', nameIdx + name.length);
    if (parenRel < 0) {
      throw SpanEditBounce(
        'member $name has no parameter list on its decl line — outside the '
            'v1 span-editor scope',
        'target a brace-bodied method/function with a single-line '
            'signature',
      );
    }
    final parenStart = lineStart + parenRel;
    final parenEnd = _matchParen(text, parenStart);
    if (parenEnd == null) {
      throw SpanEditBounce(
        'unbalanced parameter list of $name in $file',
        'the v1 scanner expects dart-formatted sources',
      );
    }
    // What follows the parameter list decides the body shape.
    var cursor = parenEnd + 1;
    while (cursor < text.length &&
        (text[cursor] == ' ' ||
            text[cursor] == '\n' ||
            text[cursor] == '\t' ||
            text[cursor] == '\r')) {
      cursor++;
    }
    if (cursor >= text.length ||
        (text[cursor] != '{' && text[cursor] != '=>' && text[cursor] != ';')) {
      throw SpanEditBounce(
        'member $name: unexpected token after the parameter list',
        'the v1 materializer replaces brace-bodied members only',
        fence: 'expressiveness',
      );
    }
    if (text[cursor] != '{') {
      throw SpanEditBounce(
        'member $name is ${text[cursor] == "=>" ? "expression-bodied" : "abstract/external"} '
        '— the v1 materializer replaces brace-bodied members only',
        text[cursor] == '=>'
            ? 'convert to a brace body first (out of scope for a meaning '
                  'move) or target the brace-bodied variant'
            : 'abstract/external members have no body to replace',
        fence: 'expressiveness',
      );
    }
    final openOffset = cursor;
    final closeOffset = _matchBraceText(text, openOffset);
    if (closeOffset == null) {
      throw SpanEditBounce(
        'unbalanced body braces of $name in $file',
        'the v1 scanner expects dart-formatted sources',
      );
    }
    // Param names from the paren text.
    final paramText = text.substring(parenStart + 1, parenEnd);
    final paramNames = <String>{};
    for (final raw in _topLevelCommas(paramText)) {
      var p = raw;
      final eq = p.indexOf('=');
      if (eq >= 0) p = p.substring(0, eq);
      p = p.trim();
      if (p.isEmpty) continue;
      final m = RegExp(r'([A-Za-z_$][\w$]*)\s*(\[\s*\])?\s*$').firstMatch(p);
      if (m != null) paramNames.add(m.group(1)!);
    }
    // Return type: tokens before the name on the decl line (after
    // modifiers/get).
    final prefix = line
        .substring(0, nameIdx)
        .replaceAll(RegExp(r'\b(static|final|const|late|override)\b'), '')
        .trim();
    var returnType = prefix;
    if (prefix.endsWith('get') || prefix.endsWith('set')) {
      returnType = prefix.substring(0, prefix.length - 3).trim();
    }
    // Decl line for the patch: the line the SIGNATURE starts on. For
    // single-line signatures that is declLine0; the body close line comes
    // from the text offsets.
    var closeLine0 = declLine0;
    var acc = lineStart;
    for (var i = declLine0; i < lines.length; i++) {
      if (acc <= closeOffset && closeOffset <= acc + lines[i].length) {
        closeLine0 = i;
        break;
      }
      acc += lines[i].length + 1;
    }
    final declIndent =
        RegExp(r'^\s*').firstMatch(lines[declLine0])?.group(0) ?? '';
    final signatureText = text.substring(
      lineStart,
      openOffset + 1,
    ); // signature + ' {'
    return _MemberSite(
      paramNames: paramNames,
      returnType: returnType,
      declLine0: declLine0,
      closeLine0: closeLine0,
      declIndent: declIndent,
      signatureText: signatureText,
    );
  }

  int? _findClassBodyOpen(List<String> lines, int declLine0, String className) {
    // The class body opens on the first line at/after the decl whose
    // trimmed content ends with '{' (dart-formatted: single-line decl head).
    for (var i = declLine0; i < lines.length && i <= declLine0 + 8; i++) {
      if (lines[i].trimRight().endsWith('{') && lines[i].contains(className)) {
        return i;
      }
      if (i > declLine0 && lines[i].trim() == '{') return i;
    }
    return null;
  }

  /// 0-based line of the '}' matching the '{' that opens on line
  /// [openLine0] (strings respected).
  int? _matchBrace(List<String> lines, int openLine0) {
    final text = lines.join('\n');
    var offset = 0;
    for (var i = 0; i < openLine0; i++) {
      offset += lines[i].length + 1;
    }
    offset += lines[openLine0].indexOf('{');
    final close = _matchBraceText(text, offset);
    if (close == null) return null;
    var acc = 0;
    for (var i = 0; i < lines.length; i++) {
      if (acc <= close && close <= acc + lines[i].length) return i;
      acc += lines[i].length + 1;
    }
    return null;
  }

  int? _matchBraceText(String text, int openOffset) {
    var depth = 0;
    var inStr = false;
    var strCh = '';
    for (var i = openOffset; i < text.length; i++) {
      final c = text[i];
      if (inStr) {
        if (c == r'\') {
          i++;
        } else if (c == strCh) {
          inStr = false;
        }
        continue;
      }
      if (c == "'" || c == '"') {
        inStr = true;
        strCh = c;
        continue;
      }
      if (c == '{') depth++;
      if (c == '}') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return null;
  }

  int? _matchParen(String text, int openOffset) {
    var depth = 0;
    var inStr = false;
    var strCh = '';
    for (var i = openOffset; i < text.length; i++) {
      final c = text[i];
      if (inStr) {
        if (c == r'\') {
          i++;
        } else if (c == strCh) {
          inStr = false;
        }
        continue;
      }
      if (c == "'" || c == '"') {
        inStr = true;
        strCh = c;
        continue;
      }
      if (c == '(') depth++;
      if (c == ')') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return null;
  }

  List<String> _topLevelCommas(String s) {
    final parts = <String>[];
    final buf = StringBuffer();
    var depth = 0;
    var inStr = false;
    var strCh = '';
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (inStr) {
        buf.write(c);
        if (c == r'\' && i + 1 < s.length) {
          buf.write(s[i + 1]);
          i++;
        } else if (c == strCh) {
          inStr = false;
        }
        continue;
      }
      if (c == "'" || c == '"') {
        inStr = true;
        strCh = c;
        buf.write(c);
        continue;
      }
      if ('([{'.contains(c)) depth++;
      if (')]}'.contains(c)) depth--;
      if (c == ',' && depth == 0) {
        parts.add(buf.toString());
        buf.clear();
        continue;
      }
      buf.write(c);
    }
    if (buf.toString().trim().isNotEmpty || parts.isNotEmpty) {
      parts.add(buf.toString());
    }
    return parts;
  }
}

String _tail(String s, {int lines = 12}) {
  final ls = s.trim().split('\n');
  return ls.length <= lines
      ? s.trim()
      : ls.sublist(ls.length - lines).join('\n');
}

/// Parsed member site (pure data; offsets resolved by the caller).
class _MemberSite {
  _MemberSite({
    required this.paramNames,
    required this.returnType,
    required this.declLine0,
    required this.closeLine0,
    required this.declIndent,
    required this.signatureText,
  });
  final Set<String> paramNames;
  final String returnType;
  final int declLine0;
  final int closeLine0;
  final String declIndent;

  /// Signature text INCLUDING the opening ' {' — re-emitted verbatim so
  /// the declared signature survives the body swap byte-for-byte (the
  /// integration fence validates against it before generation).
  final String signatureText;
}

// ---------------------------------------------------------------------------
// The ONE edit tool — same registry discipline as repo_etl/meaning_zoom
// (the core learns no Dart; this lives in the dart_meaning host, ADR 0015)
// ---------------------------------------------------------------------------

/// `edit_symbol`: the meaning profile's single ACT verb for existing code.
/// Every invalid move bounces as structured data with the exact repair
/// move; every applied move is verified by `dart analyze` + the workspace
/// convention and auto-reverted on failure.
ToolDef editSymbolTool(
  World world,
  Directory workspace, {
  FileLockTable? locks,
  Object owner = 'span_editor',
  Set<String> Function()? coverage,
  Future<bool> Function(SpanEditPlan plan)? approver,
  SpanEditMaterializer? materializer,
}) {
  final mat =
      materializer ??
      SpanEditMaterializer(
        world: world,
        workspace: workspace,
        locks: locks,
        owner: owner,
        coverage: coverage,
        approver: approver,
      );
  // R7 production #3 — realize the PROJECT PACK: captured novel
  // resolutions (the ADR 0021 capture loop) are available to every task
  // over this workspace at ZERO authored tokens (the model picks the id,
  // the chain travels with the pack).
  for (final captured in EditPackCapture(workspace).load()) {
    mat.registerPackExecutable(captured.wire, opChain: captured.opChain);
  }
  return ToolDef.encode(
    name: const ToolName('edit_symbol'),
    description:
        'Edit existing code through meaning moves — you never see file '
        'text and never write code tokens. Actions: '
        'replace_member_body {symbolId, opChain} (host compiles the chain '
        'into the member body; the member MUST have suite coverage), '
        'insert_member {symbolId, name, returns, params:[name:type], '
        'opChain} (symbolId is the HOST CLASS to insert into), '
        'remove_member {symbolId} (RETIRE — host prunes member+docs; '
        'retire referencers first or the refs fence bounces), '
        'apply_executable {symbolId, executableId, params} '
        '(pack-fed; built-in: rename_symbol {newName}, multi-file '
        'atomic). ARG SHAPE: '
        'symbolId is a REQUIRED TOP-LEVEL arg (the id from '
        'meaning_zoom/meaning_impact) — never inside executableParams and '
        'never as name; executableParams carries ONLY the executable\'s '
        'own slots (rename_symbol: {newName}; no-param packs: {}). '
        'opChain rows: {label, a?, b?} '
        'over the closed pure vocabulary (load_arg, literal, add, sub, '
        'mul, lt, gt, eq, not, starts_with, list_len, get_item, call, '
        'jump_if_false, return). Every move is verified by dart analyze + '
        'the workspace check and AUTO-REVERTED on failure — a failed move '
        'costs an attempt, so compose carefully from the zoom/impact '
        'data.',
    argsSchema: SchemaBundle(
      root: FM.object(
        'edit_symbol',
        properties: () => [
          FM.prop(
            'action',
            FM.enum_('action', const [
              'replace_member_body',
              'insert_member',
              'apply_executable',
            ]),
          ),
          FM.prop('symbolId', FM.string()),
          // REQUIRED (R7e finding: the on-device model reliably emits the
          // REQUIRED props and drops optional ones — action always landed,
          // symbolId never did). ONE required id: the symbol this move
          // targets — for insert_member that is the HOST CLASS.
          // R7e: a 2-4k model copies a symbol LABEL far more reliably
          // than a raw tree id — the host resolves it mechanically
          // (exact match; ambiguity bounces as data).
          FM.prop('label', FM.string(), optional: true),
          FM.prop('executableId', FM.string(), optional: true),
          FM.prop('name', FM.string(), optional: true),
          FM.prop('returns', FM.string(), optional: true),
          FM.prop('params', FM.array(FM.string()), optional: true),
          FM.prop(
            'opChain',
            FM.array(
              FM.object(
                'op',
                properties: () => [
                  FM.prop('label', FM.string()),
                  FM.prop('a', FM.string(), optional: true),
                  FM.prop('b', FM.string(), optional: true),
                ],
              ),
            ),
            optional: true,
          ),
          FM.prop(
            'executableParams',
            FM.object(
              'executableParams',
              properties: () => [
                FM.prop('newName', FM.string(), optional: true),
                FM.prop('scope', FM.string(), optional: true),
              ],
            ),
            optional: true,
          ),
        ],
      ),
    ),
    execute: (args) async {
      final map = args is Map ? args : const {};
      List<Map<String, String?>> chainOf(dynamic raw) => [
        if (raw is List)
          for (final row in raw)
            if (row is Map)
              {
                'label': row['label'] as String?,
                'a': row['a'] as String?,
                'b': row['b'] as String?,
              },
      ];
      try {
        // R7e findings (REAL AFM runs, 2026-09-04) — surface tuning, never
        // the law:
        // (1) the pack WIRE declares its own slots (e.g. params:
        //     ['symbolId']) — a symbolId inside executableParams is
        //     contract-consistent, so PROMOTE it (normalized: true), never
        //     bounce;
        // (2) a 2-4k model copies a symbol LABEL far more reliably than a
        //     raw tree id — a top-level `label` resolves mechanically
        //     (exact match on symbol labels; ambiguity bounces as data).
        final paramsMap =
            (map['executableParams'] as Map?)?.cast<String, dynamic>() ??
            const {};
        var symbolId = map['symbolId'] as String?;
        var normalized = false;
        final action = map['action'] as String?;
        if ((symbolId == null || symbolId.isEmpty) &&
            paramsMap['symbolId'] is String) {
          symbolId = paramsMap['symbolId'] as String;
          normalized = true; // a declared/bounded slot — canonicalize
        }
        if ((symbolId == null || symbolId.isEmpty) &&
            action != 'insert_member' &&
            map['name'] is String &&
            (map['name'] as String).startsWith('sym_')) {
          return {
            'error':
                "symbolId arrived as 'name' — edit_symbol takes it as "
                'the TOP-LEVEL symbolId arg (or, for pack executables that '
                'declare it, inside executableParams)',
            'bounce': true,
            'failureClass': 'slot_misplaced',
            'repair':
                're-send with {action, symbolId: <TOP-LEVEL id from '
                'meaning_zoom>, executableId, executableParams: {only the '
                "executable's own slots}}",
            'seen': {'name': map['name']},
          };
        }
        if ((symbolId == null || symbolId.isEmpty) && map['label'] is String) {
          // Mechanical label → id resolution: exact match on symbol
          // labels; ambiguity/missing bounce as structured data (never a
          // guess).
          final index = world.getResource<MeaningIndex>();
          final query = map['label'] as String;
          final hits = <String>[];
          for (final entry in index.byId.entries) {
            final node = meaningComponentOf<MeaningNode>(world, entry.value);
            if (node != null && node.kind == 'symbol' && node.label == query) {
              hits.add(entry.key);
            }
          }
          if (hits.length == 1) {
            symbolId = hits.single;
            normalized = true;
          } else {
            return {
              'error': hits.isEmpty
                  ? 'no symbol labeled "$query" in the tree (scan first)'
                  : 'ambiguous label "$query": ${hits.join(", ")}',
              'bounce': true,
              'failureClass': 'label_resolution',
              'repair': hits.isEmpty
                  ? 'repo_etl action scan, then meaning_zoom to confirm the '
                        'label'
                  : 'disambiguate with the TOP-LEVEL symbolId from the cut',
              'hints': hits,
            };
          }
        }
        // ONE required id: the symbol this move targets. For
        // insert_member that is the HOST CLASS (the old classSymbolId —
        // removed from the schema; a required slot beats two optional
        // ones for the on-device model).
        final isInsert = action == 'insert_member';
        final classSymbolId = isInsert ? symbolId : null;
        if (isInsert) symbolId = null;
        final composedChain = chainOf(map['opChain']);
        final plan = mat.plan(
          action: action,
          symbolId: symbolId,
          classSymbolId: classSymbolId,
          executableId: map['executableId'] as String?,
          name: map['name'] as String?,
          returns: map['returns'] as String?,
          params: [
            if (map['params'] is List)
              for (final p in map['params'] as List)
                if (p is String) p,
          ],
          opChain: composedChain,
          executableParams:
              (map['executableParams'] as Map?)?.cast<String, dynamic>() ??
              const {},
        );
        final outcome = await mat.apply(plan);
        // R7 production #3 — the CAPTURE LOOP: a model-composed body
        // replacement that passed all fences AND the free oracles (fully
        // green — a move merely KEPT under a pre-existing red baseline is
        // not a proven resolution) becomes a project-pack entry, so the
        // next task over the same repair class costs ZERO authored
        // tokens. Host-side, mechanical, idempotent.
        String? capturedId;
        if ((map['action'] as String?) == 'replace_member_body' &&
            map['executableId'] == null &&
            outcome.ok &&
            !outcome.reverted &&
            outcome.analyzeExit == 0 &&
            (outcome.checkExit == null || outcome.checkExit == 0)) {
          capturedId = EditPackCapture(workspace).captureVerified(
            action: 'replace_member_body',
            opChain: composedChain,
            description: plan.description,
          );
        }
        return {
          ...outcome.toJson(),
          'move': plan.description,
          'atomic': plan.isAtomic,
          if (normalized) 'normalized': true,
          if (capturedId != null) 'capturedExecutableId': capturedId,
        };
      } on SpanEditBounce catch (b) {
        return b.toJson(); // structured data — the exact repair move
      }
    },
  );
}
