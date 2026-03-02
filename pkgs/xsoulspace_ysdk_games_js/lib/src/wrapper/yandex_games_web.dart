import 'ysdk_client.dart';
import 'converters.dart';
import '../raw/ysdk_raw.g.dart' as raw;

export 'ysdk_client.dart';
export 'models.dart';
export 'enums.dart';

/// Wrapper entrypoint for Yandex Games SDK.
abstract final class YandexGames {
  static Future<YsdkClient> init({final bool signed = false}) async {
    final opts = jsify(<String, Object?>{'signed': signed});
    final sdk = await jsCallPromise(raw.yaGames, 'init', <Object?>[opts]);
    if (sdk == null) {
      throw StateError('Yandex Games SDK init returned null.');
    }
    return YsdkClient.fromSdk(sdk, signed: signed);
  }
}
