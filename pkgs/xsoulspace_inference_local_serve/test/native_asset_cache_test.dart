import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_inference_local_serve/native_asset_cache.dart';

void main() {
  test('default cache destination is preserved', () {
    expect(
      nativeAssetCacheDirectory(
        component: 'laya',
        homeDirectory: '/fixture/home',
      ).path,
      '/fixture/home/.cache/xsoulspace/laya/native/',
    );
  });
  test(
    'explicit preparation root separates native components without writes',
    () {
      final tmp = Directory.systemTemp.createTempSync(
        'native-cache-destination-',
      );
      addTearDown(() => tmp.deleteSync(recursive: true));
      final root = '${tmp.path}/uncreated';
      final laya = nativeAssetCacheDirectory(
        component: 'laya',
        configuredRoot: root,
      );
      final mlx = nativeAssetCacheDirectory(
        component: 'mlx_text',
        configuredRoot: root,
      );
      expect(laya.path, '$root/laya/native/');
      expect(mlx.path, '$root/mlx_text/native/');
      expect(Directory(root).existsSync(), isFalse);
    },
  );
  test('relative, empty or wrongly typed overrides refuse', () {
    for (final value in <Object>['relative', '', false, 42]) {
      expect(
        () =>
            nativeAssetCacheDirectory(component: 'laya', configuredRoot: value),
        throwsFormatException,
      );
    }
  });
  test('component cannot escape the configured destination', () {
    expect(
      () => nativeAssetCacheDirectory(
        component: '../laya',
        configuredRoot: '/fixture/cache',
      ),
      throwsFormatException,
    );
  });
}
