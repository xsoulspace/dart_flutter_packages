import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_storage_filesystem/universal_storage_filesystem.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';

File findUp(String relative) {
  var directory = Directory.current;
  while (true) {
    final file = File('${directory.path}/$relative');
    if (file.existsSync()) return file;
    final parent = directory.parent;
    if (parent.path == directory.path) throw StateError('Missing $relative');
    directory = parent;
  }
}

Future<FileSystemStorageProvider> open(Directory root) async {
  final provider = FileSystemStorageProvider();
  await provider.initWithConfig(
    FileSystemConfig(
      filePathConfig: FilePathConfig.create(
        path: root.path,
        macOSBookmarkData: MacOSBookmark.fromDirectory(root),
      ),
    ),
  );
  return provider;
}

void main() {
  for (final mode in [0x180, 0x1a4]) {
    for (final boundary in FileSystemWriteBoundary.values) {
      test(
        'actual SIGKILL $boundary declared$mode',
        () async {
          final root = Directory.systemTemp.createTempSync('file_state_kill_');
          final workspace = Directory('${root.path}/workspace')..createSync();
          final marker = File('${root.path}/boundary.json');
          final provider = await open(workspace);
          await provider.restoreFileState(
            'owned',
            const StorageFileState(
              content: 'original private bytes',
              mode: 0x180,
            ),
          );
          await provider.dispose();
          final child = await Process.start(Platform.resolvedExecutable, [
            '--packages=${findUp('.dart_tool/package_config.json').path}',
            findUp(
              'pkgs/universal_storage_filesystem/test/support/file_state_boundary_child.dart',
            ).path,
            workspace.path,
            marker.path,
            '$mode',
            boundary.name,
          ]);
          final stdout = child.stdout.transform(utf8.decoder).join();
          final stderr = child.stderr.transform(utf8.decoder).join();
          var exited = false;
          final exit = child.exitCode.then((code) {
            exited = true;
            return code;
          });
          Map<String, dynamic>? observed;
          try {
            final deadline = DateTime.now().add(const Duration(seconds: 30));
            while (!marker.existsSync()) {
              if (exited || DateTime.now().isAfter(deadline)) {
                throw StateError(
                  'Owned child did not pause at boundary: exited=$exited',
                );
              }
              await Future<void>.delayed(const Duration(milliseconds: 20));
            }
            observed =
                jsonDecode(marker.readAsStringSync()) as Map<String, dynamic>;
            expect(observed['pid'], child.pid);
            expect(observed['boundary'], boundary.name);
            final entries = (observed['journals'] as List)
                .cast<String>()
                .expand((journal) => const LineSplitter().convert(journal))
                .where((line) => line.trim().isNotEmpty)
                .map((line) => jsonDecode(line) as Map)
                .toList();
            if (boundary == FileSystemWriteBoundary.stagedPrivateBytes) {
              expect(entries, isEmpty);
            } else {
              expect(entries, hasLength(1));
              expect(entries.single['stage'], 'prepared');
              expect(entries.single['schema_version'], 2);
              expect(entries.single['file_mode'], mode);
              expect(
                entries.single['file_state_profile'],
                storagePosixRwxProfile,
              );
            }

            expect(child.kill(ProcessSignal.sigkill), true);
            final exitCode = await exit.timeout(const Duration(seconds: 10));
            expect(exitCode, isNot(0));
            final output = await stdout;
            final errors = await stderr;
            expect(output, '');
            expect(errors, '');
            final stages = (observed['stages'] as List).cast<Map>();
            if (boundary == FileSystemWriteBoundary.published) {
              expect(observed['target_content'], 'candidate private bytes');
              expect(observed['target_mode'], mode);
              expect(stages, isEmpty);
            } else {
              expect(observed['target_content'], 'original private bytes');
              expect(observed['target_mode'], 0x180);
              expect(stages, hasLength(1));
              expect(stages.single['content'], 'candidate private bytes');
              expect(
                stages.single['mode'],
                boundary == FileSystemWriteBoundary.stagedPrivateBytes
                    ? 0x180
                    : mode,
              );
            }
            final reopened = await open(workspace);
            final state = await reopened.readFileState('owned');
            final recovery = reopened.lastRecoveryReport;
            final stillStaged = Directory(
              '${workspace.path}/.us/tmp',
            ).listSync(recursive: true).whereType<File>().toList();
            if (boundary == FileSystemWriteBoundary.stagedPrivateBytes) {
              expect(state.content, 'original private bytes');
              expect(state.mode, 0x180);
              expect((recovery['totals'] as Map)['replayed_operations'], 0);
              // No prepared authority exists.
              // Preserve the restrictive orphan stage.
              expect(stillStaged, hasLength(1));
              expect(stillStaged.single.statSync().mode & 0xfff, 0x180);
            } else {
              expect(state.content, 'candidate private bytes');
              expect(state.mode, mode);
              expect((recovery['totals'] as Map)['replayed_operations'], 1);
              expect(stillStaged, isEmpty);
            }
            final journals = Directory(
              '${workspace.path}/.us/journal',
            ).listSync().whereType<File>();
            expect(journals.every((file) => file.lengthSync() == 0), true);
            File(
              '/tmp/meaning-filesystem-kill-${boundary.name}-$mode.json',
            ).writeAsStringSync(
              jsonEncode({
                'scope':
                    'actual owned process SIGKILL; not hardware power loss',
                'observed': observed,
                'exit_code': exitCode,
                'stdout': output,
                'stderr': errors,
                'after': {'content': state.content, 'mode': state.mode},
                'recovery': recovery,
                'orphan_stage_retained': stillStaged.isNotEmpty,
              }),
            );
            await reopened.dispose();
          } finally {
            if (!exited) {
              child.kill(ProcessSignal.sigkill);
              await exit;
            }
            root.deleteSync(recursive: true);
          }
        },
        timeout: const Timeout(Duration(seconds: 50)),
        skip: !(Platform.isMacOS || Platform.isLinux),
      );
    }
  }
}
