// ignore_for_file: lines_longer_than_80_chars

/// Tests for the discovery tools of ADR 0014 §2: jailed `grep` (regex
/// content search) and `glob` (path-pattern find). These are the cut for the
/// measured P2 bottleneck — a 2–4k model must *find* in one call instead of a
/// recursive `list_dir`+`read` walk. Deterministic, read-only, token-bounded.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

void main() {
  late Directory jail;
  late FsToolsRoot root;
  late ToolRegistry registry;

  setUp(() async {
    jail = await Directory.systemTemp.createTemp('discovery_tools_test_');
    root = FsToolsRoot(jail.path);
    registry = ToolRegistry();
    fsTools(root).forEach(registry.register);
    // Seed a small workspace.
    for (final (path, body) in [
      ('lib/a.dart', 'string legacyFetch() => "old";\nString modern() => "new";\n'),
      ('lib/b.dart', 'import "a.dart"; final x = legacyFetch();\n'),
      ('test/a_test.dart', '// tests legacyFetch via b\n'),
      ('README.md', '# hello world\n'),
    ]) {
      final f = File('${jail.path}/$path');
      await f.parent.create(recursive: true);
      await f.writeAsString(body);
    }
  });

  tearDown(() async {
    if (jail.existsSync()) await jail.delete(recursive: true);
  });

  Future<List<Object>> grep(String? pattern, {String? path}) async {
    final out = await registry
        .get(const ToolName('grep'))!
        .execute({
          'pattern': ?pattern,
          'path': ?path,
        });
    final map = jsonDecode(out!) as Map<String, dynamic>;
    return (map['results'] as List).cast<Object>();
  }

  group('grep', () {
    test('finds files containing a regex, jail-relative paths', () async {
      final results = await grep('legacyFetch');
      expect(results.length, greaterThanOrEqualTo(2));
      final paths =
          results.map((r) => (r as Map<String, dynamic>)['path'] as String).toList();
      expect(paths, contains('lib/a.dart'));
      expect(paths, contains('lib/b.dart'));
      // Never leaks the absolute jail path.
      expect(jsonEncode(results), isNot(contains(jail.path)));
    });

    test('respects a path scoping argument', () async {
      final results = await grep('fetch', path: 'lib');
      final paths =
          results.map((r) => (r as Map<String, dynamic>)['path'] as String).toList();
      expect(paths.where((p) => p.startsWith('test/')), isEmpty);
    });

    test('respects ignore_case', () async {
      final out = await registry.get(const ToolName('grep'))!.execute({
        'pattern': 'LEGACYFETCH',
        'ignore_case': true,
      });
      final map = jsonDecode(out!) as Map<String, dynamic>;
      expect(map['results'] as List, isNotEmpty);
    });

    test('bad regex is a structured failure, not a throw', () async {
      final out =
          await registry.get(const ToolName('grep'))!.execute({'pattern': '['});
      final map = jsonDecode(out!) as Map<String, dynamic>;
      expect(map['ok'], false);
      expect(map['code'], 'bad_regex');
    });
  });

  group('glob', () {
    Future<List<String>> paths(String pattern) async {
      final out = await registry.get(const ToolName('glob'))!.execute({
        'pattern': pattern,
      });
      final map = jsonDecode(out!) as Map<String, dynamic>;
      return (map['paths'] as List).cast<String>();
    }

    test('** crosses directories (files anywhere)', () async {
      final all = await paths('**/*.dart');
      expect(all, contains('lib/a.dart'));
      expect(all, contains('test/a_test.dart'));
    });

    test('** recurses directories', () async {
      final all = await paths('test/**/*_test.dart');
      expect(all, contains('test/a_test.dart'));
    });

    test('targets a subdir, paths root-relative like other tools', () async {
      final onlyLib = await registry
          .get(const ToolName('glob'))!
          .execute({'pattern': '**/*.dart', 'path': 'lib'});
      final map = jsonDecode(onlyLib!) as Map<String, dynamic>;
      final listed = (map['paths'] as List).cast<String>();
      expect(listed, ['lib/a.dart', 'lib/b.dart']);
    });
  });
}
