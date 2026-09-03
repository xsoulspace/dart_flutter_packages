// ignore_for_file: lines_longer_than_80_chars

/// ETL-out — compile meaning-tree op chains into idiomatic workspace Dart.
///
/// ADR 0022 §2: the materializer spec is data. The VM-replay program
/// (`program.dart`, harness core) stays the interpreter-parity oracle; THIS
/// target is the first application's realization: typed functions in the
/// workspace's own files, graded by the workspace's own `dart test`.
///
/// The compiler is a pure host program over the closed op vocabulary:
/// expression-stack → structured statements. Supported v1: `load_arg,
/// literal, add, sub, mul, lt, gt, eq, not, starts_with, list_len,
/// get_item, call, jump_if_false (structured if/else), return`. Unsupported
/// shapes (state ops, backward jumps, unstructured joins) fail as NAMED
/// problems — never silently. Recovery for richer shapes is pulled by
/// failing tasks, never pushed (ADR 0022 non-goals).
///
/// TODO(code_builder upgrade): when the vocabulary needs classes/generics
/// imports, replace string concatenation with `code_builder` AST generation
/// (https://pub.dev/packages/code_builder). `source_maps` will then map
/// generated offsets back to meaning-tree ops for span-level error reporting.
/// This is a host-side refactor: the model interface stays identical.
library;

import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart'
    show MeaningView, World, meaningView;

import 'test_etl.dart' show DerivedIntent;

/// One compiled artifact: workspace-relative file → generated Dart source.
class DartMaterializerResult {
  DartMaterializerResult({required this.files, required this.problems});

  final Map<String, String> files;

  /// Named, honest failures (unsupported shape for intent X). Never
  /// dropped — the runner reports them as gate failures.
  final List<String> problems;

  bool get ok => problems.isEmpty && files.isNotEmpty;
}

class _OpRow {
  _OpRow(this.id, this.label, this.a, this.b, this.next);
  final String id;
  final String label;
  final String? a;
  final String? b;
  final String? next;
}

class _Unsupported implements Exception {
  _Unsupported(this.reason);
  final String reason;
}

/// Sanitizes an intent name into a legal Dart identifier.
String _safeName(String intent) => intent.replaceAll('.', '__');

/// Renders a literal (JSON-decoded where it parses; quoted string otherwise).
String _renderLiteral(String? b) {
  if (b == null) return 'null';
  final raw = b;
  if (raw == 'true') return 'true';
  if (raw == 'false') return 'false';
  if (raw == 'null') return 'null';
  if (num.tryParse(raw) != null) return raw;
  if (raw.startsWith('{') || raw.startsWith('[')) {
    return raw.replaceAll("'", r"\'");
  }
  return "'${raw.replaceAll(r'\', r'\\').replaceAll("'", r"\'")}'";
}

class _OpRowPtr {
  _OpRowPtr(this.rows, this.entryIdx);
  final List<_OpRow> rows;
  final int entryIdx;
}

/// Collects the intent's chain as an ordered row list. Fall-through order
/// first (following `then` edges); then any jump-target sub-chains not yet
/// collected (worklist — a target placed after the linear fall-through is
/// still part of the program).
_OpRowPtr? _chainRows(
  MeaningView view,
  String entryId,
  Map<String, String> nextOf,
) {
  final byId = {
    for (final n in view.nodes)
      if (n['kind'] == 'op') n['id'] as String: n,
  };
  final rows = <_OpRow>[];
  final positions = <String, int>{};
  void appendChain(String startId) {
    String? cursor = startId;
    while (cursor != null && !positions.containsKey(cursor)) {
      final node = byId[cursor];
      if (node == null) return;
      final props = (node['props'] as Map?) ?? const {};
      positions[cursor] = rows.length;
      rows.add(
        _OpRow(
          cursor,
          node['label'] as String,
          props['a'] as String?,
          props['b'] as String?,
          nextOf[cursor],
        ),
      );
      cursor = nextOf[cursor];
    }
  }

  appendChain(entryId);
  var grew = true;
  while (grew) {
    grew = false;
    for (final r in rows) {
      final target = (r.label == 'jump_if_false' || r.label == 'jump')
          ? r.b
          : null;
      if (target != null && !positions.containsKey(target)) {
        final before = rows.length;
        appendChain(target);
        if (rows.length > before) grew = true;
      }
    }
  }
  final entryIdx = positions[entryId];
  if (entryIdx == null) return null;
  return _OpRowPtr(rows, entryIdx);
}

/// Compiles rows [start] until [stopIdx] (exclusive) or chain end into Dart
/// statements. [stack] carries in-flight expressions. Returns whether the
/// branch TERMINATED in `return` (needed for structured if/else joins).
/// Throws [_Unsupported] on shapes the v1 dart target does not realize.
({String code, bool terminated}) _compile(
  List<_OpRow> rows,
  int start,
  int? stopIdx,
  List<String> stack,
  Set<String> paramNames,
) {
  final out = StringBuffer();
  var i = start;
  outer:
  while (i < rows.length && (stopIdx == null || i < stopIdx)) {
    final r = rows[i];
    switch (r.label) {
      case 'load_arg':
        final name = r.a ?? '';
        if (name.isEmpty || !paramNames.contains(name)) {
          throw _Unsupported(
            'load_arg "$name" is not a declared param of this intent',
          );
        }
        stack.add(name);
      case 'literal':
        stack.add(_renderLiteral(r.b ?? ''));
      case 'add':
      case 'sub':
      case 'mul':
      case 'lt':
      case 'gt':
      case 'eq':
        if (stack.length < 2) throw _Unsupported('${r.label} needs two values');
        final y = stack.removeLast();
        final x = stack.removeLast();
        final op = switch (r.label) {
          'add' => '+',
          'sub' => '-',
          'mul' => '*',
          'lt' => '<',
          'gt' => '>',
          _ => '==',
        };
        stack.add('($x $op $y)');
      case 'not':
        if (stack.isEmpty) throw _Unsupported('not needs a value');
        stack.add('!(${stack.removeLast()})');
      case 'starts_with':
        if (stack.isEmpty) throw _Unsupported('starts_with needs a value');
        stack.add(
          '(${stack.removeLast()}).startsWith(${_renderLiteral(r.b ?? '')})',
        );
      case 'list_len':
        if (stack.isEmpty) throw _Unsupported('list_len needs a value');
        stack.add('(${stack.removeLast()}).length');
      case 'get_item':
        if (stack.length < 2) {
          throw _Unsupported('get_item needs a collection and an index');
        }
        final idx = stack.removeLast();
        final coll = stack.removeLast();
        stack.add('($coll[$idx])');
      case 'call':
        final callee = _safeName(r.a ?? '');
        final keys = (r.b ?? '')
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty);
        final unknown = [
          for (final k in keys)
            if (!paramNames.contains(k)) k,
        ];
        if (unknown.isNotEmpty) {
          throw _Unsupported(
            'call arguments $unknown are not params of this intent (v1 dart '
            'target passes caller params by name)',
          );
        }
        stack.add('$callee(${keys.join(', ')})');
      case 'jump_if_false':
        if (stack.isEmpty) {
          throw _Unsupported('jump_if_false needs a condition on the stack');
        }
        final cond = stack.removeLast();
        final falseIdx = rows.indexWhere((r2) => r2.id == r.b);
        if (falseIdx <= i) {
          throw _Unsupported(
            'backward jump_if_false — v1 dart target supports structured '
            'forward conditionals only',
          );
        }
        // Compile both branches independently (each may run to chain end or
        // terminate in `return`), then find the join.
        final thenResult = _compile(
          rows,
          i + 1,
          null,
          List.of(stack),
          paramNames,
        );
        final elseResult = _compile(
          rows,
          falseIdx,
          null,
          List.of(stack),
          paramNames,
        );
        if (thenResult.terminated && elseResult.terminated) {
          // Both branches return — classic if/else, no continuation.
          out.writeln('if ($cond) {');
          out.write(thenResult.code);
          out.writeln('} else {');
          out.write(elseResult.code);
          out.writeln('}');
          return (code: out.toString(), terminated: true);
        }
        // Exactly one branch continues (the other returned early): emit
        // both compiled bodies; the continuing branch consumed the rest of
        // the chain, so the chain ends after the if/else.
        out.writeln('if ($cond) {');
        out.write(thenResult.code);
        out.writeln('} else {');
        out.write(elseResult.code);
        out.writeln('}');
        return (code: out.toString(), terminated: false);
      case 'jump':
        final targetIdx = rows.indexWhere((r2) => r2.id == r.b);
        if (targetIdx == -1) throw _Unsupported('jump to an unknown target');
        if (targetIdx > i &&
            targetIdx == rows.length - 1 &&
            rows[targetIdx].label == 'return') {
          i = targetIdx; // tail merge onto the trailing return
          continue outer;
        }
        throw _Unsupported(
          'unconditional jump to a non-merge target — v1 dart target '
          'supports structured forward control flow only',
        );
      case 'return':
        if (stack.length != 1) {
          throw _Unsupported(
            'return needs exactly one stack value (got ${stack.length})',
          );
        }
        out.writeln('return ${stack.removeLast()};');
        return (code: out.toString(), terminated: true);
      case 'load_state':
      case 'store_state':
      case 'push_state':
      case 'drop_from_state':
        throw _Unsupported(
          '${r.label}: state ops have no workspace-Dart realization in v1 '
          '(pure-function subset); the VM-replay target still runs them',
        );
      case 'error':
        throw _Unsupported(
          'error op: the workspace-Dart target returns typed results '
          '(VM-replay handles error halts)',
        );
      default:
        throw _Unsupported('op outside the closed vocabulary: ${r.label}');
    }
    i++;
  }
  return (code: out.toString(), terminated: false);
}

/// Compiles every [intents] skeleton's chain from the meaning tree into
/// idiomatic Dart, grouped by target file.
///
/// Law: this is a HOST program over model-composed meaning — the model
/// never writes code tokens (ADR 0019/0022). Chains using shapes this
/// target cannot express produce named [DartMaterializerResult.problems].
DartMaterializerResult materializeWorkspaceDart(
  World world, {
  required List<DerivedIntent> intents,
}) {
  final view = meaningView(world);
  final nextOf = <String, String>{};
  final implOf = <String, String>{};
  for (final e in view.edges) {
    if (e['relation'] == 'then') {
      nextOf[e['from'] as String] = e['to'] as String;
    }
    if (e['relation'] == 'impl') {
      implOf[e['from'] as String] = e['to'] as String;
    }
  }
  final files = <String, List<String>>{};
  final problems = <String>[];
  for (final intent in intents) {
    final entry = implOf[intent.intent];
    if (entry == null) {
      problems.add(
        '${intent.intent}: no impl chain (intent_define with specs required)',
      );
      continue;
    }
    final collected = _chainRows(view, entry, nextOf);
    if (collected == null) {
      problems.add('${intent.intent}: chain has a cycle or a missing op');
      continue;
    }
    try {
      final body = _compile(
        collected.rows,
        collected.entryIdx,
        null,
        <String>[],
        {
          for (final p in intent.params) p.name,
        },
      ).code;
      final params = intent.params
          .map((p) => '${p.type} ${p.name}')
          .join(', ');
      final fn =
          '${intent.returns} ${_safeName(intent.intent)}($params) {\n'
          '$body'
          '}\n';
      files.putIfAbsent(intent.targetFile, () => <String>[]).add(fn);
    } on _Unsupported catch (e) {
      problems.add('${intent.intent}: ${e.reason}');
    }
  }
  return DartMaterializerResult(
    files: {
      for (final e in files.entries) e.key: e.value.join('\n'),
    },
    problems: problems,
  );
}
