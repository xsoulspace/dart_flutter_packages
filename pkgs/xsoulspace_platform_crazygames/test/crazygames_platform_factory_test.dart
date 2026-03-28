import 'package:test/test.dart';
import 'package:xsoulspace_platform_crazygames/xsoulspace_platform_crazygames.dart';

void main() {
  test('environmentProbe override has highest priority', () async {
    var probeCalled = false;
    final factory = CrazyGamesPlatformFactory(
      config: const CrazyGamesPlatformConfig(
        expectedSdkGlobal: 'CustomCrazy',
        sdkInjected: true,
      ),
      environmentProbe: (final expectedGlobal) {
        probeCalled = true;
        expect(expectedGlobal, 'CustomCrazy');
        return false;
      },
    );

    expect(await factory.isSupportedEnvironment(), isFalse);
    expect(probeCalled, isTrue);
  });

  test(
    'autoload-ready config reports supported without probing globals',
    () async {
      final factory = CrazyGamesPlatformFactory(
        config: CrazyGamesPlatformConfig(
          autoLoadSdk: true,
          sdkUrl: Uri.parse('https://example.com/crazygames-sdk.js'),
          sdkScriptLoader: (final _) async {},
        ),
      );

      expect(await factory.isSupportedEnvironment(), isTrue);
    },
  );
}
