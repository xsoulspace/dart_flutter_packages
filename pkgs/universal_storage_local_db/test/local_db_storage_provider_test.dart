import 'package:test/test.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_local_db/universal_storage_local_db.dart';
import 'package:xsoulspace_foundation/xsoulspace_foundation.dart';

void main() {
  group('LocalDbStorageProvider', () {
    late _InMemoryLocalDb localDb;
    late LocalDbStorageProvider provider;

    setUp(() {
      localDb = _InMemoryLocalDb();
      provider = LocalDbStorageProvider(localDb: localDb);
    });

    test('implements LocalEngine role for kernel profile routing', () {
      expect(provider, isA<LocalEngine>());
      expect(provider, isNot(isA<RemoteEngine>()));
    });

    test('stores and reads file content', () async {
      await provider.initWithConfig(_configForPrefix('default'));

      await provider.createFile('settings/theme.json', '{"theme":"light"}');
      final raw = await provider.getFile('settings/theme.json');

      expect(raw, '{"theme":"light"}');
    });

    test('supports update and delete flows', () async {
      await provider.initWithConfig(_configForPrefix('default'));
      await provider.createFile('notes/todo.txt', 'first');

      await provider.updateFile('notes/todo.txt', 'second');
      expect(await provider.getFile('notes/todo.txt'), 'second');

      await provider.deleteFile('notes/todo.txt');
      expect(await provider.getFile('notes/todo.txt'), isNull);
    });

    test('lists files and subdirectories for a path', () async {
      await provider.initWithConfig(_configForPrefix('default'));
      await provider.createFile('notes/a.txt', 'A');
      await provider.createFile('notes/sub/b.txt', 'B');
      await provider.createFile('logs/c.txt', 'C');

      final rootEntries = await provider.listDirectory('.');
      final rootNames = rootEntries.map((final e) => e.name).toList();
      expect(rootNames, contains('logs'));
      expect(rootNames, contains('notes'));

      final notesEntries = await provider.listDirectory('notes');
      final notesNames = notesEntries.map((final e) => e.name).toList();
      expect(notesNames, contains('a.txt'));
      expect(notesNames, contains('sub'));
    });

    test('isolates storage by keyspace prefix', () async {
      final aProvider = LocalDbStorageProvider(localDb: localDb);
      final bProvider = LocalDbStorageProvider(localDb: localDb);

      await aProvider.initWithConfig(const LocalDbStorageConfig(keyspacePrefix: 'app_a'));
      await bProvider.initWithConfig(const LocalDbStorageConfig(keyspacePrefix: 'app_b'));

      await aProvider.createFile('profile.json', '{"scope":"a"}');
      await bProvider.createFile('profile.json', '{"scope":"b"}');

      expect(await aProvider.getFile('profile.json'), '{"scope":"a"}');
      expect(await bProvider.getFile('profile.json'), '{"scope":"b"}');
    });

    test('accepts LocalDbStorageConfig without filesystem path hacks', () async {
      await provider.initWithConfig(
        const LocalDbStorageConfig(keyspacePrefix: 'arena_voice_settings'),
      );

      await provider.createFile('voice/settings.json', '{"language":"en"}');

      expect(
        await provider.getFile('voice/settings.json'),
        '{"language":"en"}',
      );
    });

    test('throws expected errors for invalid mutations', () async {
      await provider.initWithConfig(_configForPrefix('default'));

      expect(
        () => provider.updateFile('unknown.json', 'x'),
        throwsA(isA<FileNotFoundException>()),
      );
      expect(
        () => provider.deleteFile('unknown.json'),
        throwsA(isA<FileNotFoundException>()),
      );

      await provider.createFile('same.json', 'first');
      expect(
        () => provider.createFile('same.json', 'second'),
        throwsA(isA<FileAlreadyExistsException>()),
      );
    });
  });
}

FileSystemConfig _configForPrefix(final String prefix) => FileSystemConfig(
  filePathConfig: FilePathConfig.create(
    path: '/$prefix',
    macOSBookmarkData: MacOSBookmark.empty,
  ),
  databaseName: prefix,
);

final class _InMemoryLocalDb implements LocalDbI {
  final Map<String, bool> _bools = <String, bool>{};
  final Map<String, int> _ints = <String, int>{};
  final Map<String, String> _strings = <String, String>{};
  final Map<String, Map<String, dynamic>> _maps = <String, Map<String, dynamic>>{};
  final Map<String, List<String>> _stringLists = <String, List<String>>{};

  @override
  Future<void> init() async {}

  @override
  Future<void> clear() async {
    _bools.clear();
    _ints.clear();
    _strings.clear();
    _maps.clear();
    _stringLists.clear();
  }

  @override
  Future<void> clearKey({required final String key}) async {
    _bools.remove(key);
    _ints.remove(key);
    _strings.remove(key);
    _maps.remove(key);
    _stringLists.remove(key);
  }

  @override
  Future<bool> getBool({
    required final String key,
    final bool defaultValue = false,
  }) async => _bools[key] ?? defaultValue;

  @override
  Future<int> getInt({
    required final String key,
    final int defaultValue = 0,
  }) async => _ints[key] ?? defaultValue;

  @override
  Future<Map<String, dynamic>> getMap(final String key) async =>
      Map<String, dynamic>.from(_maps[key] ?? const <String, dynamic>{});

  @override
  Future<Iterable<Map<String, dynamic>>> getMapIterable({
    required final String key,
    final List<Map<String, dynamic>> defaultValue = const [],
  }) async {
    final values = _stringLists[key];
    if (values == null) {
      return defaultValue;
    }
    return values
        .map((final item) => _maps[item])
        .whereType<Map<String, dynamic>>()
        .map(Map<String, dynamic>.from)
        .toList(growable: false);
  }

  @override
  Future<String> getString({
    required final String key,
    final String defaultValue = '',
  }) async => _strings[key] ?? defaultValue;

  @override
  Future<Iterable<String>> getStringsIterable({
    required final String key,
    final List<String> defaultValue = const [],
  }) async =>
      List<String>.from(_stringLists[key] ?? defaultValue);

  @override
  Future<T> getItem<T>({
    required final String key,
    required final T? Function(Map<String, dynamic> p1) fromJson,
    required final T defaultValue,
  }) async => fromJson(await getMap(key)) ?? defaultValue;

  @override
  Future<Iterable<T>> getItemsIterable<T>({
    required final String key,
    required final T Function(Map<String, dynamic> p1) fromJson,
    final List<T> defaultValue = const [],
  }) async {
    final values = await getMapIterable(key: key);
    if (values.isEmpty) {
      return defaultValue;
    }
    return values.map(fromJson).toList(growable: false);
  }

  @override
  Future<void> setBool({required final String key, required final bool value}) async {
    _bools[key] = value;
  }

  @override
  Future<void> setInt({required final String key, final int value = 0}) async {
    _ints[key] = value;
  }

  @override
  Future<void> setMap({
    required final String key,
    required final Map<String, dynamic> value,
  }) async {
    _maps[key] = Map<String, dynamic>.from(value);
  }

  @override
  Future<void> setMapList({
    required final String key,
    required final List<Map<String, dynamic>> value,
  }) async {
    final ids = <String>[];
    for (var index = 0; index < value.length; index++) {
      final id = '$key#$index';
      _maps[id] = Map<String, dynamic>.from(value[index]);
      ids.add(id);
    }
    _stringLists[key] = ids;
  }

  @override
  Future<void> setString({
    required final String key,
    required final String value,
  }) async {
    _strings[key] = value;
  }

  @override
  Future<void> setStringList({
    required final String key,
    required final List<String> value,
  }) async {
    _stringLists[key] = List<String>.from(value);
  }

  @override
  Future<void> setItem<T>({
    required final String key,
    required final T value,
    required final Map<String, dynamic> Function(T p1) toJson,
  }) async {
    await setMap(key: key, value: toJson(value));
  }

  @override
  Future<void> setItemsList<T>({
    required final String key,
    required final List<T> value,
    required final Map<String, dynamic> Function(T p1) toJson,
  }) async {
    await setMapList(
      key: key,
      value: value.map(toJson).toList(growable: false),
    );
  }
}
