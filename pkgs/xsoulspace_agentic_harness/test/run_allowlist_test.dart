// ignore_for_file: lines_longer_than_80_chars

/// R7 production #7 follow-up — the run tool's ALLOWLIST (the pi row
/// found `perl -pi -e` editing files through the free-form run tool: a
/// law-violation surface in the meaning profile). The allowlist is an
/// argv PREFIX match; violations fail as named data BEFORE spawning.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart';

void main() {
  late Directory jail;

  setUp(() async {
    jail = await Directory.systemTemp.createTemp('run_allowlist_');
    Directory('${jail.path}/lib').createSync();
  });
  tearDown(() {
    try {
      jail.deleteSync(recursive: true);
    } on Object {
      // best effort
    }
  });

  test('allowlist: convention commands run, file-mutating shells bounce as '
      'named data before spawning', () async {
    // ToolDef.encode wraps the map result into a JSON string (the
    // registry transport is JSON — decode at the boundary).
    final run = runTool(
      FsToolsRoot(jail.path),
      allowlist: const [
        ['dart', 'analyze'],
        ['dart', 'test'],
        ['dart', 'run'],
        ['flutter', 'test'],
      ],
    );
    Future<Map<String, dynamic>> callTool(Object args) async =>
        ((jsonDecode('${await run.execute(args)}') as Map))
            .cast<String, dynamic>();

    // The exact write path the pi row found: blocked.
    final perl = await callTool({
      'command': ['perl', '-pi', '-e', 's/a/b/', 'lib/x.dart'],
    });
    expect(perl['code'], 'command_not_allowed');
    expect(
      '${perl['hint']}',
      contains('edit verbs'),
      reason: 'the bounce names the lawful path for mutation',
    );

    // Prefix, not token: 'dart --version' is NOT 'dart analyze'.
    final version = await callTool({
      'command': ['dart', '--version'],
    });
    expect(version['code'], 'command_not_allowed');

    // The convention commands RUN (no command_not_allowed code).
    final analyze = await callTool({
      'command': ['dart', 'analyze', '.'],
    });
    expect(analyze['code'], isNull, reason: '${analyze['code']}');
    final test = await callTool({
      'command': ['dart', 'test'],
    });
    expect(test['code'], isNull);
  });
}
