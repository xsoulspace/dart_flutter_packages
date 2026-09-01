// ignore_for_file: avoid_print

/// M1 profile runner — attribution-ranked view of one suite task (or all).
///
/// ```sh
/// dart run bin/harness_profile.dart --task edit_05
/// dart run bin/harness_profile.dart --all
/// ```
///
/// Scripted backend by default: the full loop runs LLM-free, so the
/// attribution plumbing itself is verified in seconds. Real backends run
/// through provider launchers that call [runProfile] with their own
/// handler factory (see example/agents/profile_openrouter.dart).
library;

import 'dart:io';

import 'package:xsoulspace_agentic_harness/benchmark_api.dart';

Future<void> main(List<String> args) async {
  var task = '';
  var tasksDir = 'benchmark/coding_suite/tasks';
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--task':
        task = args[++i];
      case '--tasks-dir':
        tasksDir = args[++i];
      case '--all':
        task = '';
    }
  }
  final tasks = loadTasks(tasksDir)
      .where((t) => task.isEmpty || t.id.contains(task))
      .toList();
  if (tasks.isEmpty) {
    stderr.writeln('no tasks matched "$task"');
    exit(2);
  }

  final report = await runProfile(
    tasks,
    buildHandler: (task) => ScriptedSuiteHandler(taskId: task.id),
  );
  print(report);
}
