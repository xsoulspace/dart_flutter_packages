import 'ysdk_client.dart';
import 'converters.dart';
import '../raw/ysdk_raw.g.dart' as raw;

export 'ysdk_client.dart';
export 'models.dart';
export 'enums.dart';

/// Wrapper entrypoint for Yandex Games SDK.
abstract final class YandexGames {
  static Future<YsdkClient> init({
    final bool signed = false,
    final String expectedGlobal = 'YaGames',
  }) async {
    final global = _resolveGlobal(expectedGlobal: expectedGlobal);
    if (global == null) {
      throw StateError(
        'Yandex Games SDK global `$expectedGlobal` was not detected.',
      );
    }

    final opts = jsify(<String, Object?>{'signed': signed});
    final sdk = await jsCallPromise(global, 'init', <Object?>[opts]);
    if (sdk == null) {
      throw StateError('Yandex Games SDK init returned null.');
    }
    return YsdkClient.fromSdk(sdk, signed: signed);
  }

  static bool isAvailable({final String expectedGlobal = 'YaGames'}) {
    return _resolveGlobal(expectedGlobal: expectedGlobal) != null;
  }

  static Object? _resolveGlobal({required final String expectedGlobal}) {
    if (!hasGlobalProperty(expectedGlobal)) {
      return null;
    }

    if (expectedGlobal == 'YaGames') {
      return raw.yaGames;
    }
    return globalProperty(expectedGlobal);
  }
}
