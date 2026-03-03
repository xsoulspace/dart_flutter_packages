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
  YsdkLeaderboardsClient get leaderboards => _unsupported();
  YsdkMultiplayerClient get multiplayer => _unsupported();
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
  String getName() => _unsupported();
  String getPhoto(final String size) => _unsupported();
  String getUniqueId() => _unsupported();
  bool isAuthorized() => _unsupported();
  Future<Map<String, Object?>> getStats([final List<String>? keys]) async =>
      _unsupported();
  Future<void> setStats(final Map<String, num> stats) async => _unsupported();
}

class YsdkPaymentsClient {
  Future<void> consumePurchase(final String token) async => _unsupported();
  Future<List<ProductModel>> getCatalog() async => _unsupported();
  Future<List<PurchaseModel>> getPurchasesUnsigned() async => _unsupported();
  Future<SignatureModel> getPurchasesSigned() async => _unsupported();
  Future<PurchaseModel> purchaseUnsigned({
    required final String id,
    final String? developerPayload,
  }) async => _unsupported();
  Future<SignatureModel> purchaseSigned({
    required final String id,
    final String? developerPayload,
  }) async => _unsupported();
}

class YsdkAdvClient {
  Future<BannerAdvShowResult> showBannerAdv() async => _unsupported();
}

class YsdkLeaderboardsClient {
  Future<LeaderboardEntriesDataModel> getEntries(
    final String leaderboardName, {
    final bool? includeUser,
    final int? quantityAround,
    final int? quantityTop,
  }) async => _unsupported();

  Future<LeaderboardEntryModel> getPlayerEntry(
    final String leaderboardName,
  ) async => _unsupported();

  Future<void> setScore(
    final String leaderboardName,
    final int score, {
    final String? extraData,
  }) async => _unsupported();
}

class YsdkMultiplayerClient {
  YsdkMultiplayerSessionsClient get sessions => _unsupported();
}

class YsdkMultiplayerSessionsClient {
  void commit(final MultiplayerCommitPayloadModel payload) => _unsupported();

  Future<List<MultiplayerSessionOpponentModel>> init({
    final MultiplayerInitOptionsModel? options,
  }) async => _unsupported();

  Future<CallbackBaseMessageDataModel> push(
    final MultiplayerMetaModel meta,
  ) async => _unsupported();
}
