// ignore_for_file: lines_longer_than_80_chars

/// Stage N5b — the workspace map: bounded, deterministic, skip-listed, with
/// test→subject links and explicit overflow absences. LLM-free.
library;

import 'dart:io';

import 'package:test/test.dart';

import 'package:xsoulspace_agentic_harness/src/tooling/workspace_map.dart';

void main() {
  late Directory ws;
  setUp(() async => ws = await Directory.systemTemp.createTemp('wsmap'));
  tearDown(() => ws.deleteSync(recursive: true));

  test('renders the tree, skips infra dirs, links test→subject', () {
    Directory('${ws.path}/lib').createSync();
    Directory('${ws.path}/test').createSync();
    Directory('${ws.path}/.dart_tool').createSync();
    File('${ws.path}/pubspec.yaml').writeAsStringSync('name: x\n');
    File('${ws.path}/lib/greet.dart').writeAsStringSync('greet() {}\n');
    File('${ws.path}/test/greet_test.dart').writeAsStringSync('t\n');
    File('${ws.path}/test/orphan_test.dart').writeAsStringSync('t\n');
    File('${ws.path}/.dart_tool/junk.json').writeAsStringSync('{}\n');

    final map = WorkspaceMapProvider(ws.path).map()!;
    expect(map, contains('lib/'));
    expect(map, contains('greet.dart'));
    expect(map, contains('pubspec.yaml'));
    expect(map, isNot(contains('.dart_tool')));
    // Test→subject link, including the honest MISSING case.
    expect(map, contains('links: test/greet_test.dart -> lib/greet.dart'));
    expect(map, contains('test/orphan_test.dart -> MISSING lib/orphan.dart'));
  });

  test('bounded: overflow becomes an explicit absence, never silent', () {
    for (var i = 0; i < 50; i++) {
      File('${ws.path}/file_$i.txt').writeAsStringSync('x');
    }
    final map = WorkspaceMapProvider(ws.path, maxEntries: 10).map()!;
    expect(map, contains('+40 more entries not shown'));
    expect(map.split('\n').where((l) => l.startsWith('file_')), hasLength(10));
  });

  test('caching: unchanged root serves the cached map', () {
    File('${ws.path}/a.txt').writeAsStringSync('a');
    final provider = WorkspaceMapProvider(ws.path);
    final first = provider.map()!;
    File('${ws.path}/a.txt').writeAsStringSync('changed');
    // Within the cache window the map is served from cache.
    expect(provider.map(), first);
  });

  test('missing workspace → null (honest absence)', () {
    expect(
      WorkspaceMapProvider('${ws.path}/nope').map(),
      isNull,
    );
  });
}
