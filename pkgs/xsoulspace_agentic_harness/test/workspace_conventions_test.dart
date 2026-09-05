// ignore_for_file: lines_longer_than_80_chars

/// Stage M0 / D8 — the default coding oracle is the workspace convention,
/// resolved mechanically (LLM-free). Locks the resolution order and the
/// honest-null contract.
library;

import 'dart:io';

import 'package:test/test.dart';

import 'package:xsoulspace_agentic_harness/src/tooling/workspace_conventions.dart';

void main() {
  late Directory tempDir;

  setUp(() async => tempDir = await Directory.systemTemp.createTemp('wscheck'));
  tearDown(() => tempDir.deleteSync(recursive: true));

  test('Dart package with tests → dart test', () {
    File('${tempDir.path}/pubspec.yaml').writeAsStringSync('name: x\n');
    final testDir = Directory('${tempDir.path}/test/units')
      ..createSync(recursive: true);
    File('${testDir.path}/x_test.dart').writeAsStringSync('void main() {}\n');
    // A stray non-test file must not qualify.
    File('${tempDir.path}/test/readme.md').writeAsStringSync('notes\n');

    expect(resolveWorkspaceCheck(tempDir), const ['dart', 'test']);
  });

  test('Dart package WITHOUT tests → null (R5: analyze passes trivially, '
      'never a done-criterion)', () {
    File('${tempDir.path}/pubspec.yaml').writeAsStringSync('name: x\n');
    // A test/ dir with NO *_test.dart files must not qualify.
    Directory('${tempDir.path}/test').createSync();

    expect(resolveWorkspaceCheck(tempDir), isNull);
  });

  test('ADR 0027 dogfood: a WORKSPACE root pubspec → flutter test (dart '
      'test cannot resolve a workspace containing Flutter packages)', () {
    File('${tempDir.path}/pubspec.yaml').writeAsStringSync(
      'name: _\nworkspace:\n  - pkgs/*\n',
    );
    final testDir = Directory('${tempDir.path}/test')
      ..createSync(recursive: true);
    File('${testDir.path}/root_test.dart').writeAsStringSync('void main() {}\n');

    expect(resolveWorkspaceCheck(tempDir), const ['flutter', 'test']);
  });

  test('bare main.dart (no pubspec) → dart run main.dart', () {
    File('${tempDir.path}/main.dart').writeAsStringSync('void main() {}\n');

    expect(resolveWorkspaceCheck(tempDir), const ['dart', 'run', 'main.dart']);
  });

  test('empty workspace → null (honest failure, never an invented criterion)',
      () {
    expect(resolveWorkspaceCheck(tempDir), isNull);
  });

  test('missing workspace → null', () {
    expect(
      resolveWorkspaceCheck(Directory('${tempDir.path}/does-not-exist')),
      isNull,
    );
  });

  test('splitCheckCommand splits shell-words, no interpolation', () {
    expect(
      splitCheckCommand('  dart   test test/x_test.dart '),
      const ['dart', 'test', 'test/x_test.dart'],
    );
    expect(splitCheckCommand('make  check'), const ['make', 'check']);
  });
}
// wait - appended below properly
