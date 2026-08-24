// ignore_for_file: lines_longer_than_80_chars

/// Tests for the fs-tools path jail mitigations (ADR 0009 follow-up):
/// small models hallucinate absolute paths and append trailing slashes;
/// the tools must bounce with TEACHING errors and return jail-relative
/// output so the model can recover without burning rounds.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_inference_core/src/agent/tools/fs_tools.dart';
import 'package:xsoulspace_inference_core/src/agent/tools/tool_registry.dart';

void main() {
  late Directory jail;
  late FsToolsRoot root;
  late ToolRegistry registry;

  setUp(() async {
    jail = await Directory.systemTemp.createTemp('fs_tools_test_');
    root = FsToolsRoot(jail.path);
    registry = ToolRegistry();
    fsTools(root).forEach(registry.register);
    final write = registry.get(const ToolName('write'))!;
    await write.execute({'path': 'config.dart', 'content': 'const x = 1;\n'});
  });

  tearDown(() async {
    if (await jail.exists()) await jail.delete(recursive: true);
  });

  group('list_dir', () {
    test('returns jail-relative entries, directories marked with /', () async {
      Directory('${jail.path}/sub').createSync();
      final out =
          await registry.get(const ToolName('list_dir'))!.execute({'path': '.'});
      expect(out, contains('config.dart'));
      expect(out, contains('sub/'));
      expect(out.toString(), isNot(contains(jail.path)));
    });

    test('listing a file path (trailing slash habit) lists its parent',
        () async {
      final out = await registry
          .get(const ToolName('list_dir'))!
          .execute({'path': 'config.dart/'});
      expect(out, contains('config.dart'));
    });
  });

  group('resolve / escapes', () {
    test('true escapes bounce WITH teaching explanation', () async {
      // resolve() throws SYNCHRONOUSLY inside the non-async read closure, so
      // the matcher needs the call-as-closure form to catch sync throws.
      await expectLater(
        () => registry.get(const ToolName('read'))!.execute({
          'path': '/tmp/user_data.json',
        }),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('Path escapes the allowed root'),
              contains('RELATIVE'),
              contains('list_dir'),
            ),
          ),
        ),
      );
    });

    test('absolute path INSIDE the root is accepted', () async {
      final out = await registry.get(const ToolName('read'))!.execute({
        'path': '${jail.path}/config.dart',
      });
      expect(out, 'const x = 1;\n');
    });

    test('symlink-spelled absolute variants of the root are accepted', () {
      // macOS: /var ↔ /private/var are the same directory lexically apart.
      final varSpelling = jail.path.replaceFirst('/private/var/', '/var/');
      if (!varSpelling.startsWith('/var/')) return; // not a macOS layout
      expect(root.resolve('$varSpelling/config.dart'), startsWith(root.rootPath));
    });

    test('wrapping quotes around the path are stripped', () async {
      final out = await registry.get(const ToolName('read'))!.execute({
        'path': '"config.dart"',
      });
      expect(out, 'const x = 1;\n');
    });
  });
}
