// ignore_for_file: lines_longer_than_80_chars

/// Intent closure (PLAN Stage H, decision D4): the built program's intents
/// are part of the agent's world.
///
/// The model **defines** intents — `intent_define` writes them as meaning
/// nodes (`kind: 'intent'`, stable id = the intent name, props carry the
/// typed params/returns/description). It never writes the implementation:
/// the host materializer owns behavior (the meaning tree IS the program
/// state), and `run` validates the materialized output compiles.
///
/// The model **calls** intents — `intent_call` executes through the
/// [IntentRuntime] where the host registered executors (V1: pure functions
/// over the meaning view, in-process). Results land as structured tool
/// beats, which the projection indexes — the agent observes its own program
/// through typed results, not stdout parsing.
///
/// Later tiers (H5, gated): the same `intent_call` shape over a subprocess
/// JSON protocol, then over mcp_flutter's MCP server for running apps.
/// Transport adapters live in host/provider packages — never in core.
library;

import 'dart:convert';

import 'package:ecsly/ecsly.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart'
    show FM, SchemaBundle, ToolDef, ToolName;

import 'meaning_program.dart'
    show addChainFromSpecs, chainSpecError, hasMeaningExecutor,
        interpretMeaningProgram, meaningExecutorOps, validateMeaningProgram;
import 'meaning_tree.dart' as mt;

// ---------------------------------------------------------------------------
// Intent definitions — meaning nodes with kind 'intent'
// ---------------------------------------------------------------------------

/// The model-facing vocabulary of `intent_define` sub-actions.
const intentDefineActions = <String>['define', 'list', 'redefine_chain'];

/// B2: the ONE repair move for an unimplemented intent — one dialect, three
/// surfaces (`intent_call`, the in-process interpreter, the materialized
/// program) all carry this hint.
const intentExecutorRepairHint =
    're-send intent_define (action define) with specs';

/// The canonical "intent has no executor" message (B2). Starts with the
/// historical phrase so older `contains` diagnostics keep matching.
String noMeaningExecutorMessage(String intent) =>
    'no meaning executor for intent: $intent — every intent needs an '
    'executor. $intentExecutorRepairHint';

/// One intent definition as it travels on the wire / in the cut.
Map<String, dynamic> intentNodeJson(Map<String, dynamic> node) {
  final props = (node['props'] as Map?) ?? const {};
  return {
    'name': node['id'],
    'params': List<String>.from(props['params'] ?? const []),
    'returns': props['returns'] ?? 'void',
    'description': props['description'] ?? '',
  };
}

/// Defines (or re-defines — modify is a re-define) an intent as a meaning
/// node. Stable id = intent name; canonical-style names with dots are fine.
/// Params are `"name:type"` strings (`x:int`) — a tiny model's vocabulary.
/// Returns the intent's model-facing JSON.
Map<String, dynamic> defineIntent(
  World world, {
  required String name,
  List<String> params = const [],
  String returns = 'void',
  String description = '',
}) {
  if (name.isEmpty) throw ArgumentError('intent name must be non-empty');
  final props = <String, dynamic>{
    'params': params,
    'returns': returns,
    'description': description,
  };
  if (mt.hasMeaningNode(world, name)) {
    // Modify = re-define over the same name (a meaning-tree edit).
    for (final entry in props.entries) {
      mt.setMeaningProp(world, id: name, key: entry.key, value: entry.value);
    }
  } else {
    mt.addMeaningNode(
      world,
      kind: 'intent',
      label: name,
      props: props,
      id: name,
    );
  }
  final node = mt.meaningView(world).nodes.firstWhere((n) => n['id'] == name);
  return intentNodeJson(node);
}

/// Lists all defined intents (a budgeted view — intent nodes only).
List<Map<String, dynamic>> listIntents(World world) => [
  for (final node in mt.meaningView(world).nodes)
    if (node['kind'] == 'intent') intentNodeJson(node),
];

// ---------------------------------------------------------------------------
// IntentRuntime — host-registered executors (V1: in-process, pure)
// ---------------------------------------------------------------------------

/// Executes one intent call. [args] are the typed call arguments; returns a
/// JSON-encodable result map. Throws for undefined behavior — the host owns
/// semantics.
typedef IntentExecutor =
    Future<Map<String, dynamic>> Function(
      Map<String, dynamic> args,
      MeaningViewSnapshot program,
    );

/// A stable, serializable view of the program state the executor reads.
/// V1 this IS the meaning tree's feature/intent nodes — the program as data.
class MeaningViewSnapshot {
  MeaningViewSnapshot(this.nodes, this.edges);
  final List<Map<String, dynamic>> nodes;
  final List<Map<String, dynamic>> edges;

  Map<String, dynamic>? nodeById(String id) =>
      nodes.where((n) => n['id'] == id).firstOrNull;

  /// All feature-node values of one prop (e.g. every cell's marker).
  List<dynamic> propValues(String prop, {String kind = 'feature'}) => [
    for (final n in nodes)
      if (n['kind'] == kind && (n['props'] as Map).containsKey(prop))
        (n['props'] as Map)[prop],
  ];
}

/// Where the host registers intent executors. Executable truth stays OUT of
/// the graph (same law as tool closures in [ToolExecutorResource]).
class IntentRuntime extends Resource {
  final Map<String, IntentExecutor> executors = {};

  void register(String name, IntentExecutor executor) =>
      executors[name] = executor;

  bool canCall(String name) => executors.containsKey(name);
}

/// World-persisted state for meaning-program executors: `intent_call` on an
/// intent whose behavior is a meaning-program chain (Stage I experiment)
/// threads this map through [interpretMeaningProgram], so cross-call state
/// accumulates exactly like the `intents` checker's sequential replay.
class IntentCallState extends Resource {
  Map<String, dynamic> state = {};
}

// ---------------------------------------------------------------------------
// Tools — the model's intent moves
// ---------------------------------------------------------------------------

/// `intent_define`: the model names the program's surface (create/modify).
ToolDef intentDefineTool(World world) => ToolDef.encode(
  name: const ToolName('intent_define'),
  description:
      'Define an intent of the program you are building AND its behavior: '
      'ONE move defines the intent (name, typed params "name:type", return '
      'type) AND wires its whole op chain from specs. Sub-actions: define '
      '(REQUIRES specs — labels MUST be from the closed op vocabulary; '
      'replacing an existing chain is atomic); list. An intent WITHOUT '
      'specs has no executor and can never be called.',
  argsSchema: SchemaBundle(
    root: FM.object('intent_define', properties: () => [
      FM.prop('action', FM.enum_('action', intentDefineActions)),
      FM.prop('name', FM.string(), optional: true),
      FM.prop('params', FM.array(FM.string()), optional: true),
      FM.prop('returns', FM.string(), optional: true),
      FM.prop('description', FM.string(), optional: true),
      FM.prop('specs', FM.array(FM.object('spec', properties: () => [
        FM.prop('label', FM.string()),
        FM.prop('a', FM.string(), optional: true),
        FM.prop('b', FM.string(), optional: true),
        FM.prop('next', FM.integer(), optional: true),
      ])), optional: true),
    ]),
  ),
  execute: (args) async {
    final map = args is Map ? args : const {};
    switch (map['action']) {
      case 'list':
        return {'intents': listIntents(world)};
      case 'define':
      case 'redefine_chain': // accepted alias of define (B1 hard cut)
        // B1 (J1.4 blocker): ONE self-executing action. `define` REQUIRES
        // specs and ALWAYS wires the impl edge — the contract-only no-op
        // path that stranded on-device runs is deleted.
        final name = map['name'];
        if (name is! String || name.isEmpty) {
          return {'error': 'define requires name'};
        }
        final specs = map['specs'];
        if (specs is! List || specs.isEmpty) {
          return {
            'ok': false,
            'error': 'define requires specs: every intent needs an executor '
                '(op rows [{label, a?, b?, next?}]); an intent without an '
                'op chain can never be called. $intentExecutorRepairHint.',
            'intent': name,
            'valid_ops': meaningExecutorOps,
            'repair': intentExecutorRepairHint,
          };
        }
        // Shape-validate BEFORE touching state (atomicity: a malformed
        // request must never drop a working chain). Errors carry the closed
        // vocabulary so an invalid op name (e.g. `load`) is fixed in the
        // NEXT move, not discovered at oracle time (AFM run3 finding).
        final specError = chainSpecError(specs);
        if (specError != null) {
          return {'error': specError, 'valid_ops': meaningExecutorOps};
        }
        // Dedup guard (thrash damping): an identical, previously-built
        // chain spec is a cheap no-op — no drop, no rebuild, no churn.
        final normalized = jsonEncode([
          for (final s in specs)
            if (s is Map)
              {
                for (final k in ['label', 'a', 'b', 'next'])
                  if (s[k] != null) k: s[k],
              }
        ]);
        final existingSpec = _chainSpecProp(world, name);
        if (existingSpec == normalized && mt.hasMeaningNode(world, name)) {
          return {
            'ok': true,
            'intent': name,
            'unchanged': true,
            'problems': validateMeaningProgram(world),
          };
        }
        final dropped = mt.hasMeaningNode(world, name)
            ? mt.dropMeaningChain(world, name)
            : 0;
        defineIntent(
          world,
          name: name,
          params: [
            if (map['params'] is List)
              for (final p in map['params'] as List)
                if (p is String) p,
          ],
          returns: map['returns'] is String ? map['returns'] as String : 'void',
          description: map['description'] is String
              ? map['description'] as String
              : '',
        );
        final ids = addChainFromSpecs(world, specs)!;
        mt.linkMeaning(world, from: name, relation: 'impl', to: ids.first);
        mt.setMeaningProp(world, id: name, key: '_chainSpec', value: normalized);
        final problems = validateMeaningProgram(world);
        return {
          'ok': problems.isEmpty,
          'defined': name,
          'ids': ids,
          'dropped': dropped,
          'problems': problems,
        };
      default:
        return {'error': 'unknown action: ${map['action']}'};
    }
  },
);

/// `intent_call`: invoke a defined intent of the built program and observe
/// its typed result. Resolution order:
/// 1. host executor registered in [IntentRuntime] (host owns semantics);
/// 2. a meaning-program `impl` chain in the tree (Stage I experiment — the
///    model shaped the logic through meaning moves; the interpreter is the
///    pure host program; state threads through [IntentCallState]);
/// 3. else a structured failure with the defined set (failures are data).
/// The call + result land as structured beats (tool system).
Future<Map<String, dynamic>> callIntent(
  World world, {
  required String name,
  Map<String, dynamic> args = const {},
}) async {
  final runtime = world.getResource<IntentRuntime>();
  final executor = runtime.executors[name];
  Map<String, dynamic> result;
  if (executor != null) {
    final view = mt.meaningView(world);
    result = await executor(
      args,
      MeaningViewSnapshot(view.nodes, view.edges),
    );
  } else if (hasMeaningExecutor(world, name)) {
    final callState = world.getResource<IntentCallState>();
    final out = interpretMeaningProgram(
      world,
      name,
      callState.state,
      args,
    );
    callState.state =
        (out['_state'] as Map?)?.cast<String, dynamic>() ?? callState.state;
    result = (out['_result'] as Map?)?.cast<String, dynamic>() ?? {};
  } else {
    // B2: ONE honest structured failure — what failed, what exists, and
    // the exact repair move. No separate "not implemented" dialect.
    return {
      'ok': false,
      'error': noMeaningExecutorMessage(name),
      'intent': name,
      'defined': [
        for (final i in listIntents(world)) i['name'],
      ],
      'repair': intentExecutorRepairHint,
    };
  }
  return {'ok': !result.containsKey('error'), 'intent': name, 'result': result};
}

ToolDef intentCallTool(World world) => ToolDef.encode(
  name: const ToolName('intent_call'),
  description:
      'Call an intent of the program you are building and observe its typed '
      'result. Arguments are "key=value" strings (values as text). This is '
      'how you verify behavior — no stdout parsing, no test files.',
  argsSchema: SchemaBundle(
    root: FM.object('intent_call', properties: () => [
      FM.prop('intent', FM.string()),
      FM.prop('args', FM.array(FM.string()), optional: true),
    ]),
  ),
  execute: (args) async {
    final map = args is Map ? args : const {};
    final name = map['intent'];
    if (name is! String || name.isEmpty) {
      return {'error': 'intent_call requires intent name'};
    }
    return callIntent(
      world,
      name: name,
      args: {
        if (map['args'] is List)
          for (final a in map['args'] as List)
            if (a is String && a.contains('='))
              a.substring(0, a.indexOf('=')):
                  a.substring(a.indexOf('=') + 1),
      },
    );
  },
);

/// Reads the stored `_chainSpec` signature from the intent node (dedup key).
String? _chainSpecProp(World world, String name) {
  for (final node in mt.meaningView(world).nodes) {
    if (node['id'] == name && node['kind'] == 'intent') {
      final v = (node['props'] as Map?)?['_chainSpec'];
      return v is String ? v : null;
    }
  }
  return null;
}
