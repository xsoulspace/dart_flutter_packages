export 'models.dart';
export 'enums.dart';
import 'models.dart';

Never _unsupported() {
  throw UnsupportedError(
    'Yandex Games SDK is available only on web (dart.library.js_interop).',
  );
}

/// Non-web fallback for Yandex Games wrapper.
abstract final class YandexGames {
  static Future<YsdkClient> init({final bool signed = false}) async =>
      _unsupported();
}

class YsdkClient {
  YsdkAdvClient get adv => _unsupported();
  YsdkPaymentsClient get payments => _unsupported();

  Future<Map<String, String>> getFlags({
    final List<ClientFeatureModel>? clientFeatures,
    final Map<String, String>? defaultFlags,
  }) async => _unsupported();

  Future<YsdkPaymentsClient> getPaymentsUnsigned() async => _unsupported();
  Future<YsdkPaymentsClient> getPaymentsSigned() async => _unsupported();
  Future<YsdkPlayer> getPlayerUnsigned() async => _unsupported();
  Future<SignatureModel> getPlayerSigned() async => _unsupported();
  double serverTime() => _unsupported();
}

class YsdkPlayer {
  String getUniqueId() => _unsupported();
}

class YsdkPaymentsClient {
  Future<List<ProductModel>> getCatalog() async => _unsupported();
  Future<List<PurchaseModel>> getPurchasesUnsigned() async => _unsupported();
  Future<SignatureModel> getPurchasesSigned() async => _unsupported();
}

class YsdkAdvClient {
  Future<BannerAdvShowResult> showBannerAdv() async => _unsupported();
}
