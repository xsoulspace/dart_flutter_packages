import 'dart:async';
import 'dart:io';

import 'package:universal_storage_filesystem/universal_storage_filesystem.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_live_apply/universal_storage_live_apply.dart';

/// Parent kills this process after a known durable/effect boundary.
Future<void> main(final List<String> args) async {
  final fs = FileSystemStorageProvider();
  await fs.initWithConfig(
    FileSystemConfig(filePathConfig: FilePathConfig({'path': args[1]})),
  );
  final store = LiveApplyJournalStore(storePath: args[2]);
  Future<Never> pause(final String runId) async {
    stdout.writeln(runId);
    await stdout.flush();
    Timer.periodic(const Duration(seconds: 1), (final _) {});
    return Completer<Never>().future;
  }

  if (args[0] == 'lock') {
    await store.withExclusive(() => pause('locked'));
  }
  final tx = await LiveApplyTransaction.begin(fs, store);
  if (args[0] == 'write') {
    await tx.mutate('a', 'candidate', () async {
      await fs.updateFile('a', 'candidate');
      return pause(tx.runId);
    });
  } else {
    await tx.writeFile('a', 'candidate');
    final intercepted = _InverseProvider(fs, () => pause(tx.runId));
    await (await LiveApplyTransaction.reopen(
      intercepted,
      store,
      tx.runId,
    )).rollback();
  }
}

class _InverseProvider extends FileSystemStorageProvider {
  _InverseProvider(this.inner, this.after);
  final FileSystemStorageProvider inner;
  final Future<Never> Function() after;

  @override
  Future<String?> getFile(final String path) => inner.getFile(path);

  @override
  Future<FileOperationResult> updateFile(
    final String path,
    final String content, {
    final String? commitMessage,
  }) async {
    await inner.updateFile(path, content);
    return after();
  }
}
