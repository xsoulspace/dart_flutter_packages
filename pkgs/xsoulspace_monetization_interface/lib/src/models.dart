import 'package:from_json_to_json/from_json_to_json.dart';

/// Extension type that represents a unique identifier for a product.
extension type const PurchaseProductId._(String value) {
  factory PurchaseProductId.fromJson(final dynamic value) =>
      PurchaseProductId._(jsonDecodeString(value));
  String toJson() => value;
  bool get isEmpty => value.isEmpty;
  bool get isNotEmpty => value.isNotEmpty;
  static const empty = PurchaseProductId._('');
}

/// Extension type that represents a unique identifier for a product price.
///
/// Usually one Product has multiple prices.
extension type const PurchasePriceId._(String value) {
  factory PurchasePriceId.fromJson(final dynamic value) =>
      PurchasePriceId._(jsonDecodeString(value));
  String toJson() => value;
  bool get isEmpty => value.isEmpty;
  bool get isNotEmpty => value.isNotEmpty;
  static const empty = PurchasePriceId._('');
}

/// Extension on List<PurchaseProductId> to convert to JSON.
extension ProductListX on List<PurchaseProductId> {
  List<String> toJson() =>
      map((final productId) => productId.toJson()).toList();
}

/// Extension type that represents a unique identifier for a purchase.
extension type const PurchaseId._(String value) {
  factory PurchaseId.fromJson(final dynamic value) =>
      PurchaseId._(jsonDecodeString(value));
  String toJson() => value;
  bool get isEmpty => value.isEmpty;
  bool get isNotEmpty => value.isNotEmpty;
  static const empty = PurchaseId._('');
}

/// Extension type that represents a purchase duration.
extension type const PurchaseDurationModel._(Map<String, dynamic> value) {
  factory PurchaseDurationModel.fromJson(final dynamic json) =>
      PurchaseDurationModel._(jsonDecodeMapAs(json));
  factory PurchaseDurationModel({
    final int years = 0,
    final int months = 0,
    final int days = 0,
  }) =>
      PurchaseDurationModel._({'years': years, 'months': months, 'days': days});
  int get years => jsonDecodeInt(value['years']);
  int get months => jsonDecodeInt(value['months']);
  int get days => jsonDecodeInt(value['days']);
  Map<String, dynamic> toJson() => value;
  static final zero = PurchaseDurationModel();
  bool get isZero => years == 0 && months == 0 && days == 0;
  Duration get duration => Duration(days: days + (months * 30) + (years * 365));
}

/// Enum representing the type of a purchasable product.
enum PurchaseProductType {
  consumable,
  nonConsumable,
  subscription;

  String toJson() => name;
  static PurchaseProductType fromJson(final dynamic value) {
    final str = jsonDecodeString(value);
    return PurchaseProductType.values.firstWhere(
      (e) => e.name == str,
      orElse: () => PurchaseProductType.consumable,
    );
  }
}

/// Extension type that represents the details of a purchasable product.
extension type const PurchaseProductDetailsModel._(Map<String, dynamic> value) {
  factory PurchaseProductDetailsModel.fromJson(final dynamic json) =>
      PurchaseProductDetailsModel._(jsonDecodeMapAs(json));
  factory PurchaseProductDetailsModel({
    required PurchaseDurationModel freeTrialDuration,
    final PurchaseProductId productId = PurchaseProductId.empty,
    final PurchasePriceId priceId = PurchasePriceId.empty,
    final PurchaseProductType productType = PurchaseProductType.consumable,
    final String name = '',
    final String formattedPrice = '',
    final double price = 0,
    final String currency = '',
    final String description = '',
    final Duration duration = Duration.zero,
  }) => PurchaseProductDetailsModel._({
    'productId': productId.toJson(),
    'priceId': priceId.toJson(),
    'productType': productType.toJson(),
    'name': name,
    'formattedPrice': formattedPrice,
    'price': price,
    'currency': currency,
    'description': description,
    'duration': duration.inSeconds,
    'freeTrialDuration': freeTrialDuration.toJson(),
  });
  PurchaseProductId get productId =>
      PurchaseProductId.fromJson(value['productId']);
  PurchasePriceId get priceId => PurchasePriceId.fromJson(value['priceId']);
  PurchaseProductType get productType =>
      PurchaseProductType.fromJson(value['productType']);
  String get name => jsonDecodeString(value['name']);
  String get formattedPrice => jsonDecodeString(value['formattedPrice']);
  double get price => jsonDecodeDouble(value['price']);
  String get currency => jsonDecodeString(value['currency']);
  String get description => jsonDecodeString(value['description']);
  Duration get duration => jsonDecodeDurationInSeconds(value['duration']);
  PurchaseDurationModel get freeTrialDuration =>
      value['freeTrialDuration'] != null
      ? PurchaseDurationModel.fromJson(value['freeTrialDuration'])
      : PurchaseDurationModel.zero;
  Map<String, dynamic> toJson() => value;
  bool get hasFreeTrial => !freeTrialDuration.isZero;
  bool get isOneTimePurchase => duration.inDays == 0;
  bool get isSubscription => !isOneTimePurchase;
  static final empty = PurchaseProductDetailsModel(
    freeTrialDuration: PurchaseDurationModel.zero,
  );
}

/// Extension type that represents the details of a purchase.
///
/// Wraps a Map<String, dynamic> for all purchase details fields.
/// Uses from_json_to_json for type-safe JSON handling.
extension type const PurchaseDetailsModel._(Map<String, dynamic> value) {
  factory PurchaseDetailsModel.fromJson(final dynamic json) =>
      PurchaseDetailsModel._(jsonDecodeMapAs(json));
  factory PurchaseDetailsModel({
    final PurchaseId purchaseId = PurchaseId.empty,
    final PurchaseProductId productId = PurchaseProductId.empty,
    final PurchasePriceId priceId = PurchasePriceId.empty,
    final PurchaseStatus status = PurchaseStatus.pending,
    final PurchaseProductType purchaseType = PurchaseProductType.consumable,
    required final DateTime purchaseDate,
    final Duration freeTrialDuration = Duration.zero,
    final Duration duration = Duration.zero,
    final DateTime? expiryDate,
    final String localVerificationData = '',
    final String serverVerificationData = '',
    final String source = '',
    final String name = '',
    final String formattedPrice = '',
    final double price = 0,
    final String currency = '',
    final String purchaseToken = '',
  }) => PurchaseDetailsModel._({
    'purchaseId': purchaseId.toJson(),
    'productId': productId.toJson(),
    'priceId': priceId.toJson(),
    'status': status.name,
    'purchaseType': purchaseType.name,
    'purchaseDate': purchaseDate.toIso8601String(),
    'freeTrialDuration': freeTrialDuration.inSeconds,
    'duration': duration.inSeconds,
    'expiryDate': expiryDate?.toIso8601String(),
    'localVerificationData': localVerificationData,
    'serverVerificationData': serverVerificationData,
    'source': source,
    'name': name,
    'formattedPrice': formattedPrice,
    'price': price,
    'currency': currency,
    'purchaseToken': purchaseToken,
  });
  PurchaseId get purchaseId => PurchaseId.fromJson(value['purchaseId']);
  PurchaseProductId get productId =>
      PurchaseProductId.fromJson(value['productId']);
  PurchasePriceId get priceId => PurchasePriceId.fromJson(value['priceId']);
  PurchaseStatus get status => PurchaseStatusX.fromJson(value['status']);
  PurchaseProductType get purchaseType =>
      PurchaseProductType.fromJson(value['purchaseType']);
  DateTime get purchaseDate =>
      dateTimeFromIso8601String(jsonDecodeString(value['purchaseDate']))!;
  Duration get freeTrialDuration =>
      jsonDecodeDurationInSeconds(value['freeTrialDuration']);
  Duration get duration => jsonDecodeDurationInSeconds(value['duration']);
  DateTime? get expiryDate =>
      dateTimeFromIso8601String(jsonDecodeString(value['expiryDate']));
  String get localVerificationData =>
      jsonDecodeString(value['localVerificationData']);
  String get serverVerificationData =>
      jsonDecodeString(value['serverVerificationData']);
  String get source => jsonDecodeString(value['source']);
  String get name => jsonDecodeString(value['name']);
  String get formattedPrice => jsonDecodeString(value['formattedPrice']);
  double get price => jsonDecodeDouble(value['price']);
  String get currency => jsonDecodeString(value['currency']);
  String get purchaseToken => jsonDecodeString(value['purchaseToken']);
  Map<String, dynamic> toJson() => value;
  bool get hasFreeTrial => freeTrialDuration.inDays > 0;
  bool get isOneTimePurchase => duration.inDays == 0;
  bool get isSubscription => !isOneTimePurchase;
  bool get isPending => status == PurchaseStatus.pending;
  bool get isActive {
    if (purchaseType case PurchaseProductType.subscription) {
      final expiry = expiryDate;
      return status == PurchaseStatus.purchased &&
          expiry != null &&
          expiry.isAfter(DateTime.now());
    }
    return status == PurchaseStatus.purchased;
  }

  PurchaseVerificationDtoModel toVerificationDto() =>
      PurchaseVerificationDtoModel(
        transactionDate: purchaseDate,
        purchaseId: purchaseId,
        productId: productId,
        status: status,
        productType: purchaseType,
        purchaseToken: purchaseToken,
        localVerificationData: localVerificationData,
        serverVerificationData: serverVerificationData,
        source: source,
      );
  static final empty = PurchaseDetailsModel(purchaseDate: DateTime.now());
}

/// Enum representing the status of a purchase.

enum PurchaseStatus {
  pending,
  purchased,
  error,

  /// The purchase has been restored to the device and
  /// pending server validation.
  ///
  /// You should validate the purchase and if valid deliver the content.
  /// Once the content has been delivered or if the receipt is invalid
  /// you should finish the purchase by calling the completePurchase method.
  restored,
  canceled;

  String toJson() => name;
}

/// Helper for PurchaseStatus enum JSON decode.
extension PurchaseStatusX on PurchaseStatus {
  static PurchaseStatus fromJson(final dynamic value) {
    final str = jsonDecodeString(value);
    return PurchaseStatus.values.firstWhere(
      (e) => e.name == str,
      orElse: () => PurchaseStatus.pending,
    );
  }
}

/// Extension type that represents the result of a purchase operation.
///
/// Wraps a Map<String, dynamic> for result fields.
/// Uses from_json_to_json for type-safe JSON handling.
extension type const PurchaseResultModel._(Map<String, dynamic> value) {
  factory PurchaseResultModel.fromJson(final dynamic json) =>
      PurchaseResultModel._(jsonDecodeMapAs(json));
  factory PurchaseResultModel({
    PurchaseDetailsModel? details,
    final ResultType type = ResultType.success,
    final String? error,
  }) => PurchaseResultModel._({
    'type': type.name,
    'details': details?.toJson(),
    'error': error,
  });
  factory PurchaseResultModel.success(final PurchaseDetailsModel details) =>
      PurchaseResultModel(details: details, type: ResultType.success);
  factory PurchaseResultModel.failure(final String error) =>
      PurchaseResultModel(error: error, type: ResultType.failure);
  bool get isSuccess => value['type'] == ResultType.success.name;
  ResultType get type => ResultType.values.firstWhere(
    (e) => e.name == jsonDecodeString(value['type']),
    orElse: () => ResultType.failure,
  );
  PurchaseDetailsModel? get details =>
      isSuccess ? PurchaseDetailsModel.fromJson(value['details']) : null;
  String get error => !isSuccess ? jsonDecodeString(value['error']) : '';
  Map<String, dynamic> toJson() => value;
  static final empty = PurchaseResultModel(details: PurchaseDetailsModel.empty);
}

/// Extension type that represents the result of a restore operation.
///
/// Wraps a Map<String, dynamic> for result fields.
/// Uses from_json_to_json for type-safe JSON handling.
extension type const RestoreResultModel._(Map<String, dynamic> value) {
  factory RestoreResultModel.fromJson(final dynamic json) =>
      RestoreResultModel._(jsonDecodeMapAs(json));
  factory RestoreResultModel({
    final List<PurchaseDetailsModel> restoredPurchases = const [],
    final ResultType type = ResultType.success,
    final String? error,
  }) => RestoreResultModel._({
    'type': type.name,
    'restoredPurchases': restoredPurchases
        .map((final p) => p.toJson())
        .toList(),
    'error': error,
  });
  factory RestoreResultModel.success(
    final List<PurchaseDetailsModel> restoredPurchases,
  ) => RestoreResultModel(
    restoredPurchases: restoredPurchases,
    type: ResultType.success,
  );
  factory RestoreResultModel.failure(final String error) =>
      RestoreResultModel(error: error, type: ResultType.failure);
  bool get isSuccess => value['type'] == ResultType.success.name;
  ResultType get type => ResultType.values.firstWhere(
    (e) => e.name == jsonDecodeString(value['type']),
    orElse: () => ResultType.failure,
  );

  List<PurchaseDetailsModel> get restoredPurchases => isSuccess
      ? jsonDecodeListAs<Map<String, dynamic>>(
          value['restoredPurchases'],
        ).map(PurchaseDetailsModel.fromJson).toList()
      : [];
  String get error => !isSuccess ? jsonDecodeString(value['error']) : '';
  Map<String, dynamic> toJson() => value;
  static final empty = RestoreResultModel();
}

/// Common result type for all operations.
enum ResultType { success, failure }

/// Extension type that represents the result of a cancellation operation.
///
/// Wraps a Map<String, dynamic> for result fields.
/// Uses from_json_to_json for type-safe JSON handling.
extension type const CancelResultModel._(Map<String, dynamic> value) {
  factory CancelResultModel.fromJson(final dynamic json) =>
      CancelResultModel._(jsonDecodeMapAs(json));
  factory CancelResultModel({
    final ResultType type = ResultType.success,
    final String? error,
  }) => CancelResultModel._({'type': type.name, 'error': error});
  factory CancelResultModel.success() =>
      CancelResultModel(type: ResultType.success);
  factory CancelResultModel.failure(final String error) =>
      CancelResultModel(error: error, type: ResultType.failure);
  bool get isSuccess => value['type'] == ResultType.success.name;
  ResultType get type => ResultType.values.firstWhere(
    (e) => e.name == jsonDecodeString(value['type']),
    orElse: () => ResultType.failure,
  );
  String get error => !isSuccess ? jsonDecodeString(value['error']) : '';
  Map<String, dynamic> toJson() => value;
  static final empty = CancelResultModel();
}

/// Extension type that represents the result of completing a purchase.
///
/// Wraps a Map<String, dynamic> for result fields.
/// Uses from_json_to_json for type-safe JSON handling.
extension type const CompletePurchaseResultModel._(Map<String, dynamic> value) {
  factory CompletePurchaseResultModel.fromJson(final dynamic json) =>
      CompletePurchaseResultModel._(jsonDecodeMapAs(json));
  factory CompletePurchaseResultModel({
    final ResultType type = ResultType.success,
    final String? error,
  }) => CompletePurchaseResultModel._({'type': type.name, 'error': error});
  factory CompletePurchaseResultModel.success() =>
      CompletePurchaseResultModel(type: ResultType.success);
  factory CompletePurchaseResultModel.failure(final String error) =>
      CompletePurchaseResultModel(error: error, type: ResultType.failure);
  bool get isSuccess => value['type'] == ResultType.success.name;
  ResultType get type => ResultType.values.firstWhere(
    (e) => e.name == jsonDecodeString(value['type']),
    orElse: () => ResultType.failure,
  );
  String get error => !isSuccess ? jsonDecodeString(value['error']) : '';
  Map<String, dynamic> toJson() => value;
  static final empty = CompletePurchaseResultModel();
}

/// Extension type that represents a DTO for purchase verification.
///
/// Wraps a Map<String, dynamic> for all DTO fields.
/// Uses from_json_to_json for type-safe JSON handling.
extension type const PurchaseVerificationDtoModel._(
  Map<String, dynamic> value
) {
  factory PurchaseVerificationDtoModel.fromJson(final dynamic json) =>
      PurchaseVerificationDtoModel._(jsonDecodeMapAs(json));
  factory PurchaseVerificationDtoModel({
    required final DateTime transactionDate,
    final PurchaseId purchaseId = PurchaseId.empty,
    final PurchaseProductId productId = PurchaseProductId.empty,
    final PurchasePriceId priceId = PurchasePriceId.empty,
    final PurchaseStatus status = PurchaseStatus.pending,
    final PurchaseProductType productType = PurchaseProductType.consumable,
    final String purchaseToken = '',
    final String? localVerificationData,
    final String? serverVerificationData,
    final String? source,
  }) => PurchaseVerificationDtoModel._({
    'purchaseId': purchaseId.toJson(),
    'productId': productId.toJson(),
    'priceId': priceId.toJson(),
    'status': status.name,
    'productType': productType.name,
    'transactionDate': transactionDate.toIso8601String(),
    'purchaseToken': purchaseToken,
    'localVerificationData': localVerificationData,
    'serverVerificationData': serverVerificationData,
    'source': source,
  });
  PurchaseId get purchaseId => PurchaseId.fromJson(value['purchaseId']);
  PurchaseProductId get productId =>
      PurchaseProductId.fromJson(value['productId']);
  PurchasePriceId get priceId => PurchasePriceId.fromJson(value['priceId']);
  PurchaseStatus get status => PurchaseStatusX.fromJson(value['status']);
  PurchaseProductType get productType =>
      PurchaseProductType.fromJson(value['productType']);
  DateTime? get transactionDate =>
      dateTimeFromIso8601String(jsonDecodeString(value['transactionDate']));
  String? get purchaseToken => jsonDecodeString(value['purchaseToken']);
  String? get localVerificationData =>
      jsonDecodeString(value['localVerificationData']);
  String? get serverVerificationData =>
      jsonDecodeString(value['serverVerificationData']);
  String? get source => jsonDecodeString(value['source']);
  Map<String, dynamic> toJson() => value;
  static final empty = PurchaseVerificationDtoModel(
    transactionDate: DateTime.now(),
  );
}
