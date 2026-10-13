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
/// HONEST SEMANTIC GAP (recorded, not fixed here): the VM-replay
/// interpreter treats `add` as numeric-only, while this target also
/// composes strings through `add` (PROVEN String + String only — see
/// `_binaryExpr`). String-add chains therefore have no interpreter-parity
/// claim; the generated Dart keeps its own Dart-level semantics.
///
/// When the vocabulary needs classes/generics imports, replace string
/// concatenation with `code_builder` AST generation
/// (https://pub.dev/packages/code_builder). `source_maps` will then map
/// generated offsets back to meaning-tree ops for span-level error reporting.
/// This is a host-side refactor: the model interface stays identical.
library;

import 'dart:convert';

import 'observed_expression.dart';

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

class _OpRowPtr {
  _OpRowPtr(this.rows, this.entryIdx);
  final List<_OpRow> rows;
  final int entryIdx;
}

// ---------------------------------------------------------------------------
// Expression rendering
// ---------------------------------------------------------------------------

/// Static type knowledge the compiler can prove syntactically. Drives the
/// string-composition rendering: numeric vs string `add` must never be
/// confused (VM parity — interpreter `add` is numeric-only; a string literal
/// operand is the only compile-time proof of concatenation).
enum _Type { numeric, boolean, text, unknown }

/// An expression embedded into a string interpolation (`$x` / `${...}`).
class _Embed {
  _Embed(this.text, {required this.simple});
  final String text;

  /// Plain identifier — may render without braces unless the next segment
  /// continues an identifier character (`'$x' + 'b'` → `'${x}b'`).
  final bool simple;
}

/// A rendered expression fragment: source text plus the metadata needed to
/// parenthesize only where the parse actually requires it
/// (`unnecessary_parenthesis`), and to render string composition as
/// interpolation (`prefer_interpolation_to_compose_strings`).
class _Expr {
  _Expr(
    this.text, {
    required this.atomic,
    this.precedence = _precPrimary,
    this.type = _Type.unknown,
    this.simple = false,
    this.stringParts,
    this.fromObservedReturn = false,
  });

  /// Rendered Dart source of the expression (parenthesized exactly where
  /// the grammar requires).
  final String text;
  String? rawLiteral;

  /// Usable under a postfix member/index access or a prefix operator
  /// without parens (identifiers, literals, calls, index/member chains).
  final bool atomic;

  /// Binding power: eq 1 < relational 2 < additive 3 < multiplicative 4 <
  /// unary 6 < primary/postfix 7.
  final int precedence;

  final _Type type;

  /// Plain identifier (safe to interpolate as `$name`).
  final bool simple;

  /// The expression came from a host-resolved observed return
  /// (`load_return`): untyped composition with `add` is rejected instead of
  /// silently emitting runtime-unsafe `+` (see [_binaryExpr]).
  final bool fromObservedReturn;

  /// Present iff [type] is text: the string's segments as escaped literal
  /// chunks ([String]) and embedded expressions ([_Embed]). Keeps folding
  /// literal + interpolated strings idempotent.
  final List<Object>? stringParts;
}

const int _precEq = 1;
const int _precRelational = 2;
const int _precAdditive = 3;
const int _precMultiplicative = 4;
const int _precUnary = 6;
const int _precPrimary = 7;

/// Renders a string composed of [parts] (escaped literal chunks and
/// [_Embed]s) as a single-quoted Dart string literal.
String _renderStringParts(List<Object> parts) {
  final buf = StringBuffer("'");
  for (var i = 0; i < parts.length; i++) {
    final p = parts[i];
    if (p is String) {
      buf.write(p);
      continue;
    }
    final e = p as _Embed;
    var braces = !e.simple;
    if (!braces && i + 1 < parts.length) {
      final next = parts[i + 1];
      if (next is String &&
          next.isNotEmpty &&
          RegExp(r'[A-Za-z0-9_$]').hasMatch(next[0])) {
        braces = true; // `$x` + `bc` would read as `$xbc` — brace it.
      }
    }
    buf.write(braces ? '\${${e.text}}' : '\$${e.text}');
  }
  buf.write("'");
  return buf.toString();
}

_Expr _stringExpr(List<Object> parts) => _Expr(
  _renderStringParts(parts),
  atomic: true,
  type: _Type.text,
  stringParts: parts,
);

/// Renders a literal row (`b`) as an [_Expr] (JSON-decoded where it parses;
/// quoted string otherwise). String literals carry their escaped body so
/// later `add` ops can fold/interpolate instead of composing with `+`.
_Expr _literalExpr(String? b) {
  if (b == null) return _Expr('null', atomic: true);
  final raw = b;
  if (raw == 'true' || raw == 'false') {
    return _Expr(raw, atomic: true, type: _Type.boolean);
  }
  if (raw == 'null') return _Expr('null', atomic: true);
  if (num.tryParse(raw) != null) {
    // A negative literal is unary — it needs parens under postfix access
    // (`(-5).length`, not `-5.length`).
    return _Expr(
      raw,
      atomic: !raw.startsWith('-'),
      precedence: _precUnary,
      type: _Type.numeric,
    );
  }
  if (raw.startsWith('{') || raw.startsWith('[')) {
    return _Expr(raw.replaceAll("'", r"\'"), atomic: true);
  }
  return _stringExpr([_escapeStringBody(raw)]);
}

/// Escapes [raw] for inclusion inside a single-quoted Dart string literal:
/// backslash, quote, `$` (no accidental interpolation), newline and
/// carriage return — the emitted literal round-trips byte-for-byte through
/// the Dart parser.
String _escapeStringBody(String raw) => raw
    .replaceAll(r'\', r'\\')
    .replaceAll("'", r"\'")
    .replaceAll(r'$', r'\$')
    .replaceAll('\n', r'\n')
    .replaceAll('\r', r'\r');

/// Renders a binary op, parenthesizing children exactly where the grammar
/// requires (see [_infix]).
_Expr _binaryExpr(String label, _Expr x, _Expr y) {
  switch (label) {
    case 'concat':
      _Expr textOperand(_Expr value) {
        final raw = value.rawLiteral;
        if (raw != null) {
          if (raw.startsWith('{') || raw.startsWith('[')) {
            try {
              jsonDecode(raw);
              throw _Unsupported('concat requires text operands');
            } on FormatException {
              /* Legacy literal wire value remains text. */
            }
          }
          return _stringExpr([_escapeStringBody(raw)]);
        }
        if (value.type != _Type.text) {
          throw _Unsupported('concat requires proven text operands');
        }
        return value;
      }
      final left = textOperand(x);
      final right = textOperand(y);
      return _stringExpr([
        ...(left.stringParts ?? [_Embed(left.text, simple: left.simple)]),
        ...(right.stringParts ?? [_Embed(right.text, simple: right.simple)]),
      ]);
    case 'add':
      if ((x.fromObservedReturn || y.fromObservedReturn) &&
          (x.type == _Type.text || y.type == _Type.text)) {
        throw _Unsupported(
          'add is numeric for observed transformations; use concat for text',
        );
      }
      // INTERPOLATION/FOLD ONLY ON PROVEN String + String. A string literal
      // operand alone does NOT prove concatenation: a dynamic operand may
      // carry null or a custom-operator object at runtime, and `x + y`
      // then throws where interpolation would silently produce a string.
      // Only operands PROVEN text — string literals, or params whose
      // declared signature type is exactly `String` — compose without `+`.
      // Numeric and boolean operands always keep `+` (their semantics are
      // arithmetic, never rewritten); unknown adds keep `+` verbatim.
      //
      // Honest gap note: the VM-replay interpreter (meaning_program) treats
      // `add` as numeric-only, so string composition through `add` in this
      // target is a PRE-EXISTING divergence from interpreter parity, not
      // something this compiler claims or fixes.
      if (x.type == _Type.text && y.type == _Type.text) {
        final xs = x.stringParts ?? [_Embed(x.text, simple: x.simple)];
        final ys = y.stringParts ?? [_Embed(y.text, simple: y.simple)];
        return _stringExpr([...xs, ...ys]);
      }
      // An OBSERVED-RETURN leaf may compose only when its type is proven:
      // unknown operands would otherwise keep `+` verbatim and fail the
      // workspace lint/verify tier AFTER bytes moved — bounce as named data
      // BEFORE any change instead.
      if ((x.fromObservedReturn || y.fromObservedReturn) &&
          !((x.type == _Type.text && y.type == _Type.text) ||
              (x.type == _Type.numeric && y.type == _Type.numeric))) {
        throw _Unsupported(
          'add on an untyped observed return expression — the host cannot '
          'prove text or numeric composition; return the expression '
          'verbatim, or zoom a member whose return expression is a '
          'typed literal/interpolation/parameter',
        );
      }
      return _infix(x, '+', y, _precAdditive);
    case 'sub':
      return _infix(x, '-', y, _precAdditive);
    case 'mul':
      return _infix(x, '*', y, _precMultiplicative);
    case 'lt':
      return _infix(x, '<', y, _precRelational, leftAssoc: false);
    case 'gt':
      return _infix(x, '>', y, _precRelational, leftAssoc: false);
    case 'eq':
      return _infix(x, '==', y, _precEq, leftAssoc: false);
    default:
      throw _Unsupported('op outside the closed vocabulary: $label');
  }
}

_Expr _infix(
  _Expr x,
  String op,
  _Expr y,
  int precedence, {
  bool leftAssoc = true,
}) {
  // Dart binary ops are left-associative: the right child parens when it
  // binds equally-or-weaker. NON-ASSOCIATIVE ops (equality, relational)
  // additionally parenthesize the LEFT child at equal precedence —
  // `(a == b) == c`, never the invalid `a == b == c`.
  final leftMin = leftAssoc ? precedence : precedence + 1;
  final left = x.precedence < leftMin ? '(${x.text})' : x.text;
  final right = y.precedence <= precedence ? '(${y.text})' : y.text;
  return _Expr(
    '$left $op $right',
    atomic: false,
    precedence: precedence,
    type: switch (op) {
      '==' => _Type.boolean,
      '<' || '>' => _Type.boolean,
      '+' || '-' || '*' =>
        x.type == _Type.numeric && y.type == _Type.numeric
            ? _Type.numeric
            : _Type.unknown,
      _ => _Type.unknown,
    },
  );
}

_Expr _unaryNot(_Expr operand) => _Expr(
  operand.precedence < _precUnary ? '!(${operand.text})' : '!${operand.text}',
  atomic: false,
  precedence: _precUnary,
  type: _Type.boolean,
);

/// Postfix access (`.length`, `.startsWith(..)`, `[..]`): the receiver is
/// parenthesized only when it is not atomic; the result re-enters the
/// expression grammar as an atomic postfix chain.
_Expr _postfix(_Expr receiver, String suffix, {_Type type = _Type.unknown}) =>
    _Expr(
      '${receiver.atomic ? receiver.text : '(${receiver.text})'}$suffix',
      atomic: true,
      type: type,
    );

/// Renders a host-resolved observed return expression as an [_Expr]. The
/// AST-derived type class and precedence keep composition grammar-exact and
/// lint-clean; proven text folds like a literal would.
_Expr _observedExpr(ObservedReturn o) {
  final parts = o.stringParts;
  if (o.kind == 'text') {
    if (parts != null) {
      final embeds = [
        for (final part in parts)
          if (part is String)
            _escapeStringBody(part)
          else
            _Embed((part as ObservedEmbed).text, simple: part.simple),
      ];
      return _Expr(
        _renderStringParts(embeds),
        atomic: true,
        type: _Type.text,
        stringParts: embeds,
        fromObservedReturn: true,
      );
    }
    return _Expr(
      o.text,
      atomic: o.atomic,
      precedence: o.precedence,
      type: _Type.text,
      simple: o.simple,
      fromObservedReturn: true,
    );
  }
  return _Expr(
    o.text,
    atomic: o.atomic,
    precedence: o.precedence,
    type: o.kind == 'numeric' ? _Type.numeric : _Type.unknown,
    fromObservedReturn: true,
  );
}

/// PUBLIC compiler entry (R7b): compiles an op-chain (rows of
/// `{label, a?, b?}` — the same spec rows `intent_define` takes) into Dart
/// statements, for the span-edit materializer's `replace_member_body` /
/// `insert_member` moves. Rows are sequential (`#0..#n`); `jump_if_false` /
/// `jump` targets are `'#<index>'`. Same closed vocabulary, same fences:
/// state ops / backward jumps / undeclared load_args fail as NAMED problems
/// (never silently) — the span editor turns them into structured bounces.
///
/// Generated Dart is lint-clean under the workspace convention:
/// - `expression` is non-null iff the whole body is exactly one `return` —
///   callers preserving single-expression declaration style emit
///   `... => expression;` instead of the block in `code`
///   (prefer_expression_function_bodies);
/// - parenthesization is grammar-exact (unnecessary_parenthesis);
/// - PROVEN String + String `add` renders as interpolation
///   (prefer_interpolation_to_compose_strings): proven means BOTH operands
///   are string literals or [paramTypes] types them exactly `String`.
///   Unknown/numeric/boolean operands keep `+` verbatim — no semantics
///   invented. A dynamic operand's runtime behavior (null or a
///   custom-operator object) is preserved exactly.
({String? code, String? expression, String? problem}) compileOpChainBody(
  List<Map<String, String?>> rows, {
  required Set<String> paramNames,
  Map<String, String> paramTypes = const {},

  /// Host-resolved observed return expression backing `load_return` rows
  /// (see observed_return.dart). Null ⇒ every `load_return` row is a named
  /// compile problem — the op is workspace-only and requires authorization.
  ObservedReturn? observedReturn,
}) {
  final compiled = <_OpRow>[];
  for (var i = 0; i < rows.length; i++) {
    final r = rows[i];
    compiled.add(_OpRow('#$i', r['label'] ?? '', r['a'], r['b'], '#${i + 1}'));
  }
  try {
    if (rows.where((row) => row['label'] == 'load_return').length > 1) {
      throw _Unsupported(
        'load_return may evaluate the observed expression only once',
      );
    }
    final result = _compile(
      compiled,
      0,
      null,
      <_Expr>[],
      paramNames,
      paramTypes,
      observedReturn,
    );
    return (code: result.code, expression: result.singleExpr, problem: null);
  } on _Unsupported catch (e) {
    return (code: null, expression: null, problem: e.reason);
  }
}

/// Collects the intent's chain as an ordered row list. Fall-through order
/// first (following `then` edges); then any jump-target sub-chains not yet
/// collected (worklist — a target placed after the linear fall-through is
/// still part of the program).
_OpRowPtr? _chainRows(
  List<Map<String, dynamic>> nodes,
  String entryId,
  Map<String, String> nextOf,
) {
  final byId = {
    for (final n in nodes)
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
/// branch TERMINATED in `return` (needed for structured if/else joins),
/// and `singleExpr` — the returned value iff the emitted body is exactly
/// one `return` (enables `=> expr;` declaration style). Throws
/// [_Unsupported] on shapes the v1 dart target does not realize.
({String code, bool terminated, String? singleExpr}) _compile(
  List<_OpRow> rows,
  int start,
  int? stopIdx,
  List<_Expr> stack,
  Set<String> paramNames,
  Map<String, String> paramTypes,
  ObservedReturn? observedReturn,
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
        // A param typed exactly `String` in the declared signature is
        // PROVEN text — it may compose via interpolation. Any other or
        // unknown type stays `unknown`: `+` is kept verbatim so dynamic
        // null / custom-operator runtime behavior is never rewritten.
        final type = paramTypes[name];
        stack.add(
          _Expr(
            name,
            atomic: true,
            // `$name` interpolation cannot read `$` inside the identifier.
            simple: !name.contains(r'$'),
            type: type == 'String' ? _Type.text : _Type.unknown,
          ),
        );
      case 'load_return':
        final observed = observedReturn;
        if (observed == null) {
          throw _Unsupported(
            'load_return without a host-resolved observed return expression '
            '(the op is authorized only after the actor observed the '
            'symbol and the materializer resolved it from current source)',
          );
        }
        stack.add(_observedExpr(observed));
      case 'literal':
        stack.add(_literalExpr(r.b ?? '')..rawLiteral = r.b ?? '');
      case 'concat':
      case 'add':
      case 'sub':
      case 'mul':
      case 'lt':
      case 'gt':
      case 'eq':
        if (stack.length < 2) throw _Unsupported('${r.label} needs two values');
        final y = stack.removeLast();
        final x = stack.removeLast();
        stack.add(_binaryExpr(r.label, x, y));
      case 'not':
        if (stack.isEmpty) throw _Unsupported('not needs a value');
        stack.add(_unaryNot(stack.removeLast()));
      case 'starts_with':
        if (stack.isEmpty) throw _Unsupported('starts_with needs a value');
        stack.add(
          _postfix(
            stack.removeLast(),
            ".startsWith(${_literalExpr(r.b ?? '').text})",
            type: _Type.boolean,
          ),
        );
      case 'list_len':
        if (stack.isEmpty) throw _Unsupported('list_len needs a value');
        stack.add(_postfix(stack.removeLast(), '.length', type: _Type.numeric));
      case 'get_item':
        if (stack.length < 2) {
          throw _Unsupported('get_item needs a collection and an index');
        }
        final idx = stack.removeLast();
        final coll = stack.removeLast();
        // The index sits inside `[...]` — no extra parens at any precedence.
        stack.add(
          _Expr(
            '${coll.atomic ? coll.text : '(${coll.text})'}[${idx.text}]',
            atomic: true,
          ),
        );
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
        stack.add(_Expr('$callee(${keys.join(', ')})', atomic: true));
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
          paramTypes,
          observedReturn,
        );
        final elseResult = _compile(
          rows,
          falseIdx,
          null,
          List.of(stack),
          paramNames,
          paramTypes,
          observedReturn,
        );
        if (thenResult.terminated && elseResult.terminated) {
          // Both branches return — classic if/else, no continuation.
          out.writeln('if (${cond.text}) {');
          out.write(thenResult.code);
          out.writeln('} else {');
          out.write(elseResult.code);
          out.writeln('}');
          return (code: out.toString(), terminated: true, singleExpr: null);
        }
        // Exactly one branch continues (the other returned early): emit
        // both compiled bodies; the continuing branch consumed the rest of
        // the chain, so the chain ends after the if/else.
        out.writeln('if (${cond.text}) {');
        out.write(thenResult.code);
        out.writeln('} else {');
        out.write(elseResult.code);
        out.writeln('}');
        return (code: out.toString(), terminated: false, singleExpr: null);
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
        final value = stack.removeLast();
        // A first-statement return makes the whole body a single
        // expression — exposed so callers can keep the declaration's
        // single-expression style (`=> value;`).
        final singleExpr = out.isEmpty ? value.text : null;
        out.writeln('return ${value.text};');
        return (code: out.toString(), terminated: true, singleExpr: singleExpr);
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
  return (code: out.toString(), terminated: false, singleExpr: null);
}

/// Compiles every [intents] skeleton's chain from the meaning tree into
/// idiomatic Dart, grouped by target file.
///
/// Native adapters resolve graph inputs and authorize their use. Chains this
/// target cannot express produce named [DartMaterializerResult.problems].
DartMaterializerResult materializeDartGraph({
  required List<Map<String, dynamic>> nodes,
  required List<Map<String, dynamic>> edges,
  required List<DartMaterializationIntent> intents,
}) {
  final nextOf = <String, String>{};
  final implOf = <String, String>{};
  for (final e in edges) {
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
    final collected = _chainRows(nodes, entry, nextOf);
    if (collected == null) {
      problems.add('${intent.intent}: chain has a cycle or a missing op');
      continue;
    }
    try {
      final body = _compile(
        collected.rows,
        collected.entryIdx,
        null,
        <_Expr>[],
        {for (final p in intent.params) p.name},
        {for (final p in intent.params) p.name: p.type},
        null,
      );
      final params = intent.params.map((p) => '${p.type} ${p.name}').join(', ');
      final name = _safeName(intent.intent);
      // Single-return chains keep the declaration's single-expression
      // style (prefer_expression_function_bodies).
      final fn = body.singleExpr != null
          ? '${intent.returns} $name($params) => ${body.singleExpr};\n'
          : '${intent.returns} $name($params) {\n'
                '${body.code}'
                '}\n';
      files.putIfAbsent(intent.targetFile, () => <String>[]).add(fn);
    } on _Unsupported catch (e) {
      problems.add('${intent.intent}: ${e.reason}');
    }
  }
  return DartMaterializerResult(
    files: {for (final e in files.entries) e.key: e.value.join('\n')},
    problems: problems,
  );
}

/// Explicit callable signature and destination; no suite, world or provider coupling.
class DartMaterializationIntent {
  const DartMaterializationIntent({
    required this.intent,
    required this.targetFile,
    required this.params,
    required this.returns,
  });
  final String intent;
  final String targetFile;
  final List<({String name, String type})> params;
  final String returns;
}
