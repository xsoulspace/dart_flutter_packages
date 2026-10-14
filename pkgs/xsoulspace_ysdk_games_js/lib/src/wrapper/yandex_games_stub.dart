import 'models.dart';

export 'enums.dart';
export 'models.dart';

Never _unsupported() {
  throw UnsupportedError(
    'Yandex Games SDK is available only on web (dart.library.js_interop).',
  );
}

/// Non-web fallback for Yandex Games wrapper.
abstract final class YandexGames {
  static Future<YsdkClient> init({
    bool signed = false,
    String expectedGlobal = 'YaGames',
  }) async => _unsupported();

  static bool isAvailable({String expectedGlobal = 'YaGames'}) => false;
}

class YsdkClient {
  YsdkAdvClient get adv => _unsupported();
  YsdkLeaderboardsClient get leaderboards => _unsupported();
  YsdkMultiplayerClient get multiplayer => _unsupported();
  YsdkPaymentsClient get payments => _unsupported();

  Future<Map<String, String>> getFlags({
    List<ClientFeatureModel>? clientFeatures,
    Map<String, String>? defaultFlags,
  }) async => _unsupported();

  Future<YsdkPaymentsClient> getPaymentsUnsigned() async => _unsupported();
  Future<YsdkPaymentsClient> getPaymentsSigned() async => _unsupported();
  Future<YsdkPlayer> getPlayerUnsigned() async => _unsupported();
  Future<SignatureModel> getPlayerSigned() async => _unsupported();
  double serverTime() => _unsupported();
}

class YsdkPlayer {
  String getName() => _unsupported();
  String getPhoto(String size) => _unsupported();
  String getUniqueId() => _unsupported();
  bool isAuthorized() => _unsupported();
  Future<Map<String, Object?>> getStats([List<String>? keys]) async =>
      _unsupported();
  Future<void> setStats(Map<String, num> stats) async => _unsupported();
}

class YsdkPaymentsClient {
  Future<void> consumePurchase(String token) async => _unsupported();
  Future<List<ProductModel>> getCatalog() async => _unsupported();
  Future<List<PurchaseModel>> getPurchasesUnsigned() async => _unsupported();
  Future<SignatureModel> getPurchasesSigned() async => _unsupported();
  Future<PurchaseModel> purchaseUnsigned({
    required String id,
    String? developerPayload,
  }) async => _unsupported();
  Future<SignatureModel> purchaseSigned({
    required String id,
    String? developerPayload,
  }) async => _unsupported();
}

class YsdkAdvClient {
  Future<BannerAdvShowResult> showBannerAdv() async => _unsupported();
}

class YsdkLeaderboardsClient {
  Future<LeaderboardEntriesDataModel> getEntries(
    String leaderboardName, {
    bool? includeUser,
    int? quantityAround,
    int? quantityTop,
  }) async => _unsupported();

  Future<LeaderboardEntryModel> getPlayerEntry(
    String leaderboardName,
  ) async => _unsupported();

  Future<void> setScore(
    String leaderboardName,
    int score, {
    String? extraData,
  }) async => _unsupported();
}

class YsdkMultiplayerClient {
  YsdkMultiplayerSessionsClient get sessions => _unsupported();
}

class YsdkMultiplayerSessionsClient {
  void commit(MultiplayerCommitPayloadModel payload) => _unsupported();

  Future<List<MultiplayerSessionOpponentModel>> init({
    MultiplayerInitOptionsModel? options,
  }) async => _unsupported();

  Future<CallbackBaseMessageDataModel> push(
    MultiplayerMetaModel meta,
  ) async => _unsupported();
}
