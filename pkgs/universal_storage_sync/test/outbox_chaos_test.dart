import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_storage_filesystem/universal_storage_filesystem.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_sync/universal_storage_sync.dart';

/// Chaos/durability tests for the outbox queue.
///
/// Simulates crash and corruption scenarios and asserts no data loss:
/// - queue file corrupted mid-flight → kernel still boots, data intact
/// - duplicate delivery of the same entry → idempotent handling
/// - queue file deleted entirely → user data unaffected
void main() {
  Future<(StorageKernel, Directory)> buildKernel({
    required final String name,
    SyncQueueStore? queueStore,
  }) async {
    final directory = await Directory.systemTemp.createTemp('chaos_$name');
    final provider = FileSystemStorageProvider();
    await provider.initWithConfig(
      FileSystemConfig(
        filePathConfig: FilePathConfig.create(
          path: directory.path,
          macOSBookmarkData: MacOSBookmark.fromDirectory(directory),
        ),
      ),
    );
    return (
      StorageKernel(
        profile: StorageProfile(
          name: 'chaos_$name',
          namespaces: [
            StorageNamespaceProfile(
              namespace: StorageNamespace.projects,
              policy: StoragePolicy.optimisticSync,
              remoteEngineId: 'unreachable',
            ),
          ],
        ),
        resolver: InMemoryStorageProfileResolver(
          namespaceServices: {
            StorageNamespace.projects: StorageService(provider),
          },
        ),
        queueStore: queueStore,
      ),
      directory,
    );
  }

  group('chaos: corrupted queue file', () {
    test('kernel boots with empty queue; user data intact', () async {
      final (kernel, directory) = await buildKernel(name: 'corrupt');
      try {
        // Seed user data + outbox entries.
        for (var i = 0; i < 5; i++) {
          await kernel.write(
            namespace: StorageNamespace.projects,
            path: 'data/file-$i.json',
            content: '{"i":$i}',
          );
        }
        expect(
          await kernel.outboxSnapshot(StorageNamespace.projects),
          hasLength(5),
        );

        // Corrupt the queue file in place (simulates torn write / crash).
        final queueFile = File('${directory.path}/.us/sync_queue_v1.json');
        expect(queueFile.existsSync(), isTrue);
        await queueFile.writeAsString('{"outbox": [TRUNCATED GARBAGE');

        // New kernel instance must boot without throwing.
        final recoveredProvider = FileSystemStorageProvider();
        await recoveredProvider.initWithConfig(
          FileSystemConfig(
            filePathConfig: FilePathConfig.create(
              path: directory.path,
              macOSBookmarkData: MacOSBookmark.fromDirectory(directory),
            ),
          ),
        );
        final recovered = StorageKernel(
          profile: StorageProfile(
            name: 'chaos_corrupt',
            namespaces: [
              StorageNamespaceProfile(
                namespace: StorageNamespace.projects,
                policy: StoragePolicy.optimisticSync,
                remoteEngineId: 'unreachable',
              ),
            ],
          ),
          resolver: InMemoryStorageProfileResolver(
            namespaceServices: {
              StorageNamespace.projects: StorageService(recoveredProvider),
            },
          ),
        );

        // Queue resets to empty but USER DATA is untouched.
        final outbox = await recovered.outboxSnapshot(
          StorageNamespace.projects,
        );
        expect(outbox, isEmpty);
        for (var i = 0; i < 5; i++) {
          final content = await recovered.read(
            namespace: StorageNamespace.projects,
            path: 'data/file-$i.json',
          );
          expect(content, '{"i":$i}', reason: 'file-$i lost after corruption');
        }
      } finally {
        await directory.delete(recursive: true);
      }
    });

    test('queue file deleted → user data unaffected', () async {
      final (kernel, directory) = await buildKernel(name: 'deleted');
      try {
        for (var i = 0; i < 3; i++) {
          await kernel.write(
            namespace: StorageNamespace.projects,
            path: 'data/keep-$i.json',
            content: 'value-$i',
          );
        }
        final queueFile = File('${directory.path}/.us/sync_queue_v1.json');
        if (queueFile.existsSync()) {
          await queueFile.delete();
        }

        final recoveredProvider = FileSystemStorageProvider();
        await recoveredProvider.initWithConfig(
          FileSystemConfig(
            filePathConfig: FilePathConfig.create(
              path: directory.path,
              macOSBookmarkData: MacOSBookmark.fromDirectory(directory),
            ),
          ),
        );
        final recovered = StorageKernel(
          profile: StorageProfile(
            name: 'chaos_deleted',
            namespaces: [
              StorageNamespaceProfile(
                namespace: StorageNamespace.projects,
                policy: StoragePolicy.optimisticSync,
                remoteEngineId: 'unreachable',
              ),
            ],
          ),
          resolver: InMemoryStorageProfileResolver(
            namespaceServices: {
              StorageNamespace.projects: StorageService(recoveredProvider),
            },
          ),
        );

        for (var i = 0; i < 3; i++) {
          expect(
            await recovered.read(
              namespace: StorageNamespace.projects,
              path: 'data/keep-$i.json',
            ),
            'value-$i',
          );
        }
      } finally {
        await directory.delete(recursive: true);
      }
    });
  });

  group('chaos: duplicate delivery', () {
    test('replaying same entry twice is idempotent', () async {
      final (kernel, directory) = await buildKernel(name: 'dupes');
      try {
        await kernel.write(
          namespace: StorageNamespace.projects,
          path: 'data/same.json',
          content: '{"v":1}',
        );
        final entries = await kernel.outboxSnapshot(StorageNamespace.projects);
        expect(entries, hasLength(1));
        final entryId = entries.single.id;

        // Simulate double-delivery by re-adding the applied id to the
        // outbox via a second identical write. Deterministic ids mean
        // identical content collapses to one entry.
        await kernel.write(
          namespace: StorageNamespace.projects,
          path: 'data/same.json',
          content: '{"v":1}',
        );
        final afterDupe = await kernel.outboxSnapshot(
          StorageNamespace.projects,
        );
        expect(afterDupe, hasLength(1));
        expect(afterDupe.single.id, entryId);
      } finally {
        await directory.delete(recursive: true);
      }
    });
  });

  group('chaos: concurrent queue access', () {
    test('interleaved writes never lose an entry', () async {
      final (kernel, directory) = await buildKernel(name: 'concurrent');
      try {
        // Fire 20 writes concurrently; all must land in the outbox.
        await Future.wait([
          for (var i = 0; i < 20; i++)
            kernel.write(
              namespace: StorageNamespace.projects,
              path: 'data/conc-$i.json',
              content: '{"i":$i}',
            ),
        ]);
        final outbox = await kernel.outboxSnapshot(StorageNamespace.projects);
        expect(outbox, hasLength(20));
      } finally {
        await directory.delete(recursive: true);
      }
    });
  });
}
