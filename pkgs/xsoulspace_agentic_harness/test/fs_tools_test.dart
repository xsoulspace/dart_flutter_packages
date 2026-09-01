// ignore_for_file: lines_longer_than_80_chars

/// Tests for the fs-tools path jail mitigations (ADR 0009 follow-up):
/// small models hallucinate absolute paths and append trailing slashes;
/// the tools must bounce with TEACHING errors and return jail-relative
/// output so the model can recover without burning rounds.
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
    jail = await Directory.systemTemp.createTemp('fs_tools_test_');
    root = FsToolsRoot(jail.path);
    registry = ToolRegistry();
    fsTools(root).forEach(registry.register);
    final write = registry.get(const ToolName('write'))!;
    await write.execute({'path': 'config.dart', 'content': 'const x = 1;\n'});
  });

  tearDown(() async {
    if (jail.existsSync()) await jail.delete(recursive: true);
  });

  group('list_dir', () {
    test('returns jail-relative entries, directories marked with /', () async {
      Directory('${jail.path}/sub').createSync();
      final out = await registry.get(const ToolName('list_dir'))!.execute({
        'path': '.',
      });
      expect(out, contains('config.dart'));
      expect(out, contains('sub/'));
      expect(out.toString(), isNot(contains(jail.path)));
    });

    test(
      'listing a file path (trailing slash habit) lists its parent',
      () async {
        final out = await registry.get(const ToolName('list_dir'))!.execute({
          'path': 'config.dart/',
        });
        expect(out, contains('config.dart'));
      },
    );
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
      expect(
        root.resolve('$varSpelling/config.dart'),
        startsWith(root.rootPath),
      );
    });

    test('wrapping quotes around the path are stripped', () async {
      final out = await registry.get(const ToolName('read'))!.execute({
        'path': '"config.dart"',
      });
      expect(out, 'const x = 1;\n');
    });
  });

  group('JailWriteGateway — host write policy (P3, revised)', () {
    test(
      'review mode: approved write lands, rejected write does NOT '
      '(jail content matches; model ack is structured)',
      () async {
        final gateway = JailWriteGateway(
          root,
          mode: WriteGateMode.review,
          approver: (w) async => w.relativePath == 'approved.dart',
        );
        root.writeGateway = gateway;
        final write = registry.get(const ToolName('write'))!;

        final okAck = await write.execute({
          'path': 'approved.dart',
          'content': 'const a = 1;\n',
        });
        final rejectAck = await write.execute({
          'path': 'rejected.dart',
          'content': 'const b = 2;\n',
        });

        expect(okAck, 'wrote approved.dart');
        expect(rejectAck, contains('REJECTED'));
        expect(rejectAck, contains('NOT applied'));
        expect(File('${jail.path}/approved.dart').readAsStringSync(),
            'const a = 1;\n');
        expect(File('${jail.path}/rejected.dart').existsSync(), isFalse,
            reason: 'rejected write must never touch the disk');
        expect(gateway.appliedCount, 1);
        expect(gateway.rejectedCount, 1);
      },
    );

    test('review mode: unified diff is minimal and names the file', () async {
      CapturedWrite? capturedWrite;
      final gateway = JailWriteGateway(
        root,
        mode: WriteGateMode.review,
        approver: (w) async {
          capturedWrite = w;
          return true;
        },
      );
      root.writeGateway = gateway;
      final write = registry.get(const ToolName('write'))!;
      // Existing file edit (seeded by setUp).
      await write.execute({
        'path': 'config.dart',
        'content': 'const x = 2;\n',
      });
      final diff = JailWriteGateway.unifiedDiff(capturedWrite!);
      expect(diff, contains('--- a/config.dart'));
      expect(diff, contains('+++ b/config.dart'));
      expect(diff, contains('-const x = 1;'));
      expect(diff, contains('+const x = 2;'));

      // New file diffs against /dev/null.
      await write.execute({
        'path': 'new.dart',
        'content': 'const n = 3;\n',
      });
      final newDiff = JailWriteGateway.unifiedDiff(capturedWrite!);
      expect(newDiff, contains('--- /dev/null'));
      expect(newDiff, contains('+const n = 3;'));
      expect(gateway.renderDiffs(), contains('b/new.dart'));
    },
    );

    test('apply mode (default) is byte-identical to the ungated path',
        () async {
      final gateway = JailWriteGateway(root);
      root.writeGateway = gateway;
      await registry.get(const ToolName('write'))!.execute({
        'path': 'deep/nested.dart',
        'content': 'const d = 1;\n',
      });
      expect(File('${jail.path}/deep/nested.dart').readAsStringSync(),
          'const d = 1;\n');
      expect(gateway.appliedCount, 1);
      // Host materializer writes also flow through (auto-approved).
      gateway.interceptHostWrite('${jail.path}/program.dart', 'void m() {}');
      expect(File('${jail.path}/program.dart').readAsStringSync(),
          'void m() {}');
      expect(gateway.appliedCount, 2);
    },
    );
  });

  group('jailed read-only git visibility (P3)', () {
    test('git_status / git_diff reject outside a repository', () async {
      // `jail` here has no .git (fresh temp dir).
      final status = await registry.get(const ToolName('git_status'))!
          .execute(const {});
      final diff = await registry.get(const ToolName('git_diff'))!
          .execute(const {});
      for (final out in [status, diff]) {
        expect(jsonDecode(out!), containsPair('code', 'not_a_git_repo'));
      }
    },
    );

    test('git_status and git_diff report repo state inside a git repo',
        () async {
      // Fixture repo inside the jail (the jail IS the repo).
      Future<void> git(List<String> args) async {
        final r = await Process.run('git', args, workingDirectory: jail.path);
        if (r.exitCode != 0) {
          fail('git $args failed: ${r.stderr}');
        }
      }
      await git(['init', '-q', '-b', 'main']);
      await git(['config', 'user.email', 'test@example.dev']);
      await git(['config', 'user.name', 'test']);
      File('${jail.path}/tracked.dart').writeAsStringSync('const t = 1;\n');
      await git(['add', '.']);
      await git(['commit', '-q', '-m', 'seed']);
      // Uncommitted change + untracked file.
      File('${jail.path}/tracked.dart').writeAsStringSync('const t = 2;\n');
      File('${jail.path}/untracked.dart').writeAsStringSync('const u = 1;\n');

      final status = await registry
          .get(const ToolName('git_status'))!
          .execute(const {});
      final statusMap = jsonDecode(status!) as Map<String, dynamic>;
      expect(statusMap['ok'], isTrue);
      expect(statusMap['branch'], contains('main'));
      final entries = (statusMap['entries'] as List).cast<String>().join('\n');
      expect(entries, contains('tracked.dart'));
      expect(entries, contains('untracked.dart'));

      final diff =
          await registry.get(const ToolName('git_diff'))!.execute(const {});
      final diffMap = jsonDecode(diff!) as Map<String, dynamic>;
      expect(diffMap['ok'], isTrue);
      expect(diffMap['diff'], contains('-const t = 1;'));
      expect(diffMap['diff'], contains('+const t = 2;'));

      // Path-limited diff only sees that path.
      final limited = await registry.get(const ToolName('git_diff'))!
          .execute({'path': 'tracked.dart'});
      expect(
        (jsonDecode(limited!) as Map<String, dynamic>)['diff'],
        isNot(contains('untracked')),
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
    );
  });
}
