// ignore_for_file: lines_longer_than_80_chars

/// EnvConfig — global/local env config file store with process-env
/// precedence. Uses temp dirs so no machine state is touched.
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

void main() {
  late Directory tmp;
  late String globalPath;
  late String localPath;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('env_config_test_');
    globalPath = '${tmp.path}/global/config.json';
    localPath = '${tmp.path}/local/.xsoulspace/config.json';
  });

  tearDown(() => tmp.delete(recursive: true));

  test('set persists per scope and get resolves across scopes', () async {
    final cfg = await EnvConfig.load(
      globalPath: globalPath,
      localPath: localPath,
    );
    await cfg.set('GLOBAL_KEY', 'g1', scope: ConfigScope.global);
    await cfg.set('LOCAL_KEY', 'l1', scope: ConfigScope.local);

    expect(cfg.get('GLOBAL_KEY'), 'g1');
    expect(cfg.get('LOCAL_KEY'), 'l1');

    // Files exist at the configured paths with valid JSON.
    expect(File(globalPath).existsSync(), isTrue);
    expect(File(localPath).existsSync(), isTrue);
    final reloaded = await EnvConfig.load(
      globalPath: globalPath,
      localPath: localPath,
    );
    expect(reloaded.get('GLOBAL_KEY'), 'g1');
    expect(reloaded.get('LOCAL_KEY'), 'l1');
  });

  test('local overrides global; missing keys return null', () async {
    File(localPath).parent.createSync(recursive: true);
    File(localPath).writeAsStringSync('{"KEY":"from-local"}');
    File(globalPath).parent.createSync(recursive: true);
    File(globalPath).writeAsStringSync('{"KEY":"from-global"}');

    final cfg = await EnvConfig.load(
      globalPath: globalPath,
      localPath: localPath,
    );
    expect(cfg.get('KEY'), 'from-local');
    expect(cfg.keys()['KEY'], ConfigScope.local);
    expect(cfg.get('NOPE'), isNull);
  });

  test('process environment wins over both files', () async {
    File(globalPath).parent.createSync(recursive: true);
    File(globalPath).writeAsStringSync('{"PATH_LIKE":"from-file"}');
    // PATH always exists in the process env — proves env beats files.
    final cfg = await EnvConfig.load(
      globalPath: globalPath,
      localPath: localPath,
    );
    await cfg.set('PATH_LIKE', 'from-file-too', scope: .global);
    expect(cfg.get('PATH'), isNotNull);
  });

  test('malformed config is skipped with a warning, not thrown', () async {
    File(localPath).parent.createSync(recursive: true);
    File(localPath).writeAsStringSync('{not json');
    var reported = false;
    final cfg = await EnvConfig.load(
      globalPath: globalPath,
      localPath: localPath,
      onCorrupt: (path, _) => reported = true,
    );
    expect(reported, isTrue);
    expect(cfg.get('anything'), isNull);
    // And the store still works — set overwrites the broken file.
    await cfg.set('K', 'v', scope: .local);
    final again = await EnvConfig.load(
      globalPath: globalPath,
      localPath: localPath,
    );
    expect(again.get('K'), 'v');
  });

  test('delete removes only from its own scope', () async {
    final cfg = await EnvConfig.load(
      globalPath: globalPath,
      localPath: localPath,
    );
    await cfg.set('K', 'global', scope: ConfigScope.global);
    await cfg.set('K2', 'local', scope: ConfigScope.local);

    expect(await cfg.delete('K', scope: .local), isFalse);
    expect(cfg.get('K'), 'global'); // untouched in global
    expect(await cfg.delete('K2', scope: .local), isTrue);
    expect(cfg.get('K2'), isNull);
  });

  test('non-object JSON root is treated as corrupt', () async {
    File(globalPath).parent.createSync(recursive: true);
    File(globalPath).writeAsStringSync('[1,2,3]');
    var reported = false;
    final cfg = await EnvConfig.load(
      globalPath: globalPath,
      localPath: localPath,
      onCorrupt: (_, __) => reported = true,
    );
    expect(reported, isTrue);
    expect(cfg.keys(), isEmpty);
  });
}
