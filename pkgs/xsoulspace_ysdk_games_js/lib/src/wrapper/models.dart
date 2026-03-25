import 'package:meta/meta.dart';

import 'enums.dart';

@immutable
class ClientFeatureModel {
  const ClientFeatureModel({required this.name, required this.value});

  final String name;
  final String value;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'value': value,
  };
}

@immutable
class SignatureModel {
  const SignatureModel({required this.signature});

  factory SignatureModel.fromMap(final Map<String, Object?> map) =>
      SignatureModel(signature: (map['signature'] as String?) ?? '');

  final String signature;
}

@immutable
class BannerAdvStatus {
  const BannerAdvStatus({required this.stickyAdvIsShowing, this.reason});

  final bool stickyAdvIsShowing;
  final StickyAdvError? reason;
}

@immutable
class BannerAdvShowResult {
  const BannerAdvShowResult({this.reason});

  final StickyAdvError? reason;
}

@immutable
class BannerAdvHideResult {
  const BannerAdvHideResult({required this.stickyAdvIsShowing});

  final bool stickyAdvIsShowing;
}

@immutable
class FeedbackAvailability {
  const FeedbackAvailability({required this.value, this.reason});

  final bool value;
  final FeedbackError? reason;
}

@immutable
class FeedbackRequestResult {
  const FeedbackRequestResult({required this.feedbackSent});

  final bool feedbackSent;
}

@immutable
class GameModel {
  const GameModel({
    required this.appId,
    required this.coverUrl,
    required this.iconUrl,
    required this.title,
    required this.url,
  });

  factory GameModel.fromMap(final Map<String, Object?> map) => GameModel(
    appId: (map['appID'] as String?) ?? '',
    coverUrl: (map['coverURL'] as String?) ?? '',
    iconUrl: (map['iconURL'] as String?) ?? '',
    title: (map['title'] as String?) ?? '',
    url: (map['url'] as String?) ?? '',
  );

  final String appId;
  final String coverUrl;
  final String iconUrl;
  final String title;
  final String url;
}

@immutable
class GamesListResult {
  const GamesListResult({required this.developerUrl, required this.games});

  final String developerUrl;
  final List<GameModel> games;
}

@immutable
class GameByIdResult {
  const GameByIdResult({required this.isAvailable, this.game});

  final bool isAvailable;
  final GameModel? game;
}

@immutable
class ProductModel {
  const ProductModel({
    required this.description,
    required this.id,
    required this.imageUri,
    required this.price,
    required this.priceCurrencyCode,
    required this.priceValue,
    required this.title,
  });

  factory ProductModel.fromMap(final Map<String, Object?> map) => ProductModel(
    description: (map['description'] as String?) ?? '',
    id: (map['id'] as String?) ?? '',
    imageUri: (map['imageURI'] as String?) ?? '',
    price: (map['price'] as String?) ?? '',
    priceCurrencyCode: (map['priceCurrencyCode'] as String?) ?? '',
    priceValue: (map['priceValue'] as String?) ?? '',
    title: (map['title'] as String?) ?? '',
  );

  final String description;
  final String id;
  final String imageUri;
  final String price;
  final String priceCurrencyCode;
  final String priceValue;
  final String title;
}

@immutable
class PurchaseModel {
  const PurchaseModel({
    required this.productId,
    required this.purchaseToken,
    this.developerPayload,
  });

  factory PurchaseModel.fromMap(final Map<String, Object?> map) =>
      PurchaseModel(
        productId: (map['productID'] as String?) ?? '',
        purchaseToken: (map['purchaseToken'] as String?) ?? '',
        developerPayload: map['developerPayload'] as String?,
      );

  final String productId;
  final String purchaseToken;
  final String? developerPayload;
}

@immutable
class ShortcutPromptAvailability {
  const ShortcutPromptAvailability({required this.canShow});

  final bool canShow;
}

@immutable
class ShortcutPromptResult {
  const ShortcutPromptResult({required this.outcome});

  final PromptOutcome outcome;
}

enum PromptOutcome {
  accepted('accepted'),
  rejected('rejected'),
  unknownValue('__unknown__');

  const PromptOutcome(this.value);
  final String value;

  static PromptOutcome fromValue(final String? value) {
    for (final item in values) {
      if (item.value == value) {
        return item;
      }
    }
    return unknownValue;
  }
}

@immutable
class LeaderboardDescriptionModel {
  const LeaderboardDescriptionModel({
    required this.appId,
    required this.isDefault,
    required this.name,
    required this.type,
    required this.invertSortOrder,
    required this.decimalOffset,
    required this.title,
  });

  final String appId;
  final bool isDefault;
  final String name;
  final String type;
  final bool invertSortOrder;
  final int decimalOffset;
  final Map<String, String> title;
}

@immutable
class LeaderboardPlayerModel {
  const LeaderboardPlayerModel({
    required this.lang,
    required this.publicName,
    required this.uniqueId,
    required this.scopePermissions,
  });

  final String lang;
  final String publicName;
  final String uniqueId;
  final Map<String, String> scopePermissions;
}

@immutable
class LeaderboardEntryModel {
  const LeaderboardEntryModel({
    this.extraData,
    required this.formattedScore,
    required this.player,
    required this.rank,
    required this.score,
  });

  final String? extraData;
  final String formattedScore;
  final LeaderboardPlayerModel player;
  final int rank;
  final int score;
}

@immutable
class LeaderboardEntriesDataModel {
  const LeaderboardEntriesDataModel({
    required this.entries,
    required this.leaderboard,
    required this.userRank,
  });

  final List<LeaderboardEntryModel> entries;
  final LeaderboardDescriptionModel leaderboard;
  final int userRank;
}

@immutable
class MultiplayerCommitPayloadModel {
  const MultiplayerCommitPayloadModel({required this.data, required this.time});

  final Map<String, Object?> data;
  final int time;

  Map<String, Object?> toJson() => <String, Object?>{
    'data': data,
    'time': time,
  };
}

@immutable
class MultiplayerMetaModel {
  const MultiplayerMetaModel({
    required this.meta1,
    required this.meta2,
    required this.meta3,
  });

  final int meta1;
  final int meta2;
  final int meta3;

  Map<String, Object?> toJson() => <String, Object?>{
    'meta1': meta1,
    'meta2': meta2,
    'meta3': meta3,
  };
}

@immutable
class MultiplayerMetaRangeModel {
  const MultiplayerMetaRangeModel({required this.min, required this.max});

  final int min;
  final int max;

  Map<String, Object?> toJson() => <String, Object?>{'min': min, 'max': max};
}

@immutable
class MultiplayerMetaRangesModel {
  const MultiplayerMetaRangesModel({
    required this.meta1,
    required this.meta2,
    required this.meta3,
  });

  final MultiplayerMetaRangeModel meta1;
  final MultiplayerMetaRangeModel meta2;
  final MultiplayerMetaRangeModel meta3;

  Map<String, Object?> toJson() => <String, Object?>{
    'meta1': meta1.toJson(),
    'meta2': meta2.toJson(),
    'meta3': meta3.toJson(),
  };
}

@immutable
class MultiplayerInitOptionsModel {
  const MultiplayerInitOptionsModel({
    this.count,
    this.isEventBased,
    this.maxOpponentTurnTime,
    this.meta,
  });

  final int? count;
  final bool? isEventBased;
  final int? maxOpponentTurnTime;
  final MultiplayerMetaRangesModel? meta;

  Map<String, Object?> toJson() => <String, Object?>{
    if (count != null) 'count': count,
    if (isEventBased != null) 'isEventBased': isEventBased,
    if (maxOpponentTurnTime != null) 'maxOpponentTurnTime': maxOpponentTurnTime,
    if (meta != null) 'meta': meta!.toJson(),
  };
}

@immutable
class MultiplayerSessionOpponentModel {
  const MultiplayerSessionOpponentModel({
    required this.id,
    required this.meta,
    required this.transactions,
  });

  final String id;
  final MultiplayerMetaModel meta;
  final List<MultiplayerCommitPayloadModel> transactions;
}

@immutable
class CallbackBaseMessageDataModel {
  const CallbackBaseMessageDataModel({
    required this.status,
    this.data,
    this.error,
  });

  final String status;
  final Object? data;
  final String? error;
}

@immutable
class FullscreenAdvCallbacks {
  const FullscreenAdvCallbacks({
    this.onOpen,
    this.onClose,
    this.onOffline,
    this.onError,
  });

  final void Function()? onOpen;
  final void Function(bool wasShown)? onClose;
  final void Function()? onOffline;
  final void Function(Object? error)? onError;
}

@immutable
class RewardedVideoCallbacks {
  const RewardedVideoCallbacks({
    this.onOpen,
    this.onClose,
    this.onRewarded,
    this.onError,
  });

  final void Function()? onOpen;
  final void Function()? onClose;
  final void Function()? onRewarded;
  final void Function(Object? error)? onError;
}
