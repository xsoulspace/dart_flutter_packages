// ignore_for_file: lines_longer_than_80_chars

/// Meaning-executor experiment (PLAN Stage I / decision D3 evidence gate):
/// the model shapes EXECUTOR LOGIC through meaning moves.
///
/// An intent's behavior is a chain of `op` nodes in the meaning tree:
///
///     intent --impl--> op_1 --then--> op_2 --then--> ... --then--> return
///
/// The model's whole vocabulary is a CLOSED op set ([meaningExecutorOps]) —
/// it adds op nodes and links them with the SAME `act_with_project` tool it
/// already knows; no new tool, no code tokens, no AST. The host owns two pure
/// programs:
///
/// - [interpretMeaningProgram] — the in-process interpreter (drives
///   `intent_call` when no host executor is registered), and
/// - [materializeMeaningProgram] — compiles the tree into the suite's
///   `program.dart` contract (`initialState()` + `runIntent(...)`), which the
///   `intents` checker grades with a REAL `dart` subprocess.
///
/// Semantics are identical by construction (one VM, two hosts); the parity
/// test pins it. This is `Agent = G ∘ F` extended to behavior: the model
/// emits a tiny closed-enum selection over ops; everything after is
/// deterministic and benchmarkable.
///
/// GATE: this arm ships behind `TaskCategory.intentClosure` + the
/// `intent_02_*` task family. It graduates to default only if the Stage-I
/// matrix shows it beats the hand-written-write arm on tokens/task at equal
/// pass rate (failures remain data).
library;

import 'dart:convert';

import 'package:ecsly/ecsly.dart';

import 'intents.dart' show noMeaningExecutorMessage;
import 'meaning_tree.dart';

/// The CLOSED executor vocabulary. Stewardship probe: countable, and every
/// op's behavior is specified below in [interpretMeaningProgram].
const meaningExecutorOps = <String>[
  'load_arg', // push args[a] (whole args map when a empty)
  'load_state', // push state[a]
  'store_state', // state[a] = pop
  'push_state', // state[a] (list) += pop
  'drop_from_state', // state[a] (list) -= pop
  'literal', // push JSON-decoded b (raw string when not JSON)
  'list_len', // top = len(top)
  'starts_with', // pop v; push v.toString().startsWith(b)
  'eq', // pop y, pop x; push x == y
  'not', // pop; push !top
  'jump_if_false', // pop c; if c != true → pc = b
  'jump', // pc = b
  'return', // result = pop (maps as-is, else {"value": v})
  'error', // result = {"error": pop}; halt
];

/// The max VM steps per call — a deterministic bound against looping chains.
const meaningExecutorStepLimit = 1000;

// ---------------------------------------------------------------------------
// Interpreter (in-process host)
// ---------------------------------------------------------------------------

/// Interprets the meaning-program chain of [intent] over [state] with [args].
///
/// Returns the H4 protocol shape: `{'_result': ..., '_state': ...}`.
/// Malformed chains and unknown ops are failures-as-data (error result), not
/// throws.
Map<String, dynamic> interpretMeaningProgram(
  World world,
  String intent,
  Map<String, dynamic> state,
  Map<String, dynamic> args,
) {
  final index = _indexOf(world);
  String? entry;
  final nextOf = <String, String>{};
  final opIds = <String>{};
  for (final (from, relation, to) in index.triples) {
    if (relation == 'impl' && from == intent) entry = to;
    if (relation == 'then') {
      nextOf[from] = to;
      opIds.add(from);
      opIds.add(to);
    }
  }
  if (entry == null) {
    return {
      // B2: the ONE "no executor" dialect — same message the intent_call
      // tool and the materialized program emit.
      '_result': {'error': noMeaningExecutorMessage(intent)},
      '_state': state,
    };
  }
  opIds.add(entry);
  final ops = <String, Map<String, dynamic>>{};
  for (final id in opIds) {
    final entity = index.byId[id];
    if (entity == null) continue;
    final json = _opJson(world, entity);
    json['next'] = nextOf[id];
    ops[id] = json;
  }
  final vm = _MeaningVm(ops);
  return vm.run(entry, state, args);
}

Map<String, dynamic> _opJson(World world, Entity opEntity) {
  final node = meaningComponentOf<MeaningNode>(world, opEntity)!;
  final props =
      meaningComponentOf<MeaningProps>(world, opEntity) ?? const MeaningProps();
  return {
    'id': node.id,
    'op': node.label,
    'a': props.props['a'],
    'b': props.props['b'],
  };
}

MeaningIndex _indexOf(World world) => world.getResource<MeaningIndex>();

/// Whether [intent] carries a meaning-program executor (an `impl` chain).
bool hasMeaningExecutor(World world, String intent) {
  for (final (from, relation, _) in _indexOf(world).triples) {
    if (from == intent && relation == 'impl') return true;
  }
  return false;
}

/// Host chain validation (the heavy lifting stays host-side): walks every
/// intent's `impl` chain exactly like the interpreter would and reports
/// problems as actionable data (op ids included, so the model can repair
/// with `set_prop` / `link`). Called by the materializer so a broken chain
/// is caught at materialize time — not one oracle round-trip later.
List<String> validateMeaningProgram(World world) {
  final problems = <String>[];
  final intents = [
    for (final node in meaningView(world).nodes)
      if (node['kind'] == 'intent') node['id'] as String,
  ];
  for (final intent in intents) {
    final out = interpretMeaningProgram(
      world,
      intent,
      const <String, dynamic>{},
      const <String, dynamic>{},
    );
    final result = out['_result'] as Map? ?? const {};
    final error = result['error'];
    if (error is String) {
      problems.add('$intent: $error');
    } else if (result.isEmpty) {
      problems.add('$intent: chain ended without result');
    }
  }
  return problems;
}

/// Validates macro spec rows BEFORE any state change. Returns an actionable
/// error message, or null when every row is buildable:
/// - `label` must be a non-empty string IN the closed op vocabulary
///   (`meaningExecutorOps`) — a typo like `load` fails here, not at oracle
///   time (AFM run3 finding);
/// - `next` must be a valid row index;
/// - a `b` starting with `#` must resolve to a valid row (a verbatim
///   prompt-echo like `#row` is malformed — AFM run2 finding).
String? chainSpecError(List specs) {
  for (var i = 0; i < specs.length; i++) {
    final s = specs[i];
    if (s is! Map) return 'spec row $i must be an object';
    final label = s['label'];
    if (label is! String || label.isEmpty) {
      return 'spec row $i requires label (string)';
    }
    if (!meaningExecutorOps.contains(label)) {
      return 'spec row $i: op "$label" is outside the closed vocabulary; '
          'valid ops: ${meaningExecutorOps.join(', ')}';
    }
    final next = s['next'];
    if (next is int && (next < 0 || next >= specs.length)) {
      return 'spec row $i: next $next out of range (0..${specs.length - 1})';
    }
    final b = s['b'];
    if (b is String && b.startsWith('#')) {
      final ref = int.tryParse(b.substring(1));
      if (ref == null || ref < 0 || ref >= specs.length) {
        return 'spec row $i: jump target "$b" does not resolve to a spec '
            'row (use "#<row index>", e.g. "#${specs.length - 1}")';
      }
    }
  }
  // Topology gate (AFM run4 finding): chains must TERMINATE. Walk the
  // spec graph (then-edges + jump targets) from row 0; a revisited row on
  // the current path is a cycle, and row 0 must reach a `return` row.
  // Rationale: in this vocabulary a non-terminating loop can't be taught
  // to a 2-4k model (it thrashed on cyclic chains across a whole run), and
  // every intended chain so far is linear+branch. Hard cut until evidence
  // demands loops — the closed vocabulary states this restriction.
  final jumpOf = <int, int>{};
  for (var i = 0; i < specs.length; i++) {
    final s = specs[i] as Map;
    final b = s['b'];
    if (b is String && b.startsWith('#')) {
      jumpOf[i] = int.parse(b.substring(1));
    }
  }
  String? rowLabel(int i) => (specs[i] as Map)['label'] as String?;
  final onPath = <int>{};
  final done = <int>{};
  var reachedReturn = false;
  void walk(int i) {
    if (reachedReturn || i < 0 || i >= specs.length) return;
    if (done.contains(i)) {
      reachedReturn = reachedReturn || rowLabel(i) == 'return';
      return;
    }
    if (!onPath.add(i)) {
      throw _CyclicChainException();
    }
    if (rowLabel(i) == 'return') reachedReturn = true;
    final successors = <int>[];
    final next = (specs[i] as Map)['next'];
    if (next is int) {
      successors.add(next);
    } else if (i + 1 < specs.length) {
      successors.add(i + 1);
    }
    if (jumpOf.containsKey(i)) successors.add(jumpOf[i]!);
    for (final n in successors) {
      walk(n);
    }
    onPath.remove(i);
    done.add(i);
  }

  try {
    walk(0);
  } on _CyclicChainException {
    return 'chain topology: the spec graph has a cycle reachable from row '
        '0 — chains must terminate at a return op. Check next/# targets.';
  }
  if (!reachedReturn) {
    return 'chain topology: no return op is reachable from row 0 — every '
        'chain must end at a return op.';
  }
  return null;
}

class _CyclicChainException implements Exception {}

/// Host program (J1 macros): two-pass build of an op chain from declarative
/// spec rows. Pass 1 spawns the op nodes; pass 2 wires `then` edges —
/// spec[i] → spec[spec[i].next ?? i+1] — and resolves jump targets of the
/// form `b: '#<index>'` to the spawned stable id of spec[<index>].
/// Declarative by design: the model emits a TABLE of rows with row-relative
/// references; the host tracks every id. Returns the assigned ids in spec
/// order, or null if any spec is malformed (nothing spawned on [dryRun]).
List<String>? addChainFromSpecs(
  World world,
  List specs, {
  bool dryRun = false,
}) {
  if (chainSpecError(specs) != null) return null;
  final parsed = <({String label, String? a, String? b, int? next})>[];
  for (final s in specs) {
    if (s is! Map) return null;
    final label = s['label'];
    if (label is! String || label.isEmpty) return null;
    final next = s['next'] is int ? s['next'] as int : null;
    parsed.add((
      label: label,
      a: s['a'] is String ? s['a'] as String : null,
      b: s['b'] is String ? s['b'] as String : null,
      next: next,
    ));
  }
  if (dryRun) return const ['ok'];

  // Pass 1: spawn (b kept raw — jump targets resolve after all ids exist).
  final ids = <String>[];
  final rawB = <String?>[];
  for (final spec in parsed) {
    final entity = addMeaningNode(
      world,
      kind: 'op',
      label: spec.label,
      props: {
        if (spec.a != null) 'a': spec.a,
      },
    );
    final node = meaningComponentOf<MeaningNode>(world, entity);
    if (node == null) return null;
    ids.add(node.id);
    rawB.add(spec.b);
  }

  // Pass 2: write `b` props (resolving `#<index>` jump targets to the
  // spawned stable id), then wire `then` edges.
  for (var i = 0; i < parsed.length; i++) {
    final b = rawB[i];
    if (b != null) {
      var resolved = b;
      if (b.startsWith('#')) {
        final ref = int.tryParse(b.substring(1));
        resolved = (ref != null && ref >= 0 && ref < ids.length) ? ids[ref] : b;
      }
      setMeaningProp(world, id: ids[i], key: 'b', value: resolved);
    }
    final target = parsed[i].next ?? i + 1;
    if (target < ids.length) {
      linkMeaning(world, from: ids[i], relation: 'then', to: ids[target]);
    }
  }
  return ids;
}

// ---------------------------------------------------------------------------
// The VM — ONE implementation of the op semantics
// ---------------------------------------------------------------------------

class _MeaningVm {
  _MeaningVm(this.ops);
  final Map<String, Map<String, dynamic>> ops;

  Map<String, dynamic> run(
    String entry,
    Map<String, dynamic> state,
    Map<String, dynamic> args,
  ) {
    final stack = <dynamic>[];
    final working = jsonDecode(jsonEncode(state)) as Map<String, dynamic>;
    String? pc = entry;
    Map<String, dynamic>? result;
    var steps = 0;
    while (pc != null) {
      if (++steps > meaningExecutorStepLimit) {
        result = {'error': 'step limit exceeded'};
        break;
      }
      final op = ops[pc];
      if (op == null) {
        result = {'error': 'unknown op: $pc'};
        break;
      }
      final kind = op['op'] as String?;
      final a = op['a'];
      final b = op['b'];
      var next = op['next'] as String?;
      if (!meaningExecutorOps.contains(kind)) {
        result = {'error': 'op outside closed vocabulary: $kind'};
        break;
      }
      switch (kind) {
        case 'load_arg':
          stack.add(a == null || '$a'.isEmpty ? args : args['$a']);
        case 'load_state':
          stack.add(working['$a']);
        case 'store_state':
          working['$a'] = stack.isEmpty ? null : stack.removeLast();
        case 'push_state':
          final key = '$a';
          final list = (working[key] ?? <dynamic>[]) as List;
          list.add(stack.isEmpty ? null : stack.removeLast());
          working[key] = list;
        case 'drop_from_state':
          final key = '$a';
          final list = (working[key] ?? <dynamic>[]) as List;
          list.remove(stack.isEmpty ? null : stack.removeLast());
          working[key] = list;
        case 'literal':
          stack.add(_jsonish(b));
        case 'list_len':
          final top = stack.isEmpty ? null : stack.removeLast();
          stack.add(top is List ? top.length : 0);
        case 'starts_with':
          if (b == null) {
            result = {'error': 'starts_with without prefix (op $pc)'};
            break;
          }
          final v = stack.isEmpty ? null : stack.removeLast();
          stack.add('${v ?? ''}'.startsWith('$b'));
        case 'eq':
          final y = stack.isEmpty ? null : stack.removeLast();
          final x = stack.isEmpty ? null : stack.removeLast();
          stack.add(x == y);
        case 'not':
          final top = stack.isEmpty ? null : stack.removeLast();
          stack.add(top != true);
        case 'jump_if_false':
          if (b == null) {
            result = {'error': 'jump_if_false without target (op $pc)'};
            break;
          }
          final cond = stack.isEmpty ? null : stack.removeLast();
          if (cond != true) next = '$b';
        case 'jump':
          if (b == null) {
            result = {'error': 'jump without target (op $pc)'};
            break;
          }
          next = '$b';
        case 'return':
          if (stack.isEmpty) {
            result = {
              'error': 'return without value (op $pc): the chain reached the '
                  'return op with an empty stack — push a literal (or the '
                  'value to return) BEFORE the return op',
            };
            break;
          }
          final top = stack.removeLast();
          result = top is Map ? top.cast<String, dynamic>() : {'value': top};
        case 'error':
          final top = stack.isEmpty ? null : stack.removeLast();
          result = {'error': '${top ?? 'error'}'};
      }
      if (result != null) break;
      pc = next;
    }
    result ??= {'error': 'chain ended without return'};
    return {'_result': result, '_state': working};
  }
}

/// Decodes JSON when [v] looks like JSON; otherwise the raw string.
dynamic _jsonish(v) {
  final s = '$v';
  if (s.startsWith('{') || s.startsWith('[')) {
    try {
      return jsonDecode(s);
    } on FormatException {
      return s;
    }
  }
  return v;
}

// ---------------------------------------------------------------------------
// Materializer (host program): meaning tree → real Dart (the suite contract)
// ---------------------------------------------------------------------------

/// Compiles every intent's op chain into the suite's `program.dart`
/// contract. The ops table travels as JSON; the VM below is fixed
/// boilerplate with semantics identical to [_MeaningVm] (pinned by the
/// parity test).
String materializeMeaningProgram(World world) {
  final index = _indexOf(world);
  final ops = <Map<String, dynamic>>[];
  final impl = <String, String>{};
  // intent → entry (impl edges); op → next (then edges)
  final nextOf = <String, String>{};
  for (final (from, relation, to) in index.triples) {
    if (relation == 'impl') impl[from] = to;
    if (relation == 'then') nextOf[from] = to;
  }
  for (final entry in index.byId.entries) {
    final node = meaningComponentOf<MeaningNode>(world, entry.value);
    if (node == null || node.kind != 'op') continue;
    final props =
        meaningComponentOf<MeaningProps>(world, entry.value) ??
        const MeaningProps();
    ops.add({
      'id': node.id,
      'op': node.label,
      'a': props.props['a'],
      'b': props.props['b'],
      'next': nextOf[node.id],
    });
  }
  final program = jsonEncode({'ops': ops, 'impl': impl});
  return _meaningProgramDartTemplate(program);
}

const _meaningProgramTemplateSrc = r'''
// GENERATED by xsoulspace_agentic_harness meaning-executor materializer.
// The ops table below IS the meaning tree materialized; the VM below is a
// FAITHFUL TRANSCRIPTION of the in-process interpreter (same op guards, same
// '$a' string coercions, same error shapes) — pinned by the parity test in
// test/meaning_program_test.dart. Contract: initialState() +
// runIntent(name, state, args) — the suite 'intents' checker protocol.
import 'dart:convert';

const String _programJson = r"""__PROGRAM_JSON__""";

Map<String, dynamic> initialState() => <String, dynamic>{};

Map<String, dynamic> runIntent(
  String name,
  Map<String, dynamic> state,
  Map<String, dynamic> args,
) {
  final program = jsonDecode(_programJson) as Map;
  final impl = (program['impl'] as Map).cast<String, dynamic>();
  final entry = impl[name];
  if (entry == null) {
    // B2: canonical message, INLINED (generated program has no harness
    // import) — parity with the interpreter is pinned by the parity test.
    return {
      '_result': {
        'error': 'no meaning executor for intent: ' +
            name +
            ' — every intent needs an executor. '
                're-send intent_define (action define) with specs',
      },
      '_state': state,
    };
  }
  try {
    return _runProgram(program, entry, state, args);
  } catch (e) {
    // Errors are data: same failure shape as the in-process interpreter.
    return {'_result': {'error': e.toString()}, '_state': state};
  }
}

dynamic _jsonish(dynamic v) {
  final s = v.toString();
  if (s.startsWith('{') || s.startsWith('[')) {
    try {
      return jsonDecode(s);
    } on FormatException {
      return s;
    }
  }
  return v;
}

Map<String, dynamic> _runProgram(
  Map program,
  String entry,
  Map<String, dynamic> state,
  Map<String, dynamic> args,
) {
  final ops = <String, Map<String, dynamic>>{
    for (final o in (program['ops'] as List).cast<Map>())
      o['id'] as String: o.cast<String, dynamic>(),
  };
  final stack = <dynamic>[];
  final working = jsonDecode(jsonEncode(state)) as Map<String, dynamic>;
  String? pc = entry;
  Map<String, dynamic>? result;
  var steps = 0;
  while (pc != null) {
    if (++steps > 1000) {
      result = {'error': 'step limit exceeded'};
      break;
    }
    final op = ops[pc];
    if (op == null) {
      result = {'error': 'unknown op: $pc'};
      break;
    }
    final kind = op['op'] as String?;
    final a = op['a'];
    final b = op['b'];
    var next = op['next'] as String?;
    switch (kind) {
      case 'load_arg':
        stack.add(a == null || '$a'.isEmpty ? args : args['$a']);
        break;
      case 'load_state':
        stack.add(working['$a']);
        break;
      case 'store_state':
        working['$a'] = stack.isEmpty ? null : stack.removeLast();
        break;
      case 'push_state':
        final key = '$a';
        final list = (working[key] ?? <dynamic>[]) as List;
        list.add(stack.isEmpty ? null : stack.removeLast());
        working[key] = list;
        break;
      case 'drop_from_state':
        final key = '$a';
        final list = (working[key] ?? <dynamic>[]) as List;
        list.remove(stack.isEmpty ? null : stack.removeLast());
        working[key] = list;
        break;
      case 'literal':
        stack.add(_jsonish(b));
        break;
      case 'list_len':
        final top = stack.isEmpty ? null : stack.removeLast();
        stack.add(top is List ? top.length : 0);
        break;
      case 'starts_with':
        if (b == null) {
          result = {'error': 'starts_with without prefix (op $pc)'};
          break;
        }
        final v = stack.isEmpty ? null : stack.removeLast();
        stack.add('${v ?? ''}'.startsWith('$b'));
        break;
      case 'eq':
        final y = stack.isEmpty ? null : stack.removeLast();
        final x = stack.isEmpty ? null : stack.removeLast();
        stack.add(x == y);
        break;
      case 'not':
        final top = stack.isEmpty ? null : stack.removeLast();
        stack.add(top != true);
        break;
      case 'jump_if_false':
        if (b == null) {
          result = {'error': 'jump_if_false without target (op $pc)'};
          break;
        }
        final cond = stack.isEmpty ? null : stack.removeLast();
        if (cond != true) next = '$b';
        break;
      case 'jump':
        if (b == null) {
          result = {'error': 'jump without target (op $pc)'};
          break;
        }
        next = '$b';
        break;
      case 'return':
        if (stack.isEmpty) {
          result = {
            'error': 'return without value (op ' +
                pc! +
                '): the chain reached the return op with an empty stack '
                '- push a literal (or the value to return) BEFORE the '
                'return op',
          };
          break;
        }
        final top = stack.removeLast();
        result =
            top is Map ? top.cast<String, dynamic>() : {'value': top};
        break;
      case 'error':
        final top = stack.isEmpty ? null : stack.removeLast();
        result = {'error': '${top ?? 'error'}'};
        break;
      default:
        result = {'error': 'op outside closed vocabulary: $kind'};
    }
    if (result != null) break;
    pc = next;
  }
  if (result == null && pc == null) {
    result = {'error': 'chain ended without return'};
  }
  return {'_result': result ?? <String, dynamic>{}, '_state': working};
}
''';

String _meaningProgramDartTemplate(String programJson) =>
    _meaningProgramTemplateSrc.replaceFirst('__PROGRAM_JSON__', programJson);
