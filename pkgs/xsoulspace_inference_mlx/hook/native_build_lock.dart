import 'dart:io';

/// Serializes native builders in separate hook processes on one persistent inode.
/// Never unlink the file: queued builders must keep sharing the same lock.
Future<T> withNativeBuildLock<T>(File file, Future<T> Function() build) async {
  await file.parent.create(recursive: true);
  final handle = await file.open(mode: FileMode.append);
  var locked = false;
  try {
    await handle.lock(FileLock.blockingExclusive);
    locked = true;
    return await build();
  } finally {
    try {
      if (locked) await handle.unlock();
    } finally {
      await handle.close();
    }
  }
}
