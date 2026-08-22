// ignore_for_file: lines_longer_than_80_chars

/// Deterministic scripted handler for suite smoke runs.
///
/// Maps a task id (parsed from the prompt's first line marker) to a canned
/// sequence of tool calls + final text. No LLM involved — this validates the
/// pipeline (jail seeding → harness loop → tool execution → checkers) in CI.
library;

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

/// One scripted step: a tool call to dispatch.
class ScriptedStep {
  ScriptedStep(this.toolName, this.arguments);
  final String toolName;
  final Map<String, dynamic> arguments;
}

/// Canned behavior per task id.
final Map<String, List<ScriptedStep>> scriptedBehaviors = {
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
      'content': 'class User {\n  String name = \'\';\n}\n',
    }),
    ScriptedStep('write', {
      'path': 'order.dart',
      'content': 'class Order {\n  int id = 0;\n}\n',
    }),
    ScriptedStep('write', {
      'path': 'product.dart',
      'content': 'class Product {\n  String sku = \'\';\n}\n',
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
          'import \'math_utils.dart\';\nvoid check() {\n  assert(isEven(2));\n  assert(!isEven(3));\n  assert(isEven(0));\n}\n',
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
        structuralOutput: {'text': 'step $i'},
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
      structuralOutput: {'text': 'done'},
      rawOutput: 'done',
      taskId: request.taskId,
    );
  }
}
