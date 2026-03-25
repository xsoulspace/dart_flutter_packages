import '../raw/vkplay_raw.g.dart' as raw;
import 'converters.dart';
import 'vkplay_client.dart';

export 'models.dart';
export 'vkplay_client.dart';

/// Wrapper entrypoint for VK Play `iframeApi` SDK.
abstract final class VkPlay {
  static Future<VkPlayClient> init({
    final String? appId,
    final String expectedGlobal = 'iframeApi',
  }) async {
    final sdk = _resolveSdk(expectedGlobal: expectedGlobal);
    if (sdk == null) {
      throw StateError(
        'VK Play SDK global `$expectedGlobal` was not detected.',
      );
    }

    final client = VkPlayClient(sdk);
    await client.init(appId: appId);
    return client;
  }

  static bool isAvailable({final String expectedGlobal = 'iframeApi'}) {
    return _resolveSdk(expectedGlobal: expectedGlobal) != null;
  }

  static Object? _resolveSdk({required final String expectedGlobal}) {
    if (expectedGlobal == 'iframeApi') {
      final known = raw.iframeApi;
      if (known != null) {
        return known;
      }
    }

    if (!hasGlobalProperty(expectedGlobal)) {
      return null;
    }
    return globalProperty(expectedGlobal);
  }
}
