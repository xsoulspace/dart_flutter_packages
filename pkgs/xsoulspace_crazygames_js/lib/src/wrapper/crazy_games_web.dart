import 'crazygames_client.dart';
import 'converters.dart';
import '../raw/crazygames_raw.g.dart' as raw;

export 'crazygames_client.dart';
export 'models.dart';
export 'enums.dart';

/// Wrapper entrypoint for CrazyGames HTML5 SDK.
abstract final class CrazyGames {
  static Future<CrazyGamesClient> init({
    final String expectedGlobal = 'CrazyGames',
  }) async {
    final sdk = _resolveSdk(expectedGlobal: expectedGlobal);
    if (sdk == null) {
      throw StateError(
        'CrazyGames SDK global `$expectedGlobal` was not detected.',
      );
    }
    await jsCallPromise(sdk, 'init');
    return CrazyGamesClient(sdk);
  }

  static bool isAvailable({final String expectedGlobal = 'CrazyGames'}) {
    return _resolveSdk(expectedGlobal: expectedGlobal) != null;
  }

  static Object? _resolveSdk({required final String expectedGlobal}) {
    if (!hasGlobalProperty(expectedGlobal)) {
      return null;
    }

    if (expectedGlobal == 'CrazyGames') {
      return raw.crazyGamesSdk;
    }

    final customGlobal = globalProperty(expectedGlobal);
    if (customGlobal == null) {
      return null;
    }

    final customSdk = prop(customGlobal, 'SDK');
    return customSdk ?? customGlobal;
  }
}
