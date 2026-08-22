// ignore_for_file: lines_longer_than_80_chars

/// Declarative coding-task spec for the 20-task suite.
///
/// A task is: a prompt for the agent, an optional set of fixture files seeded
/// into the tool jail before the run, and a list of deterministic checkers
/// evaluated against the jail after the run. Checkers are pure data — the same
/// YAML runs identically against this harness, pi, or any other agent.
///
/// Example:
///
/// ```yaml
/// id: edit_01_rename_constant
/// category: file_edit
/// prompt: |
///   In config.dart, rename MAX_USERS to maxUserLimit and update all uses.
/// fixtures:
///   - path: config.dart
///     content: |
///       const MAX_USERS = 10;
/// checkers:
///   - type: not_contains
///     path: config.dart
///     value: MAX_USERS
///   - type: contains
///     path: config.dart
///     value: maxUserLimit
/// ```
library;

import 'dart:io';

import 'package:yaml/yaml.dart';

/// Task categories matching the approved split (6/4/4/3/3).
enum TaskCategory {
  fileEdit('file_edit'),
  multiFileRefactor('multi_file_refactor'),
  searchThenEdit('search_then_edit'),
  toolChain('tool_chain'),
  bugFixWithTest('bug_fix_with_test');

  const TaskCategory(this.yamlName);
  final String yamlName;

  static TaskCategory parse(String name) => values.firstWhere(
    (c) => c.yamlName == name,
    orElse: () => throw ArgumentError('unknown category: $name'),
  );
}

/// A single deterministic post-run assertion on the jail workspace.
class CheckerSpec {
  factory CheckerSpec.fromYaml(YamlMap y) => CheckerSpec(
    type: y['type'] as String,
    path: y['path'] as String?,
    value: y['value'] as String?,
    pattern: y['pattern'] as String?,
    values: (y['values'] as YamlList?)?.cast<String>() ?? const [],
  );

  CheckerSpec({
    required this.type,
    this.path,
    this.value,
    this.pattern,
    this.values = const [],
  });

  /// One of: contains | not_contains | equals | regex | file_exists |
  /// json_valid.
  final String type;
  final String? path;
  final String? value;

  /// Regex source for [type] == 'regex'.
  final String? pattern;

  /// All-must-contain list for multi-value checks.
  final List<String> values;
}

/// A file seeded into the jail before the run.
class FixtureFile {
  FixtureFile({required this.path, required this.content});
  final String path;
  final String content;
}

/// One coding task.
class CodingTask {
  factory CodingTask.fromYaml(String source) {
    final doc = loadYamlNode(source) as YamlMap;
    return CodingTask(
      id: doc['id'] as String,
      category: TaskCategory.parse(doc['category'] as String),
      prompt: doc['prompt'] as String,
      systemPrompt: doc['system_prompt'] as String? ?? defaultSystemPrompt,
      fixtures: ((doc['fixtures'] as YamlList?) ?? [])
          .map(
            (f) => FixtureFile(
              path: (f as YamlMap)['path'] as String,
              content: f['content'] as String? ?? '',
            ),
          )
          .toList(),
      checkers: ((doc['checkers'] as YamlList?) ?? [])
          .map((c) => CheckerSpec.fromYaml(c as YamlMap))
          .toList(),
    );
  }

  CodingTask({
    required this.id,
    required this.category,
    required this.prompt,
    required this.checkers,
    this.fixtures = const [],
    this.systemPrompt = defaultSystemPrompt,
  });

  static const defaultSystemPrompt =
      'You are a coding agent working inside a sandboxed directory. '
      'Use the provided tools to read, write, list, search, and run '
      'commands. Complete the task fully; do not ask questions.';

  final String id;
  final TaskCategory category;
  final String prompt;
  final String systemPrompt;
  final List<FixtureFile> fixtures;
  final List<CheckerSpec> checkers;
}

/// Load every `*.yaml` task in [dir] (non-recursive), sorted by id.
List<CodingTask> loadTasks(String dir) {
  final files =
      Directory(dir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.yaml'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return [for (final f in files) _parseOrThrow(f.path, f.readAsStringSync())];
}

CodingTask _parseOrThrow(String path, String source) {
  try {
    return CodingTask.fromYaml(source);
  } catch (e) {
    throw StateError('bad task file $path: $e');
  }
}
