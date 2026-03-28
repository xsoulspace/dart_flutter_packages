import 'package:test/test.dart';
import 'package:xsoulspace_platform_yandex_games/xsoulspace_platform_yandex_games.dart';

void main() {
  test('environmentProbe override has highest priority', () async {
    var probeCalled = false;
    final factory = YandexGamesPlatformFactory(
      config: const YandexGamesPlatformConfig(
        expectedSdkGlobal: 'CustomYsdk',
        sdkInjected: true,
      ),
      environmentProbe: (final expectedGlobal) {
        probeCalled = true;
        expect(expectedGlobal, 'CustomYsdk');
        return false;
      },
    );

    expect(await factory.isSupportedEnvironment(), isFalse);
    expect(probeCalled, isTrue);
  });

  test(
    'autoload-ready config reports supported without probing globals',
    () async {
      final factory = YandexGamesPlatformFactory(
        config: YandexGamesPlatformConfig(
          autoLoadSdk: true,
          sdkUrl: Uri.parse('https://example.com/ysdk.js'),
          sdkScriptLoader: (final _) async {},
        ),
      );

      expect(await factory.isSupportedEnvironment(), isTrue);
    },
  );
}
