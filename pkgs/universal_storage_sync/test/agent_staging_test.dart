import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_storage_filesystem/universal_storage_filesystem.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_sync/universal_storage_sync.dart';

void main() {
  late Directory directory;
  late StorageService service;
  late AgentEditStager stager;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('agent_staging');
    final provider = FileSystemStorageProvider();
    await provider.initWithConfig(
      FileSystemConfig(
        filePathConfig: FilePathConfig.create(
          path: directory.path,
          macOSBookmarkData: MacOSBookmark.fromDirectory(directory),
        ),
      ),
    );
    service = StorageService(provider);
    stager = AgentEditStager(queueStore: InMemorySyncQueueStore());
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('stage → list → promote writes to target and clears the draft',
      () async {
    final entryId = await stager.stage(
      service: service,
      path: 'docs/design.md',
      content: 'proposed new paragraph',
      agentId: 'test-agent',
    );
    expect(entryId, isNotEmpty);

    final pending = await stager.listPending(service: service);
    expect(pending, hasLength(1));
    expect(pending.single.path, 'docs/design.md');
    expect(pending.single.content, 'proposed new paragraph');

    final result = await stager.promote(
      service: service,
      namespaceProfile: const StorageNamespaceProfile(
        namespace: StorageNamespace.projects,
        policy: StoragePolicy.localOnly,
      ),
      entryId: entryId,
      targetPath: 'docs/design.md',
      content: 'proposed new paragraph',
    );
    expect(result.path.endsWith('docs/design.md'), isTrue);

    final promoted = await service.readFile('docs/design.md');
    expect(promoted, 'proposed new paragraph');
    expect(await stager.listPending(service: service), isEmpty);
  });

  test('drop removes the proposal without touching the target', () async {
    final entryId = await stager.stage(
      service: service,
      path: 'docs/x.md',
      content: 'bad idea',
    );
    await stager.drop(service: service, entryId: entryId);
    expect(await stager.listPending(service: service), isEmpty);
    expect(await service.readFile('docs/x.md'), isNull);
  });

  test('staging identical content twice collapses to one proposal',
      () async {
    await stager.stage(
      service: service,
      path: 'docs/same.md',
      content: 'identical',
    );
    await stager.stage(
      service: service,
      path: 'docs/same.md',
      content: 'identical',
    );
    // Both stages write draft files keyed by the same deterministic id.
    final pending = await stager.listPending(service: service);
    expect(pending, hasLength(1));
  });
}
