// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_PurchaseDuration _$PurchaseDurationFromJson(Map<String, dynamic> json) =>
    _PurchaseDuration(
      years: (json['years'] as num?)?.toInt() ?? 0,
      months: (json['months'] as num?)?.toInt() ?? 0,
      days: (json['days'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$PurchaseDurationToJson(_PurchaseDuration instance) =>
    <String, dynamic>{
      'years': instance.years,
      'months': instance.months,
      'days': instance.days,
    };

_PurchaseProductDetails _$PurchaseProductDetailsFromJson(
  Map<String, dynamic> json,
) => _PurchaseProductDetails(
  productId: PurchaseProductId.fromJson(json['productId']),
  productType: $enumDecode(_$PurchaseProductTypeEnumMap, json['productType']),
  name: json['name'] as String,
  formattedPrice: json['formattedPrice'] as String,
  price: (json['price'] as num).toDouble(),
  currency: json['currency'] as String,
  description: json['description'] as String? ?? '',
  duration: json['duration'] == null
      ? Duration.zero
      : Duration(microseconds: (json['duration'] as num).toInt()),
  freeTrialDuration: json['freeTrialDuration'] == null
      ? PurchaseDuration.zero
      : PurchaseDuration.fromJson(
          json['freeTrialDuration'] as Map<String, dynamic>,
        ),
);

Map<String, dynamic> _$PurchaseProductDetailsToJson(
  _PurchaseProductDetails instance,
) => <String, dynamic>{
  'productId': instance.productId,
  'productType': instance.productType,
  'name': instance.name,
  'formattedPrice': instance.formattedPrice,
  'price': instance.price,
  'currency': instance.currency,
  'description': instance.description,
  'duration': instance.duration.inMicroseconds,
  'freeTrialDuration': instance.freeTrialDuration,
};

const _$PurchaseProductTypeEnumMap = {
  PurchaseProductType.consumable: 'consumable',
  PurchaseProductType.nonConsumable: 'nonConsumable',
  PurchaseProductType.subscription: 'subscription',
};

_PurchaseDetails _$PurchaseDetailsFromJson(Map<String, dynamic> json) =>
    _PurchaseDetails(
      purchaseId: PurchaseId.fromJson(json['purchaseId']),
      productId: PurchaseProductId.fromJson(json['productId']),
      name: json['name'] as String,
      formattedPrice: json['formattedPrice'] as String,
      status: $enumDecode(_$PurchaseStatusEnumMap, json['status']),
      price: (json['price'] as num).toDouble(),
      currency: json['currency'] as String,
      purchaseDate: DateTime.parse(json['purchaseDate'] as String),
      purchaseType: $enumDecode(
        _$PurchaseProductTypeEnumMap,
        json['purchaseType'],
      ),
      freeTrialDuration: json['freeTrialDuration'] == null
          ? Duration.zero
          : Duration(microseconds: (json['freeTrialDuration'] as num).toInt()),
      duration: json['duration'] == null
          ? Duration.zero
          : Duration(microseconds: (json['duration'] as num).toInt()),
      expiryDate: json['expiryDate'] == null
          ? null
          : DateTime.parse(json['expiryDate'] as String),
      localVerificationData: json['localVerificationData'] as String?,
      serverVerificationData: json['serverVerificationData'] as String?,
      source: json['source'] as String?,
    );

Map<String, dynamic> _$PurchaseDetailsToJson(_PurchaseDetails instance) =>
    <String, dynamic>{
      'purchaseId': instance.purchaseId,
      'productId': instance.productId,
      'name': instance.name,
      'formattedPrice': instance.formattedPrice,
      'status': _$PurchaseStatusEnumMap[instance.status]!,
      'price': instance.price,
      'currency': instance.currency,
      'purchaseDate': instance.purchaseDate.toIso8601String(),
      'purchaseType': instance.purchaseType,
      'freeTrialDuration': instance.freeTrialDuration.inMicroseconds,
      'duration': instance.duration.inMicroseconds,
      'expiryDate': instance.expiryDate?.toIso8601String(),
      'localVerificationData': instance.localVerificationData,
      'serverVerificationData': instance.serverVerificationData,
      'source': instance.source,
    };

const _$PurchaseStatusEnumMap = {
  PurchaseStatus.pending: 'pending',
  PurchaseStatus.purchased: 'purchased',
  PurchaseStatus.error: 'error',
  PurchaseStatus.restored: 'restored',
  PurchaseStatus.canceled: 'canceled',
};

PurchaseSuccess _$PurchaseSuccessFromJson(Map<String, dynamic> json) =>
    PurchaseSuccess(
      PurchaseDetails.fromJson(json['details'] as Map<String, dynamic>),
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$PurchaseSuccessToJson(PurchaseSuccess instance) =>
    <String, dynamic>{
      'details': instance.details,
      'runtimeType': instance.$type,
    };

PurchaseFailure _$PurchaseFailureFromJson(Map<String, dynamic> json) =>
    PurchaseFailure(
      json['error'] as String,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$PurchaseFailureToJson(PurchaseFailure instance) =>
    <String, dynamic>{'error': instance.error, 'runtimeType': instance.$type};

RestoreSuccess _$RestoreSuccessFromJson(Map<String, dynamic> json) =>
    RestoreSuccess(
      (json['restoredPurchases'] as List<dynamic>)
          .map((e) => PurchaseDetails.fromJson(e as Map<String, dynamic>))
          .toList(),
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$RestoreSuccessToJson(RestoreSuccess instance) =>
    <String, dynamic>{
      'restoredPurchases': instance.restoredPurchases,
      'runtimeType': instance.$type,
    };

RestoreFailure _$RestoreFailureFromJson(Map<String, dynamic> json) =>
    RestoreFailure(
      json['error'] as String,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$RestoreFailureToJson(RestoreFailure instance) =>
    <String, dynamic>{'error': instance.error, 'runtimeType': instance.$type};

CancelSuccess _$CancelSuccessFromJson(Map<String, dynamic> json) =>
    CancelSuccess($type: json['runtimeType'] as String?);

Map<String, dynamic> _$CancelSuccessToJson(CancelSuccess instance) =>
    <String, dynamic>{'runtimeType': instance.$type};

CancelFailure _$CancelFailureFromJson(Map<String, dynamic> json) =>
    CancelFailure(
      json['error'] as String,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$CancelFailureToJson(CancelFailure instance) =>
    <String, dynamic>{'error': instance.error, 'runtimeType': instance.$type};

CompletePurchaseSuccess _$CompletePurchaseSuccessFromJson(
  Map<String, dynamic> json,
) => CompletePurchaseSuccess($type: json['runtimeType'] as String?);

Map<String, dynamic> _$CompletePurchaseSuccessToJson(
  CompletePurchaseSuccess instance,
) => <String, dynamic>{'runtimeType': instance.$type};

CompletePurchaseFailure _$CompletePurchaseFailureFromJson(
  Map<String, dynamic> json,
) => CompletePurchaseFailure(
  json['error'] as String,
  $type: json['runtimeType'] as String?,
);

Map<String, dynamic> _$CompletePurchaseFailureToJson(
  CompletePurchaseFailure instance,
) => <String, dynamic>{'error': instance.error, 'runtimeType': instance.$type};

_PurchaseVerificationDto _$PurchaseVerificationDtoFromJson(
  Map<String, dynamic> json,
) => _PurchaseVerificationDto(
  purchaseId: PurchaseId.fromJson(json['purchaseId']),
  productId: PurchaseProductId.fromJson(json['productId']),
  status: $enumDecode(_$PurchaseStatusEnumMap, json['status']),
  productType: $enumDecode(_$PurchaseProductTypeEnumMap, json['productType']),
  transactionDate: json['transactionDate'] == null
      ? null
      : DateTime.parse(json['transactionDate'] as String),
  purchaseToken: json['purchaseToken'] as String?,
  localVerificationData: json['localVerificationData'] as String?,
  serverVerificationData: json['serverVerificationData'] as String?,
  source: json['source'] as String?,
);

Map<String, dynamic> _$PurchaseVerificationDtoToJson(
  _PurchaseVerificationDto instance,
) => <String, dynamic>{
  'purchaseId': instance.purchaseId,
  'productId': instance.productId,
  'status': _$PurchaseStatusEnumMap[instance.status]!,
  'productType': instance.productType,
  'transactionDate': instance.transactionDate?.toIso8601String(),
  'purchaseToken': instance.purchaseToken,
  'localVerificationData': instance.localVerificationData,
  'serverVerificationData': instance.serverVerificationData,
  'source': instance.source,
};
