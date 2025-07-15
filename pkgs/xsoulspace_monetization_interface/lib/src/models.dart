import 'package:freezed_annotation/freezed_annotation.dart';

part 'models.freezed.dart';
part 'models.g.dart';

/// {@template product_id}
/// Represents a unique identifier for a product.
/// {@endtemplate}
extension type PurchaseProductId(String value) {
  factory PurchaseProductId.fromJson(final dynamic json) =>
      PurchaseProductId(json.toString());
  String toJson() => value;
}

/// {@template product_list_x}
/// Extension on List<ProductId> to convert to JSON.
/// {@endtemplate}
extension ProductListX on List<PurchaseProductId> {
  List<String> toJson() =>
      map((final productId) => productId.toJson()).toSet().toList();
}

/// {@template purchase_id}
/// Represents a unique identifier for a purchase.
/// {@endtemplate}
extension type PurchaseId(String value) {
  factory PurchaseId.fromJson(final dynamic json) =>
      PurchaseId(json.toString());
  String toJson() => value;
}

@Freezed()
class PurchaseDuration with _$PurchaseDuration {
  const factory PurchaseDuration({
    @Default(0) final int years,
    @Default(0) final int months,
    @Default(0) final int days,
  }) = _PurchaseDuration;
  factory PurchaseDuration.fromJson(final Map<String, dynamic> json) =>
      _$PurchaseDurationFromJson(json);
  const PurchaseDuration._();
  static const zero = PurchaseDuration();
  bool get isZero => years == 0 && months == 0 && days == 0;
  Duration get duration => Duration(days: days + (months * 30) + (years * 365));
}

/// {@template purchase_product_type}
/// Represents the type of a purchasable product.
/// {@endtemplate}
enum PurchaseProductType {
  consumable,
  nonConsumable,
  subscription;

  String toJson() => name;
}

/// {@template purchase_product_details}
/// Represents the details of a purchasable product.
/// {@endtemplate}
@freezed
class PurchaseProductDetails with _$PurchaseProductDetails {
  const factory PurchaseProductDetails({
    required final PurchaseProductId productId,
    required final PurchaseProductType productType,
    required final String name,

    /// formatted price with currency
    required final String formattedPrice,

    /// price without currency in smallest unit of currency
    required final double price,
    required final String currency,
    @Default('') final String description,
    @Default(Duration.zero) final Duration duration,
    @Default(PurchaseDuration.zero) final PurchaseDuration freeTrialDuration,
  }) = _PurchaseProductDetails;
  const PurchaseProductDetails._();
  factory PurchaseProductDetails.fromJson(final Map<String, dynamic> json) =>
      _$PurchaseProductDetailsFromJson(json);
  bool get hasFreeTrial => !freeTrialDuration.isZero;
  bool get isOneTimePurchase => duration.inDays == 0;
  bool get isSubscription => !isOneTimePurchase;
}

/// {@template purchase_details}
/// Represents the details of a purchase.
/// {@endtemplate}
@freezed
class PurchaseDetails with _$PurchaseDetails {
  const factory PurchaseDetails({
    required final PurchaseId purchaseId,
    required final PurchaseProductId productId,
    required final String name,

    /// formatted price with currency
    required final String formattedPrice,
    required final PurchaseStatus status,

    /// price without currency in smallest unit of currency
    required final double price,
    required final String currency,
    required final DateTime purchaseDate,
    required final PurchaseProductType purchaseType,
    @Default(Duration.zero) final Duration freeTrialDuration,
    @Default(Duration.zero) final Duration duration,
    final DateTime? expiryDate,
    final String? localVerificationData,
    final String? serverVerificationData,
    final String? source,
  }) = _PurchaseDetails;
  const PurchaseDetails._();
  factory PurchaseDetails.fromJson(final Map<String, dynamic> json) =>
      _$PurchaseDetailsFromJson(json);

  PurchaseVerificationDto toVerificationDto() => PurchaseVerificationDto(
    purchaseId: purchaseId,
    productId: productId,
    status: status,
    productType: purchaseType,
    localVerificationData: localVerificationData,
    serverVerificationData: serverVerificationData,
    source: source,
  );
  bool get hasFreeTrial => freeTrialDuration.inDays > 0;
  bool get isOneTimePurchase => duration.inDays == 0;
  bool get isSubscription => !isOneTimePurchase;
  bool get isPending => status == PurchaseStatus.pending;
  bool get isActive {
    if (purchaseType case PurchaseProductType.subscription) {
      final expiryDate = this.expiryDate;
      return status == PurchaseStatus.purchased &&
          expiryDate != null &&
          expiryDate.isAfter(DateTime.now());
    }
    return status == PurchaseStatus.purchased;
  }
}

/// {@template purchase_result}
/// Represents the result of a purchase operation.
/// {@endtemplate}
@freezed
class PurchaseResult with _$PurchaseResult {
  const factory PurchaseResult.success(final PurchaseDetails details) =
      PurchaseSuccess;
  const factory PurchaseResult.failure(final String error) = PurchaseFailure;

  factory PurchaseResult.fromJson(final Map<String, dynamic> json) =>
      _$PurchaseResultFromJson(json);
}

/// {@template purchase_status}
/// Represents the status of a purchase.
/// {@endtemplate}
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
  canceled,
}

/// {@template restore_result}
/// Represents the result of a restore operation.
/// {@endtemplate}
@freezed
class RestoreResult with _$RestoreResult {
  const factory RestoreResult.success(
    final List<PurchaseDetails> restoredPurchases,
  ) = RestoreSuccess;
  const factory RestoreResult.failure(final String error) = RestoreFailure;

  factory RestoreResult.fromJson(final Map<String, dynamic> json) =>
      _$RestoreResultFromJson(json);
}

/// {@template cancel_result}
/// Represents the result of a cancellation operation.
/// {@endtemplate}
@freezed
class CancelResult with _$CancelResult {
  const factory CancelResult.success() = CancelSuccess;
  const factory CancelResult.failure(final String error) = CancelFailure;

  factory CancelResult.fromJson(final Map<String, dynamic> json) =>
      _$CancelResultFromJson(json);
}

/// {@template complete_purchase_result}
/// Represents the result of completing a purchase.
/// {@endtemplate}
@freezed
class CompletePurchaseResult with _$CompletePurchaseResult {
  const factory CompletePurchaseResult.success() = CompletePurchaseSuccess;
  const factory CompletePurchaseResult.failure(final String error) =
      CompletePurchaseFailure;

  factory CompletePurchaseResult.fromJson(final Map<String, dynamic> json) =>
      _$CompletePurchaseResultFromJson(json);
}

/// {@template complete_purchase_dto}
/// Data Transfer Object for completing a purchase.
/// {@endtemplate}
@freezed
class PurchaseVerificationDto with _$PurchaseVerificationDto {
  const factory PurchaseVerificationDto({
    required final PurchaseId purchaseId,
    required final PurchaseProductId productId,
    required final PurchaseStatus status,
    required final PurchaseProductType productType,
    final DateTime? transactionDate,
    final String? purchaseToken,
    final String? localVerificationData,
    final String? serverVerificationData,
    final String? source,
  }) = _PurchaseVerificationDto;

  factory PurchaseVerificationDto.fromJson(final Map<String, dynamic> json) =>
      _$PurchaseVerificationDtoFromJson(json);
}
