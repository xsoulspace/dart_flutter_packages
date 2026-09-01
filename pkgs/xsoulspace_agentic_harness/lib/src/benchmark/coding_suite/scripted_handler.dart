// ignore_for_file: lines_longer_than_80_chars

/// Deterministic scripted handler for suite smoke runs.
///
/// Maps a task id (parsed from the prompt's first line marker) to a canned
/// sequence of tool calls + final text. No LLM involved — this validates the
/// pipeline (jail seeding → harness loop → tool execution → checkers) in CI.
library;

import '../../../xsoulspace_agentic_harness.dart';

/// One scripted step: a tool call to dispatch.
class ScriptedStep {
  ScriptedStep(this.toolName, this.arguments);
  final String toolName;
  final Map<String, dynamic> arguments;
}

/// Canned behavior per task id.
final Map<String, List<ScriptedStep>> scriptedBehaviors = {
  // Stage I: the MEANING-EXECUTOR arm — the same bookmark behavior, but the
  // scripted model shapes the executor LOGIC through meaning moves (closed op
  // vocabulary via act_with_project); the host materializes program.dart from
  // the tree. Tokens/decision per move vs intent_01's single big write is the
  // I1/I2 matrix column.
  'intent_02_bookmark_meaning_executor': [
    // B1: contract-only `define` no longer exists — every intent needs an
    // executor. The micro-moves arm builds the intent NODES (stable id =
    // the intent name, required by intent_call resolution) and its op
    // chains entirely through act_with_project micro-moves.
    ScriptedStep('act_with_project', {
      'action': 'add', 'kind': 'intent', 'label': 'save_url',
      'id': 'save_url',
    }),
    ScriptedStep('act_with_project', {
      'action': 'add', 'kind': 'intent', 'label': 'list_saved',
      'id': 'list_saved',
    }),
    // save_url chain: load_arg(url) -> starts_with(http) -> jump_if_false
    // -> push_state(bookmarks) -> literal(saved:true) -> return; the false
    // branch is literal(saved:false) -> return (shared return op).
    ScriptedStep('act_with_project', {
      'action': 'add', 'kind': 'op', 'label': 'load_arg',
      'props': {'a': 'url'},
    }),
    ScriptedStep('act_with_project', {
      'action': 'add', 'kind': 'op', 'label': 'starts_with',
      'props': {'b': 'http'},
    }),
    ScriptedStep('act_with_project', {
      'action': 'add', 'kind': 'op', 'label': 'jump_if_false',
      'props': {'b': 'op_6'},
    }),
    ScriptedStep('act_with_project', {
      'action': 'add', 'kind': 'op', 'label': 'push_state',
      'props': {'a': 'bookmarks'},
    }),
    ScriptedStep('act_with_project', {
      'action': 'add', 'kind': 'op', 'label': 'literal',
      'props': {'b': '{"saved": true}'},
    }),
    ScriptedStep('act_with_project', {
      'action': 'add', 'kind': 'op', 'label': 'literal',
      'props': {'b': '{"saved": false, "reason": "invalid url"}'},
    }),
    ScriptedStep('act_with_project', {
      'action': 'add', 'kind': 'op', 'label': 'load_state',
      'props': {'a': 'bookmarks'},
    }),
    ScriptedStep('act_with_project', {
      'action': 'add', 'kind': 'op', 'label': 'list_len',
    }),
    ScriptedStep('act_with_project', {
      'action': 'add', 'kind': 'op', 'label': 'return',
    }),
    ScriptedStep('act_with_project', {
      'action': 'link', 'from': 'save_url', 'relation': 'impl', 'to': 'op_1',
    }),
    ScriptedStep('act_with_project', {
      'action': 'link', 'from': 'list_saved', 'relation': 'impl', 'to': 'op_7',
    }),
    ScriptedStep('act_with_project', {
      'action': 'link', 'from': 'op_1', 'relation': 'then', 'to': 'op_2',
    }),
    ScriptedStep('act_with_project', {
      'action': 'link', 'from': 'op_2', 'relation': 'then', 'to': 'op_3',
    }),
    ScriptedStep('act_with_project', {
      'action': 'link', 'from': 'op_3', 'relation': 'then', 'to': 'op_4',
    }),
    ScriptedStep('act_with_project', {
      'action': 'link', 'from': 'op_4', 'relation': 'then', 'to': 'op_5',
    }),
    ScriptedStep('act_with_project', {
      'action': 'link', 'from': 'op_5', 'relation': 'then', 'to': 'op_9',
    }),
    ScriptedStep('act_with_project', {
      'action': 'link', 'from': 'op_6', 'relation': 'then', 'to': 'op_9',
    }),
    ScriptedStep('act_with_project', {
      'action': 'link', 'from': 'op_7', 'relation': 'then', 'to': 'op_8',
    }),
    ScriptedStep('act_with_project', {
      'action': 'link', 'from': 'op_8', 'relation': 'then', 'to': 'op_9',
    }),
    ScriptedStep('act_with_project', {
      'action': 'materialize',
    }),
    // Self-verification through intent calls (the closed feedback loop).
    ScriptedStep('intent_call', {
      'intent': 'save_url',
      'args': ['url=https://selfcheck.dev'],
    }),
    ScriptedStep('intent_call', {'intent': 'list_saved'}),
  ],
  // J1 macro arm: the SAME bookmark behavior in 5 moves instead of 24 —
  // intent_define (action define, B1) carries an intent's whole logic
  // (branchy chain via declarative spec rows: 'next' + '#row' jump
  // targets); the host does the drop+rebuild+impl-wiring. Moves/task is
  // the J1 matrix column.
  'intent_03_bookmark_macros': [
    ScriptedStep('intent_define', {
      'action': 'define',
      'name': 'save_url',
      'params': ['url:string'],
      'returns': 'bool',
      'specs': [
        {'label': 'load_arg', 'a': 'url'}, // 0
        {'label': 'starts_with', 'b': 'http'}, // 1
        {'label': 'jump_if_false', 'b': '#5'}, // 2 → false branch
        {'label': 'push_state', 'a': 'bookmarks'}, // 3
        {'label': 'literal', 'b': '{"saved": true}', 'next': 6}, // 4
        {'label': 'literal', 'b': '{"saved": false}'}, // 5
        {'label': 'return'}, // 6
      ],
    }),
    ScriptedStep('intent_define', {
      'action': 'define',
      'name': 'list_saved',
      'returns': 'int',
      'specs': [
        {'label': 'load_state', 'a': 'bookmarks'}, // 0
        {'label': 'list_len'}, // 1
        {'label': 'return'}, // 2
      ],
    }),
    ScriptedStep('act_with_project', {'action': 'materialize'}),
    // Self-verification through intent calls (the closed feedback loop).
    ScriptedStep('intent_call', {
      'intent': 'save_url',
      'args': ['url=https://selfcheck.dev'],
    }),
    ScriptedStep('intent_call', {'intent': 'list_saved'}),
  ],
  // Stage H: the materialized intent-closure program (host-written contract
  // initialState() + runIntent(name, state, args) over a JSON state map).
  'intent_01_bookmark_manager': [
    ScriptedStep('write', {
      'path': 'program.dart',
      'content':
          'Map<String, dynamic> initialState() => <String, dynamic>{"bookmarks": <String>[]};\n'
          'Map<String, dynamic> runIntent(String name, Map<String, dynamic> state, Map<String, dynamic> args) {\n'
          '  switch (name) {\n'
          '    case "save_url":\n'
          '      final url = args["url"] as String?;\n'
          '      if (url == null || !url.startsWith("http")) {\n'
          '        return {"saved": false, "reason": "invalid url"};\n'
          '      }\n'
          '      final bookmarks = [...(state["bookmarks"] as List).cast<String>(), url];\n'
          '      return {"_state": <String, dynamic>{"bookmarks": bookmarks}, "_result": <String, dynamic>{"saved": true}};\n'
          '    case "list_saved":\n'
          '      return {"count": (state["bookmarks"] as List).length};\n'
          '    default:\n'
          '      throw ArgumentError("unknown intent: \$name");\n'
          '  }\n'
          '}\n',
    }),
  ],

  'edit_01_rename_constant': [
    ScriptedStep('write', {
      'path': 'config.dart',
      'content':
          'const maxUserLimit = 10;\n\nint capacity() => maxUserLimit * 2;\n',
    }),
  ],
  'edit_02_add_field': [
    ScriptedStep('write', {
      'path': 'user.dart',
      'content':
          'class User {\n  User({required this.name, required this.email});\n  final String name;\n  final String email;\n}\n',
    }),
  ],
  'edit_03_fix_typo_string': [
    ScriptedStep('write', {
      'path': 'messages.dart',
      'content':
          "String welcome() => 'You will receive a confirmation.';\nString goodbye() => 'You will receive nothing further.';\nString hint() => 'Receive it soon.';\n",
    }),
  ],
  'edit_04_delete_function': [
    ScriptedStep('write', {
      'path': 'helpers.dart',
      'content': "String used() => 'keep me';\n",
    }),
  ],
  'edit_05_write_new_file': [
    ScriptedStep('write', {'path': 'version.txt', 'content': '1.2.3'}),
  ],
  'edit_06_json_config_update': [
    ScriptedStep('write', {
      'path': 'settings.json',
      'content':
          '{\n  "host": "localhost",\n  "port": 8080,\n  "retries": 5,\n  "verbose": false\n}\n',
    }),
  ],
  'refactor_01_extract_shared_function': [
    ScriptedStep('write', {
      'path': 'shared.dart',
      'content': "String greet(String name) => 'Hello, \$name!';\n",
    }),
    ScriptedStep('write', {
      'path': 'a.dart',
      'content': "export 'shared.dart' show greet;\nString onlyInA() => 'a';\n",
    }),
    ScriptedStep('write', {
      'path': 'b.dart',
      'content': "export 'shared.dart' show greet;\nString onlyInB() => 'b';\n",
    }),
  ],
  'refactor_02_rename_across_files': [
    ScriptedStep('write', {
      'path': 'store.dart',
      'content': 'class KeyValueStore {\n  Map<String, String> map = {};\n}\n',
    }),
    ScriptedStep('write', {
      'path': 'app.dart',
      'content': "import 'store.dart';\nfinal store = KeyValueStore();\n",
    }),
    ScriptedStep('write', {
      'path': 'tests.dart',
      'content':
          "import 'store.dart';\nvoid check() {\n  final s = KeyValueStore();\n  print(s);\n}\n",
    }),
  ],
  'refactor_03_split_file': [
    ScriptedStep('write', {
      'path': 'user.dart',
      'content': "class User {\n  String name = '';\n}\n",
    }),
    ScriptedStep('write', {
      'path': 'order.dart',
      'content': 'class Order {\n  int id = 0;\n}\n',
    }),
    ScriptedStep('write', {
      'path': 'product.dart',
      'content': "class Product {\n  String sku = '';\n}\n",
    }),
    ScriptedStep('write', {
      'path': 'models.dart',
      'content': '// split done\n',
    }),
  ],
  'refactor_04_consistent_api': [
    ScriptedStep('write', {
      'path': 'calc.dart',
      'content': 'int add(int a, {required int b}) => a + b;\n',
    }),
    ScriptedStep('write', {
      'path': 'client_a.dart',
      'content': "import 'calc.dart';\nfinal x = add(1, b: 2);\n",
    }),
    ScriptedStep('write', {
      'path': 'client_b.dart',
      'content': "import 'calc.dart';\nfinal y = add(3, b: 4);\n",
    }),
  ],
  'search_01_find_and_fix': [
    ScriptedStep('write', {
      'path': 'src/nested/beta.dart',
      'content': '// TODO-fixed: revisit\n',
    }),
  ],
  'search_02_which_file_uses_api': [
    ScriptedStep('write', {
      'path': 'worker.dart',
      'content': "import 'api.dart';\nfinal data = modernFetch();\n",
    }),
  ],
  'search_03_count_and_report': [
    ScriptedStep('write', {'path': 'count.txt', 'content': '2'}),
  ],
  'search_04_dead_code': [
    ScriptedStep('write', {
      'path': 'util.dart',
      'content': "String helpful() => 'used';\n",
    }),
  ],
  'chain_01_read_compute_write': [
    ScriptedStep('write', {'path': 'sum.txt', 'content': '42'}),
  ],
  'chain_02_transform_pipeline': [
    ScriptedStep('write', {
      'path': 'names.json',
      'content': '["alice","bob","carol"]',
    }),
  ],
  'chain_03_multi_step_build': [
    ScriptedStep('write', {
      'path': 'src/lib.dart',
      'content': 'int triple(int x) => x * 3;\n',
    }),
    ScriptedStep('write', {'path': 'README.md', 'content': 'triple(2) = 6\n'}),
  ],
  'bugfix_01_off_by_one': [
    ScriptedStep('write', {
      'path': 'loop.dart',
      'content':
          'int sumTo(int n) {\n  var total = 0;\n  for (var i = 1; i <= n; i++) {\n    total += i;\n  }\n  return total;\n}\n',
    }),
  ],
  'bugfix_02_null_crash': [
    ScriptedStep('write', {
      'path': 'greet.dart',
      'content':
          "String greet(String? name) => name == null ? 'Hi, guest' : 'Hi, \$name';\n",
    }),
  ],
  'bugfix_03_write_failing_test_pass': [
    ScriptedStep('write', {
      'path': 'math_utils.dart',
      'content': 'bool isEven(int x) => x % 2 == 0;\n',
    }),
    ScriptedStep('write', {
      'path': 'test_is_even.dart',
      'content':
          "import 'math_utils.dart';\nvoid check() {\n  assert(isEven(2));\n  assert(!isEven(3));\n  assert(isEven(0));\n}\n",
    }),
  ],
};

/// A [GenerationHandler] that executes the canned steps for the task whose id
/// appears in the prompt, then returns a completion text.
class ScriptedSuiteHandler implements GenerationHandler {
  ScriptedSuiteHandler({required this.taskId, this.onStep});

  /// Task this handler is scripted for.
  final String taskId;

  /// Optional observer for tracing (task id, step index).
  final void Function(String taskId, int stepIndex)? onStep;

  @override
  Future<ActorGenerateResponse> generate(
    World world,
    ActorGenerateRequest request,
  ) async {
    // Task id comes from the runner via the constructor.
    final steps = scriptedBehaviors[taskId];
    if (steps == null) {
      throw StateError('no scripted behavior for task "$taskId"');
    }
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      onStep?.call(taskId, i);
      final response = ActorGenerateResponse(
        actorEntity: request.actorEntity,
        structuredOutput: {'text': 'step $i'},
        rawOutput: 'step $i',
        toolCalls: [
          ToolCall(name: ToolName(step.toolName), arguments: step.arguments),
        ],
        taskId: request.taskId,
      );
      world.events.writer<ActorGenerateResponse>().send(response);
    }
    return ActorGenerateResponse(
      actorEntity: request.actorEntity,
      structuredOutput: {'text': 'done'},
      rawOutput: 'done',
      taskId: request.taskId,
    );
  }
}
