/// Universal Storage Conformance - shared behavioral test suite.
///
/// Backends opt in by calling [storageProviderConformanceTests] with a
/// factory that produces a fresh, initialized provider per scenario:
///
/// ```dart
/// void main() {
///   storageProviderConformanceTests(
///     'FileSystemStorageProvider',
///     create: () async {
///       final dir = await Directory.systemTemp.createTemp('conf_');
///       final provider = FileSystemStorageProvider();
///       await provider.initWithConfig(FileSystemConfig(
///         filePathConfig: FilePathConfig.create(path: dir.path),
///       ));
///       return provider;
///     },
///     supportsSync: false,
///   );
/// }
/// ```
library;

import 'package:test/test.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';

/// Factory producing a fresh, initialized provider per scenario.
typedef ProviderFactory = Future<StorageProvider> Function();

/// Runs the full behavioral conformance suite against a provider factory.
///
/// Every backend that claims `StorageProvider` compatibility must pass all
/// of these scenarios. Platform-specific backends (web-only or native-only)
/// run the same suite in their respective test environments; the suite
/// itself contains no platform-conditional logic.
void storageProviderConformanceTests(
  final String backendName, {
  required final ProviderFactory create,
  final bool supportsSync = false,
}) {
  group('$backendName conformance', () {
    late StorageProvider provider;

    setUp(() async {
      provider = await create();
    });

    tearDown(() async {
      await provider.dispose();
    });

    test('create → getFile round-trips content', () async {
      final result = await provider.createFile(
        'conf/roundtrip.json',
        '{"a":1}',
      );
      expect(result.path, endsWith('conf/roundtrip.json'));
      expect(result.isNew, isTrue);

      expect(await provider.getFile('conf/roundtrip.json'), '{"a":1}');
    });

    test('updateFile overwrites content and keeps path', () async {
      await provider.createFile('conf/update.json', 'v1');
      final result = await provider.updateFile('conf/update.json', 'v2');

      expect(result.isNew, isFalse);
      expect(await provider.getFile('conf/update.json'), 'v2');
    });

    test('getFile returns null for missing file', () async {
      expect(await provider.getFile('conf/missing.json'), isNull);
    });

    test('deleteFile removes content; subsequent read is null', () async {
      await provider.createFile('conf/gone.json', 'data');
      final result = await provider.deleteFile('conf/gone.json');

      expect(result.path, endsWith('conf/gone.json'));
      expect(await provider.getFile('conf/gone.json'), isNull);
    });

    test('listDirectory includes created files', () async {
      await provider.createFile('conf/list/a.json', '1');
      await provider.createFile('conf/list/b.json', '2');

      final entries = await provider.listDirectory('conf/list');
      final names = entries.map((final e) => e.name.split('/').last).toSet();
      expect(names, containsAll(<String>['a.json', 'b.json']));
    });

    test('paths are normalized: leading/trailing slashes tolerated', () async {
      // Leading/trailing separators must resolve to the same object.
      await provider.createFile('conf/norm/x.json', 'n');
      expect(await provider.getFile('/conf/norm/x.json/'), 'n');
    });

    test('empty content is a valid stored value', () async {
      await provider.createFile('conf/empty.txt', '');
      expect(await provider.getFile('conf/empty.txt'), '');
    });

    test('unicode and large payloads round-trip', () async {
      final payload = '{"text":"héllo 🌍","blob":"${'x' * 100000}"}';
      await provider.createFile('conf/big.json', payload);
      expect(await provider.getFile('conf/big.json'), payload);
    });

    test('idempotent create-or-update via update after create', () async {
      await provider.createFile('conf/idem.json', 'one');
      await provider.updateFile('conf/idem.json', 'two');
      expect(await provider.getFile('conf/idem.json'), 'two');
    });

    test('isAuthenticated reports deterministic state', () async {
      // Local backends are always authenticated; remote ones may vary but
      // must not throw in normal initialized use.
      expect(() => provider.isAuthenticated(), returnsNormally);
    });

    if (supportsSync) {
      group('sync-capable contract', () {
        test('sync completes without throwing on clean state', () async {
          await provider.createFile('conf/synced.json', 's');
          await expectLater(provider.sync(), completes);
        });

        test('restore without version restores latest', () async {
          await provider.createFile('conf/restore.json', 'r1');
          await expectLater(provider.restore('conf/restore.json'), completes);
        });
      });
    } else {
      test('sync throws UnsupportedOperationException when unsupported', () {
        expect(
          () => provider.sync(),
          throwsA(isA<UnsupportedOperationException>()),
        );
      });
    }
  });
}
