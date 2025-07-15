// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$PurchaseDuration {

 int get years; int get months; int get days;
/// Create a copy of PurchaseDuration
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PurchaseDurationCopyWith<PurchaseDuration> get copyWith => _$PurchaseDurationCopyWithImpl<PurchaseDuration>(this as PurchaseDuration, _$identity);

  /// Serializes this PurchaseDuration to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PurchaseDuration&&(identical(other.years, years) || other.years == years)&&(identical(other.months, months) || other.months == months)&&(identical(other.days, days) || other.days == days));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,years,months,days);

@override
String toString() {
  return 'PurchaseDuration(years: $years, months: $months, days: $days)';
}


}

/// @nodoc
abstract mixin class $PurchaseDurationCopyWith<$Res>  {
  factory $PurchaseDurationCopyWith(PurchaseDuration value, $Res Function(PurchaseDuration) _then) = _$PurchaseDurationCopyWithImpl;
@useResult
$Res call({
 int years, int months, int days
});




}
/// @nodoc
class _$PurchaseDurationCopyWithImpl<$Res>
    implements $PurchaseDurationCopyWith<$Res> {
  _$PurchaseDurationCopyWithImpl(this._self, this._then);

  final PurchaseDuration _self;
  final $Res Function(PurchaseDuration) _then;

/// Create a copy of PurchaseDuration
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? years = null,Object? months = null,Object? days = null,}) {
  return _then(_self.copyWith(
years: null == years ? _self.years : years // ignore: cast_nullable_to_non_nullable
as int,months: null == months ? _self.months : months // ignore: cast_nullable_to_non_nullable
as int,days: null == days ? _self.days : days // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [PurchaseDuration].
extension PurchaseDurationPatterns on PurchaseDuration {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PurchaseDuration value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PurchaseDuration() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PurchaseDuration value)  $default,){
final _that = this;
switch (_that) {
case _PurchaseDuration():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PurchaseDuration value)?  $default,){
final _that = this;
switch (_that) {
case _PurchaseDuration() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int years,  int months,  int days)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PurchaseDuration() when $default != null:
return $default(_that.years,_that.months,_that.days);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int years,  int months,  int days)  $default,) {final _that = this;
switch (_that) {
case _PurchaseDuration():
return $default(_that.years,_that.months,_that.days);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int years,  int months,  int days)?  $default,) {final _that = this;
switch (_that) {
case _PurchaseDuration() when $default != null:
return $default(_that.years,_that.months,_that.days);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PurchaseDuration extends PurchaseDuration {
  const _PurchaseDuration({this.years = 0, this.months = 0, this.days = 0}): super._();
  factory _PurchaseDuration.fromJson(Map<String, dynamic> json) => _$PurchaseDurationFromJson(json);

@override@JsonKey() final  int years;
@override@JsonKey() final  int months;
@override@JsonKey() final  int days;

/// Create a copy of PurchaseDuration
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PurchaseDurationCopyWith<_PurchaseDuration> get copyWith => __$PurchaseDurationCopyWithImpl<_PurchaseDuration>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PurchaseDurationToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PurchaseDuration&&(identical(other.years, years) || other.years == years)&&(identical(other.months, months) || other.months == months)&&(identical(other.days, days) || other.days == days));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,years,months,days);

@override
String toString() {
  return 'PurchaseDuration(years: $years, months: $months, days: $days)';
}


}

/// @nodoc
abstract mixin class _$PurchaseDurationCopyWith<$Res> implements $PurchaseDurationCopyWith<$Res> {
  factory _$PurchaseDurationCopyWith(_PurchaseDuration value, $Res Function(_PurchaseDuration) _then) = __$PurchaseDurationCopyWithImpl;
@override @useResult
$Res call({
 int years, int months, int days
});




}
/// @nodoc
class __$PurchaseDurationCopyWithImpl<$Res>
    implements _$PurchaseDurationCopyWith<$Res> {
  __$PurchaseDurationCopyWithImpl(this._self, this._then);

  final _PurchaseDuration _self;
  final $Res Function(_PurchaseDuration) _then;

/// Create a copy of PurchaseDuration
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? years = null,Object? months = null,Object? days = null,}) {
  return _then(_PurchaseDuration(
years: null == years ? _self.years : years // ignore: cast_nullable_to_non_nullable
as int,months: null == months ? _self.months : months // ignore: cast_nullable_to_non_nullable
as int,days: null == days ? _self.days : days // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}


/// @nodoc
mixin _$PurchaseProductDetails {

 PurchaseProductId get productId; PurchaseProductType get productType; String get name;/// formatted price with currency
 String get formattedPrice;/// price without currency in smallest unit of currency
 double get price; String get currency; String get description; Duration get duration; PurchaseDuration get freeTrialDuration;
/// Create a copy of PurchaseProductDetails
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PurchaseProductDetailsCopyWith<PurchaseProductDetails> get copyWith => _$PurchaseProductDetailsCopyWithImpl<PurchaseProductDetails>(this as PurchaseProductDetails, _$identity);

  /// Serializes this PurchaseProductDetails to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PurchaseProductDetails&&(identical(other.productId, productId) || other.productId == productId)&&(identical(other.productType, productType) || other.productType == productType)&&(identical(other.name, name) || other.name == name)&&(identical(other.formattedPrice, formattedPrice) || other.formattedPrice == formattedPrice)&&(identical(other.price, price) || other.price == price)&&(identical(other.currency, currency) || other.currency == currency)&&(identical(other.description, description) || other.description == description)&&(identical(other.duration, duration) || other.duration == duration)&&(identical(other.freeTrialDuration, freeTrialDuration) || other.freeTrialDuration == freeTrialDuration));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,productId,productType,name,formattedPrice,price,currency,description,duration,freeTrialDuration);

@override
String toString() {
  return 'PurchaseProductDetails(productId: $productId, productType: $productType, name: $name, formattedPrice: $formattedPrice, price: $price, currency: $currency, description: $description, duration: $duration, freeTrialDuration: $freeTrialDuration)';
}


}

/// @nodoc
abstract mixin class $PurchaseProductDetailsCopyWith<$Res>  {
  factory $PurchaseProductDetailsCopyWith(PurchaseProductDetails value, $Res Function(PurchaseProductDetails) _then) = _$PurchaseProductDetailsCopyWithImpl;
@useResult
$Res call({
 PurchaseProductId productId, PurchaseProductType productType, String name, String formattedPrice, double price, String currency, String description, Duration duration, PurchaseDuration freeTrialDuration
});


$PurchaseDurationCopyWith<$Res> get freeTrialDuration;

}
/// @nodoc
class _$PurchaseProductDetailsCopyWithImpl<$Res>
    implements $PurchaseProductDetailsCopyWith<$Res> {
  _$PurchaseProductDetailsCopyWithImpl(this._self, this._then);

  final PurchaseProductDetails _self;
  final $Res Function(PurchaseProductDetails) _then;

/// Create a copy of PurchaseProductDetails
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? productId = null,Object? productType = null,Object? name = null,Object? formattedPrice = null,Object? price = null,Object? currency = null,Object? description = null,Object? duration = null,Object? freeTrialDuration = null,}) {
  return _then(_self.copyWith(
productId: null == productId ? _self.productId : productId // ignore: cast_nullable_to_non_nullable
as PurchaseProductId,productType: null == productType ? _self.productType : productType // ignore: cast_nullable_to_non_nullable
as PurchaseProductType,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,formattedPrice: null == formattedPrice ? _self.formattedPrice : formattedPrice // ignore: cast_nullable_to_non_nullable
as String,price: null == price ? _self.price : price // ignore: cast_nullable_to_non_nullable
as double,currency: null == currency ? _self.currency : currency // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,duration: null == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as Duration,freeTrialDuration: null == freeTrialDuration ? _self.freeTrialDuration : freeTrialDuration // ignore: cast_nullable_to_non_nullable
as PurchaseDuration,
  ));
}
/// Create a copy of PurchaseProductDetails
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PurchaseDurationCopyWith<$Res> get freeTrialDuration {
  
  return $PurchaseDurationCopyWith<$Res>(_self.freeTrialDuration, (value) {
    return _then(_self.copyWith(freeTrialDuration: value));
  });
}
}


/// Adds pattern-matching-related methods to [PurchaseProductDetails].
extension PurchaseProductDetailsPatterns on PurchaseProductDetails {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PurchaseProductDetails value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PurchaseProductDetails() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PurchaseProductDetails value)  $default,){
final _that = this;
switch (_that) {
case _PurchaseProductDetails():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PurchaseProductDetails value)?  $default,){
final _that = this;
switch (_that) {
case _PurchaseProductDetails() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( PurchaseProductId productId,  PurchaseProductType productType,  String name,  String formattedPrice,  double price,  String currency,  String description,  Duration duration,  PurchaseDuration freeTrialDuration)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PurchaseProductDetails() when $default != null:
return $default(_that.productId,_that.productType,_that.name,_that.formattedPrice,_that.price,_that.currency,_that.description,_that.duration,_that.freeTrialDuration);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( PurchaseProductId productId,  PurchaseProductType productType,  String name,  String formattedPrice,  double price,  String currency,  String description,  Duration duration,  PurchaseDuration freeTrialDuration)  $default,) {final _that = this;
switch (_that) {
case _PurchaseProductDetails():
return $default(_that.productId,_that.productType,_that.name,_that.formattedPrice,_that.price,_that.currency,_that.description,_that.duration,_that.freeTrialDuration);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( PurchaseProductId productId,  PurchaseProductType productType,  String name,  String formattedPrice,  double price,  String currency,  String description,  Duration duration,  PurchaseDuration freeTrialDuration)?  $default,) {final _that = this;
switch (_that) {
case _PurchaseProductDetails() when $default != null:
return $default(_that.productId,_that.productType,_that.name,_that.formattedPrice,_that.price,_that.currency,_that.description,_that.duration,_that.freeTrialDuration);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PurchaseProductDetails extends PurchaseProductDetails {
  const _PurchaseProductDetails({required this.productId, required this.productType, required this.name, required this.formattedPrice, required this.price, required this.currency, this.description = '', this.duration = Duration.zero, this.freeTrialDuration = PurchaseDuration.zero}): super._();
  factory _PurchaseProductDetails.fromJson(Map<String, dynamic> json) => _$PurchaseProductDetailsFromJson(json);

@override final  PurchaseProductId productId;
@override final  PurchaseProductType productType;
@override final  String name;
/// formatted price with currency
@override final  String formattedPrice;
/// price without currency in smallest unit of currency
@override final  double price;
@override final  String currency;
@override@JsonKey() final  String description;
@override@JsonKey() final  Duration duration;
@override@JsonKey() final  PurchaseDuration freeTrialDuration;

/// Create a copy of PurchaseProductDetails
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PurchaseProductDetailsCopyWith<_PurchaseProductDetails> get copyWith => __$PurchaseProductDetailsCopyWithImpl<_PurchaseProductDetails>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PurchaseProductDetailsToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PurchaseProductDetails&&(identical(other.productId, productId) || other.productId == productId)&&(identical(other.productType, productType) || other.productType == productType)&&(identical(other.name, name) || other.name == name)&&(identical(other.formattedPrice, formattedPrice) || other.formattedPrice == formattedPrice)&&(identical(other.price, price) || other.price == price)&&(identical(other.currency, currency) || other.currency == currency)&&(identical(other.description, description) || other.description == description)&&(identical(other.duration, duration) || other.duration == duration)&&(identical(other.freeTrialDuration, freeTrialDuration) || other.freeTrialDuration == freeTrialDuration));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,productId,productType,name,formattedPrice,price,currency,description,duration,freeTrialDuration);

@override
String toString() {
  return 'PurchaseProductDetails(productId: $productId, productType: $productType, name: $name, formattedPrice: $formattedPrice, price: $price, currency: $currency, description: $description, duration: $duration, freeTrialDuration: $freeTrialDuration)';
}


}

/// @nodoc
abstract mixin class _$PurchaseProductDetailsCopyWith<$Res> implements $PurchaseProductDetailsCopyWith<$Res> {
  factory _$PurchaseProductDetailsCopyWith(_PurchaseProductDetails value, $Res Function(_PurchaseProductDetails) _then) = __$PurchaseProductDetailsCopyWithImpl;
@override @useResult
$Res call({
 PurchaseProductId productId, PurchaseProductType productType, String name, String formattedPrice, double price, String currency, String description, Duration duration, PurchaseDuration freeTrialDuration
});


@override $PurchaseDurationCopyWith<$Res> get freeTrialDuration;

}
/// @nodoc
class __$PurchaseProductDetailsCopyWithImpl<$Res>
    implements _$PurchaseProductDetailsCopyWith<$Res> {
  __$PurchaseProductDetailsCopyWithImpl(this._self, this._then);

  final _PurchaseProductDetails _self;
  final $Res Function(_PurchaseProductDetails) _then;

/// Create a copy of PurchaseProductDetails
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? productId = null,Object? productType = null,Object? name = null,Object? formattedPrice = null,Object? price = null,Object? currency = null,Object? description = null,Object? duration = null,Object? freeTrialDuration = null,}) {
  return _then(_PurchaseProductDetails(
productId: null == productId ? _self.productId : productId // ignore: cast_nullable_to_non_nullable
as PurchaseProductId,productType: null == productType ? _self.productType : productType // ignore: cast_nullable_to_non_nullable
as PurchaseProductType,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,formattedPrice: null == formattedPrice ? _self.formattedPrice : formattedPrice // ignore: cast_nullable_to_non_nullable
as String,price: null == price ? _self.price : price // ignore: cast_nullable_to_non_nullable
as double,currency: null == currency ? _self.currency : currency // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,duration: null == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as Duration,freeTrialDuration: null == freeTrialDuration ? _self.freeTrialDuration : freeTrialDuration // ignore: cast_nullable_to_non_nullable
as PurchaseDuration,
  ));
}

/// Create a copy of PurchaseProductDetails
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PurchaseDurationCopyWith<$Res> get freeTrialDuration {
  
  return $PurchaseDurationCopyWith<$Res>(_self.freeTrialDuration, (value) {
    return _then(_self.copyWith(freeTrialDuration: value));
  });
}
}


/// @nodoc
mixin _$PurchaseDetails {

 PurchaseId get purchaseId; PurchaseProductId get productId; String get name;/// formatted price with currency
 String get formattedPrice; PurchaseStatus get status;/// price without currency in smallest unit of currency
 double get price; String get currency; DateTime get purchaseDate; PurchaseProductType get purchaseType; Duration get freeTrialDuration; Duration get duration; DateTime? get expiryDate; String? get localVerificationData; String? get serverVerificationData; String? get source;
/// Create a copy of PurchaseDetails
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PurchaseDetailsCopyWith<PurchaseDetails> get copyWith => _$PurchaseDetailsCopyWithImpl<PurchaseDetails>(this as PurchaseDetails, _$identity);

  /// Serializes this PurchaseDetails to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PurchaseDetails&&(identical(other.purchaseId, purchaseId) || other.purchaseId == purchaseId)&&(identical(other.productId, productId) || other.productId == productId)&&(identical(other.name, name) || other.name == name)&&(identical(other.formattedPrice, formattedPrice) || other.formattedPrice == formattedPrice)&&(identical(other.status, status) || other.status == status)&&(identical(other.price, price) || other.price == price)&&(identical(other.currency, currency) || other.currency == currency)&&(identical(other.purchaseDate, purchaseDate) || other.purchaseDate == purchaseDate)&&(identical(other.purchaseType, purchaseType) || other.purchaseType == purchaseType)&&(identical(other.freeTrialDuration, freeTrialDuration) || other.freeTrialDuration == freeTrialDuration)&&(identical(other.duration, duration) || other.duration == duration)&&(identical(other.expiryDate, expiryDate) || other.expiryDate == expiryDate)&&(identical(other.localVerificationData, localVerificationData) || other.localVerificationData == localVerificationData)&&(identical(other.serverVerificationData, serverVerificationData) || other.serverVerificationData == serverVerificationData)&&(identical(other.source, source) || other.source == source));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,purchaseId,productId,name,formattedPrice,status,price,currency,purchaseDate,purchaseType,freeTrialDuration,duration,expiryDate,localVerificationData,serverVerificationData,source);

@override
String toString() {
  return 'PurchaseDetails(purchaseId: $purchaseId, productId: $productId, name: $name, formattedPrice: $formattedPrice, status: $status, price: $price, currency: $currency, purchaseDate: $purchaseDate, purchaseType: $purchaseType, freeTrialDuration: $freeTrialDuration, duration: $duration, expiryDate: $expiryDate, localVerificationData: $localVerificationData, serverVerificationData: $serverVerificationData, source: $source)';
}


}

/// @nodoc
abstract mixin class $PurchaseDetailsCopyWith<$Res>  {
  factory $PurchaseDetailsCopyWith(PurchaseDetails value, $Res Function(PurchaseDetails) _then) = _$PurchaseDetailsCopyWithImpl;
@useResult
$Res call({
 PurchaseId purchaseId, PurchaseProductId productId, String name, String formattedPrice, PurchaseStatus status, double price, String currency, DateTime purchaseDate, PurchaseProductType purchaseType, Duration freeTrialDuration, Duration duration, DateTime? expiryDate, String? localVerificationData, String? serverVerificationData, String? source
});




}
/// @nodoc
class _$PurchaseDetailsCopyWithImpl<$Res>
    implements $PurchaseDetailsCopyWith<$Res> {
  _$PurchaseDetailsCopyWithImpl(this._self, this._then);

  final PurchaseDetails _self;
  final $Res Function(PurchaseDetails) _then;

/// Create a copy of PurchaseDetails
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? purchaseId = null,Object? productId = null,Object? name = null,Object? formattedPrice = null,Object? status = null,Object? price = null,Object? currency = null,Object? purchaseDate = null,Object? purchaseType = null,Object? freeTrialDuration = null,Object? duration = null,Object? expiryDate = freezed,Object? localVerificationData = freezed,Object? serverVerificationData = freezed,Object? source = freezed,}) {
  return _then(_self.copyWith(
purchaseId: null == purchaseId ? _self.purchaseId : purchaseId // ignore: cast_nullable_to_non_nullable
as PurchaseId,productId: null == productId ? _self.productId : productId // ignore: cast_nullable_to_non_nullable
as PurchaseProductId,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,formattedPrice: null == formattedPrice ? _self.formattedPrice : formattedPrice // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as PurchaseStatus,price: null == price ? _self.price : price // ignore: cast_nullable_to_non_nullable
as double,currency: null == currency ? _self.currency : currency // ignore: cast_nullable_to_non_nullable
as String,purchaseDate: null == purchaseDate ? _self.purchaseDate : purchaseDate // ignore: cast_nullable_to_non_nullable
as DateTime,purchaseType: null == purchaseType ? _self.purchaseType : purchaseType // ignore: cast_nullable_to_non_nullable
as PurchaseProductType,freeTrialDuration: null == freeTrialDuration ? _self.freeTrialDuration : freeTrialDuration // ignore: cast_nullable_to_non_nullable
as Duration,duration: null == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as Duration,expiryDate: freezed == expiryDate ? _self.expiryDate : expiryDate // ignore: cast_nullable_to_non_nullable
as DateTime?,localVerificationData: freezed == localVerificationData ? _self.localVerificationData : localVerificationData // ignore: cast_nullable_to_non_nullable
as String?,serverVerificationData: freezed == serverVerificationData ? _self.serverVerificationData : serverVerificationData // ignore: cast_nullable_to_non_nullable
as String?,source: freezed == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [PurchaseDetails].
extension PurchaseDetailsPatterns on PurchaseDetails {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PurchaseDetails value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PurchaseDetails() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PurchaseDetails value)  $default,){
final _that = this;
switch (_that) {
case _PurchaseDetails():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PurchaseDetails value)?  $default,){
final _that = this;
switch (_that) {
case _PurchaseDetails() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( PurchaseId purchaseId,  PurchaseProductId productId,  String name,  String formattedPrice,  PurchaseStatus status,  double price,  String currency,  DateTime purchaseDate,  PurchaseProductType purchaseType,  Duration freeTrialDuration,  Duration duration,  DateTime? expiryDate,  String? localVerificationData,  String? serverVerificationData,  String? source)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PurchaseDetails() when $default != null:
return $default(_that.purchaseId,_that.productId,_that.name,_that.formattedPrice,_that.status,_that.price,_that.currency,_that.purchaseDate,_that.purchaseType,_that.freeTrialDuration,_that.duration,_that.expiryDate,_that.localVerificationData,_that.serverVerificationData,_that.source);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( PurchaseId purchaseId,  PurchaseProductId productId,  String name,  String formattedPrice,  PurchaseStatus status,  double price,  String currency,  DateTime purchaseDate,  PurchaseProductType purchaseType,  Duration freeTrialDuration,  Duration duration,  DateTime? expiryDate,  String? localVerificationData,  String? serverVerificationData,  String? source)  $default,) {final _that = this;
switch (_that) {
case _PurchaseDetails():
return $default(_that.purchaseId,_that.productId,_that.name,_that.formattedPrice,_that.status,_that.price,_that.currency,_that.purchaseDate,_that.purchaseType,_that.freeTrialDuration,_that.duration,_that.expiryDate,_that.localVerificationData,_that.serverVerificationData,_that.source);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( PurchaseId purchaseId,  PurchaseProductId productId,  String name,  String formattedPrice,  PurchaseStatus status,  double price,  String currency,  DateTime purchaseDate,  PurchaseProductType purchaseType,  Duration freeTrialDuration,  Duration duration,  DateTime? expiryDate,  String? localVerificationData,  String? serverVerificationData,  String? source)?  $default,) {final _that = this;
switch (_that) {
case _PurchaseDetails() when $default != null:
return $default(_that.purchaseId,_that.productId,_that.name,_that.formattedPrice,_that.status,_that.price,_that.currency,_that.purchaseDate,_that.purchaseType,_that.freeTrialDuration,_that.duration,_that.expiryDate,_that.localVerificationData,_that.serverVerificationData,_that.source);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PurchaseDetails extends PurchaseDetails {
  const _PurchaseDetails({required this.purchaseId, required this.productId, required this.name, required this.formattedPrice, required this.status, required this.price, required this.currency, required this.purchaseDate, required this.purchaseType, this.freeTrialDuration = Duration.zero, this.duration = Duration.zero, this.expiryDate, this.localVerificationData, this.serverVerificationData, this.source}): super._();
  factory _PurchaseDetails.fromJson(Map<String, dynamic> json) => _$PurchaseDetailsFromJson(json);

@override final  PurchaseId purchaseId;
@override final  PurchaseProductId productId;
@override final  String name;
/// formatted price with currency
@override final  String formattedPrice;
@override final  PurchaseStatus status;
/// price without currency in smallest unit of currency
@override final  double price;
@override final  String currency;
@override final  DateTime purchaseDate;
@override final  PurchaseProductType purchaseType;
@override@JsonKey() final  Duration freeTrialDuration;
@override@JsonKey() final  Duration duration;
@override final  DateTime? expiryDate;
@override final  String? localVerificationData;
@override final  String? serverVerificationData;
@override final  String? source;

/// Create a copy of PurchaseDetails
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PurchaseDetailsCopyWith<_PurchaseDetails> get copyWith => __$PurchaseDetailsCopyWithImpl<_PurchaseDetails>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PurchaseDetailsToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PurchaseDetails&&(identical(other.purchaseId, purchaseId) || other.purchaseId == purchaseId)&&(identical(other.productId, productId) || other.productId == productId)&&(identical(other.name, name) || other.name == name)&&(identical(other.formattedPrice, formattedPrice) || other.formattedPrice == formattedPrice)&&(identical(other.status, status) || other.status == status)&&(identical(other.price, price) || other.price == price)&&(identical(other.currency, currency) || other.currency == currency)&&(identical(other.purchaseDate, purchaseDate) || other.purchaseDate == purchaseDate)&&(identical(other.purchaseType, purchaseType) || other.purchaseType == purchaseType)&&(identical(other.freeTrialDuration, freeTrialDuration) || other.freeTrialDuration == freeTrialDuration)&&(identical(other.duration, duration) || other.duration == duration)&&(identical(other.expiryDate, expiryDate) || other.expiryDate == expiryDate)&&(identical(other.localVerificationData, localVerificationData) || other.localVerificationData == localVerificationData)&&(identical(other.serverVerificationData, serverVerificationData) || other.serverVerificationData == serverVerificationData)&&(identical(other.source, source) || other.source == source));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,purchaseId,productId,name,formattedPrice,status,price,currency,purchaseDate,purchaseType,freeTrialDuration,duration,expiryDate,localVerificationData,serverVerificationData,source);

@override
String toString() {
  return 'PurchaseDetails(purchaseId: $purchaseId, productId: $productId, name: $name, formattedPrice: $formattedPrice, status: $status, price: $price, currency: $currency, purchaseDate: $purchaseDate, purchaseType: $purchaseType, freeTrialDuration: $freeTrialDuration, duration: $duration, expiryDate: $expiryDate, localVerificationData: $localVerificationData, serverVerificationData: $serverVerificationData, source: $source)';
}


}

/// @nodoc
abstract mixin class _$PurchaseDetailsCopyWith<$Res> implements $PurchaseDetailsCopyWith<$Res> {
  factory _$PurchaseDetailsCopyWith(_PurchaseDetails value, $Res Function(_PurchaseDetails) _then) = __$PurchaseDetailsCopyWithImpl;
@override @useResult
$Res call({
 PurchaseId purchaseId, PurchaseProductId productId, String name, String formattedPrice, PurchaseStatus status, double price, String currency, DateTime purchaseDate, PurchaseProductType purchaseType, Duration freeTrialDuration, Duration duration, DateTime? expiryDate, String? localVerificationData, String? serverVerificationData, String? source
});




}
/// @nodoc
class __$PurchaseDetailsCopyWithImpl<$Res>
    implements _$PurchaseDetailsCopyWith<$Res> {
  __$PurchaseDetailsCopyWithImpl(this._self, this._then);

  final _PurchaseDetails _self;
  final $Res Function(_PurchaseDetails) _then;

/// Create a copy of PurchaseDetails
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? purchaseId = null,Object? productId = null,Object? name = null,Object? formattedPrice = null,Object? status = null,Object? price = null,Object? currency = null,Object? purchaseDate = null,Object? purchaseType = null,Object? freeTrialDuration = null,Object? duration = null,Object? expiryDate = freezed,Object? localVerificationData = freezed,Object? serverVerificationData = freezed,Object? source = freezed,}) {
  return _then(_PurchaseDetails(
purchaseId: null == purchaseId ? _self.purchaseId : purchaseId // ignore: cast_nullable_to_non_nullable
as PurchaseId,productId: null == productId ? _self.productId : productId // ignore: cast_nullable_to_non_nullable
as PurchaseProductId,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,formattedPrice: null == formattedPrice ? _self.formattedPrice : formattedPrice // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as PurchaseStatus,price: null == price ? _self.price : price // ignore: cast_nullable_to_non_nullable
as double,currency: null == currency ? _self.currency : currency // ignore: cast_nullable_to_non_nullable
as String,purchaseDate: null == purchaseDate ? _self.purchaseDate : purchaseDate // ignore: cast_nullable_to_non_nullable
as DateTime,purchaseType: null == purchaseType ? _self.purchaseType : purchaseType // ignore: cast_nullable_to_non_nullable
as PurchaseProductType,freeTrialDuration: null == freeTrialDuration ? _self.freeTrialDuration : freeTrialDuration // ignore: cast_nullable_to_non_nullable
as Duration,duration: null == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as Duration,expiryDate: freezed == expiryDate ? _self.expiryDate : expiryDate // ignore: cast_nullable_to_non_nullable
as DateTime?,localVerificationData: freezed == localVerificationData ? _self.localVerificationData : localVerificationData // ignore: cast_nullable_to_non_nullable
as String?,serverVerificationData: freezed == serverVerificationData ? _self.serverVerificationData : serverVerificationData // ignore: cast_nullable_to_non_nullable
as String?,source: freezed == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

PurchaseResult _$PurchaseResultFromJson(
  Map<String, dynamic> json
) {
        switch (json['runtimeType']) {
                  case 'success':
          return PurchaseSuccess.fromJson(
            json
          );
                case 'failure':
          return PurchaseFailure.fromJson(
            json
          );
        
          default:
            throw CheckedFromJsonException(
  json,
  'runtimeType',
  'PurchaseResult',
  'Invalid union type "${json['runtimeType']}"!'
);
        }
      
}

/// @nodoc
mixin _$PurchaseResult {



  /// Serializes this PurchaseResult to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PurchaseResult);
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'PurchaseResult()';
}


}

/// @nodoc
class $PurchaseResultCopyWith<$Res>  {
$PurchaseResultCopyWith(PurchaseResult _, $Res Function(PurchaseResult) __);
}


/// Adds pattern-matching-related methods to [PurchaseResult].
extension PurchaseResultPatterns on PurchaseResult {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( PurchaseSuccess value)?  success,TResult Function( PurchaseFailure value)?  failure,required TResult orElse(),}){
final _that = this;
switch (_that) {
case PurchaseSuccess() when success != null:
return success(_that);case PurchaseFailure() when failure != null:
return failure(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( PurchaseSuccess value)  success,required TResult Function( PurchaseFailure value)  failure,}){
final _that = this;
switch (_that) {
case PurchaseSuccess():
return success(_that);case PurchaseFailure():
return failure(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( PurchaseSuccess value)?  success,TResult? Function( PurchaseFailure value)?  failure,}){
final _that = this;
switch (_that) {
case PurchaseSuccess() when success != null:
return success(_that);case PurchaseFailure() when failure != null:
return failure(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( PurchaseDetails details)?  success,TResult Function( String error)?  failure,required TResult orElse(),}) {final _that = this;
switch (_that) {
case PurchaseSuccess() when success != null:
return success(_that.details);case PurchaseFailure() when failure != null:
return failure(_that.error);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( PurchaseDetails details)  success,required TResult Function( String error)  failure,}) {final _that = this;
switch (_that) {
case PurchaseSuccess():
return success(_that.details);case PurchaseFailure():
return failure(_that.error);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( PurchaseDetails details)?  success,TResult? Function( String error)?  failure,}) {final _that = this;
switch (_that) {
case PurchaseSuccess() when success != null:
return success(_that.details);case PurchaseFailure() when failure != null:
return failure(_that.error);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class PurchaseSuccess implements PurchaseResult {
  const PurchaseSuccess(this.details, {final  String? $type}): $type = $type ?? 'success';
  factory PurchaseSuccess.fromJson(Map<String, dynamic> json) => _$PurchaseSuccessFromJson(json);

 final  PurchaseDetails details;

@JsonKey(name: 'runtimeType')
final String $type;


/// Create a copy of PurchaseResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PurchaseSuccessCopyWith<PurchaseSuccess> get copyWith => _$PurchaseSuccessCopyWithImpl<PurchaseSuccess>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PurchaseSuccessToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PurchaseSuccess&&(identical(other.details, details) || other.details == details));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,details);

@override
String toString() {
  return 'PurchaseResult.success(details: $details)';
}


}

/// @nodoc
abstract mixin class $PurchaseSuccessCopyWith<$Res> implements $PurchaseResultCopyWith<$Res> {
  factory $PurchaseSuccessCopyWith(PurchaseSuccess value, $Res Function(PurchaseSuccess) _then) = _$PurchaseSuccessCopyWithImpl;
@useResult
$Res call({
 PurchaseDetails details
});


$PurchaseDetailsCopyWith<$Res> get details;

}
/// @nodoc
class _$PurchaseSuccessCopyWithImpl<$Res>
    implements $PurchaseSuccessCopyWith<$Res> {
  _$PurchaseSuccessCopyWithImpl(this._self, this._then);

  final PurchaseSuccess _self;
  final $Res Function(PurchaseSuccess) _then;

/// Create a copy of PurchaseResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? details = null,}) {
  return _then(PurchaseSuccess(
null == details ? _self.details : details // ignore: cast_nullable_to_non_nullable
as PurchaseDetails,
  ));
}

/// Create a copy of PurchaseResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PurchaseDetailsCopyWith<$Res> get details {
  
  return $PurchaseDetailsCopyWith<$Res>(_self.details, (value) {
    return _then(_self.copyWith(details: value));
  });
}
}

/// @nodoc
@JsonSerializable()

class PurchaseFailure implements PurchaseResult {
  const PurchaseFailure(this.error, {final  String? $type}): $type = $type ?? 'failure';
  factory PurchaseFailure.fromJson(Map<String, dynamic> json) => _$PurchaseFailureFromJson(json);

 final  String error;

@JsonKey(name: 'runtimeType')
final String $type;


/// Create a copy of PurchaseResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PurchaseFailureCopyWith<PurchaseFailure> get copyWith => _$PurchaseFailureCopyWithImpl<PurchaseFailure>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PurchaseFailureToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PurchaseFailure&&(identical(other.error, error) || other.error == error));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,error);

@override
String toString() {
  return 'PurchaseResult.failure(error: $error)';
}


}

/// @nodoc
abstract mixin class $PurchaseFailureCopyWith<$Res> implements $PurchaseResultCopyWith<$Res> {
  factory $PurchaseFailureCopyWith(PurchaseFailure value, $Res Function(PurchaseFailure) _then) = _$PurchaseFailureCopyWithImpl;
@useResult
$Res call({
 String error
});




}
/// @nodoc
class _$PurchaseFailureCopyWithImpl<$Res>
    implements $PurchaseFailureCopyWith<$Res> {
  _$PurchaseFailureCopyWithImpl(this._self, this._then);

  final PurchaseFailure _self;
  final $Res Function(PurchaseFailure) _then;

/// Create a copy of PurchaseResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(PurchaseFailure(
null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

RestoreResult _$RestoreResultFromJson(
  Map<String, dynamic> json
) {
        switch (json['runtimeType']) {
                  case 'success':
          return RestoreSuccess.fromJson(
            json
          );
                case 'failure':
          return RestoreFailure.fromJson(
            json
          );
        
          default:
            throw CheckedFromJsonException(
  json,
  'runtimeType',
  'RestoreResult',
  'Invalid union type "${json['runtimeType']}"!'
);
        }
      
}

/// @nodoc
mixin _$RestoreResult {



  /// Serializes this RestoreResult to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RestoreResult);
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RestoreResult()';
}


}

/// @nodoc
class $RestoreResultCopyWith<$Res>  {
$RestoreResultCopyWith(RestoreResult _, $Res Function(RestoreResult) __);
}


/// Adds pattern-matching-related methods to [RestoreResult].
extension RestoreResultPatterns on RestoreResult {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RestoreSuccess value)?  success,TResult Function( RestoreFailure value)?  failure,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RestoreSuccess() when success != null:
return success(_that);case RestoreFailure() when failure != null:
return failure(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RestoreSuccess value)  success,required TResult Function( RestoreFailure value)  failure,}){
final _that = this;
switch (_that) {
case RestoreSuccess():
return success(_that);case RestoreFailure():
return failure(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RestoreSuccess value)?  success,TResult? Function( RestoreFailure value)?  failure,}){
final _that = this;
switch (_that) {
case RestoreSuccess() when success != null:
return success(_that);case RestoreFailure() when failure != null:
return failure(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( List<PurchaseDetails> restoredPurchases)?  success,TResult Function( String error)?  failure,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RestoreSuccess() when success != null:
return success(_that.restoredPurchases);case RestoreFailure() when failure != null:
return failure(_that.error);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( List<PurchaseDetails> restoredPurchases)  success,required TResult Function( String error)  failure,}) {final _that = this;
switch (_that) {
case RestoreSuccess():
return success(_that.restoredPurchases);case RestoreFailure():
return failure(_that.error);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( List<PurchaseDetails> restoredPurchases)?  success,TResult? Function( String error)?  failure,}) {final _that = this;
switch (_that) {
case RestoreSuccess() when success != null:
return success(_that.restoredPurchases);case RestoreFailure() when failure != null:
return failure(_that.error);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class RestoreSuccess implements RestoreResult {
  const RestoreSuccess(final  List<PurchaseDetails> restoredPurchases, {final  String? $type}): _restoredPurchases = restoredPurchases,$type = $type ?? 'success';
  factory RestoreSuccess.fromJson(Map<String, dynamic> json) => _$RestoreSuccessFromJson(json);

 final  List<PurchaseDetails> _restoredPurchases;
 List<PurchaseDetails> get restoredPurchases {
  if (_restoredPurchases is EqualUnmodifiableListView) return _restoredPurchases;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_restoredPurchases);
}


@JsonKey(name: 'runtimeType')
final String $type;


/// Create a copy of RestoreResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RestoreSuccessCopyWith<RestoreSuccess> get copyWith => _$RestoreSuccessCopyWithImpl<RestoreSuccess>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RestoreSuccessToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RestoreSuccess&&const DeepCollectionEquality().equals(other._restoredPurchases, _restoredPurchases));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_restoredPurchases));

@override
String toString() {
  return 'RestoreResult.success(restoredPurchases: $restoredPurchases)';
}


}

/// @nodoc
abstract mixin class $RestoreSuccessCopyWith<$Res> implements $RestoreResultCopyWith<$Res> {
  factory $RestoreSuccessCopyWith(RestoreSuccess value, $Res Function(RestoreSuccess) _then) = _$RestoreSuccessCopyWithImpl;
@useResult
$Res call({
 List<PurchaseDetails> restoredPurchases
});




}
/// @nodoc
class _$RestoreSuccessCopyWithImpl<$Res>
    implements $RestoreSuccessCopyWith<$Res> {
  _$RestoreSuccessCopyWithImpl(this._self, this._then);

  final RestoreSuccess _self;
  final $Res Function(RestoreSuccess) _then;

/// Create a copy of RestoreResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? restoredPurchases = null,}) {
  return _then(RestoreSuccess(
null == restoredPurchases ? _self._restoredPurchases : restoredPurchases // ignore: cast_nullable_to_non_nullable
as List<PurchaseDetails>,
  ));
}


}

/// @nodoc
@JsonSerializable()

class RestoreFailure implements RestoreResult {
  const RestoreFailure(this.error, {final  String? $type}): $type = $type ?? 'failure';
  factory RestoreFailure.fromJson(Map<String, dynamic> json) => _$RestoreFailureFromJson(json);

 final  String error;

@JsonKey(name: 'runtimeType')
final String $type;


/// Create a copy of RestoreResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RestoreFailureCopyWith<RestoreFailure> get copyWith => _$RestoreFailureCopyWithImpl<RestoreFailure>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RestoreFailureToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RestoreFailure&&(identical(other.error, error) || other.error == error));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,error);

@override
String toString() {
  return 'RestoreResult.failure(error: $error)';
}


}

/// @nodoc
abstract mixin class $RestoreFailureCopyWith<$Res> implements $RestoreResultCopyWith<$Res> {
  factory $RestoreFailureCopyWith(RestoreFailure value, $Res Function(RestoreFailure) _then) = _$RestoreFailureCopyWithImpl;
@useResult
$Res call({
 String error
});




}
/// @nodoc
class _$RestoreFailureCopyWithImpl<$Res>
    implements $RestoreFailureCopyWith<$Res> {
  _$RestoreFailureCopyWithImpl(this._self, this._then);

  final RestoreFailure _self;
  final $Res Function(RestoreFailure) _then;

/// Create a copy of RestoreResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(RestoreFailure(
null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

CancelResult _$CancelResultFromJson(
  Map<String, dynamic> json
) {
        switch (json['runtimeType']) {
                  case 'success':
          return CancelSuccess.fromJson(
            json
          );
                case 'failure':
          return CancelFailure.fromJson(
            json
          );
        
          default:
            throw CheckedFromJsonException(
  json,
  'runtimeType',
  'CancelResult',
  'Invalid union type "${json['runtimeType']}"!'
);
        }
      
}

/// @nodoc
mixin _$CancelResult {



  /// Serializes this CancelResult to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CancelResult);
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'CancelResult()';
}


}

/// @nodoc
class $CancelResultCopyWith<$Res>  {
$CancelResultCopyWith(CancelResult _, $Res Function(CancelResult) __);
}


/// Adds pattern-matching-related methods to [CancelResult].
extension CancelResultPatterns on CancelResult {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( CancelSuccess value)?  success,TResult Function( CancelFailure value)?  failure,required TResult orElse(),}){
final _that = this;
switch (_that) {
case CancelSuccess() when success != null:
return success(_that);case CancelFailure() when failure != null:
return failure(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( CancelSuccess value)  success,required TResult Function( CancelFailure value)  failure,}){
final _that = this;
switch (_that) {
case CancelSuccess():
return success(_that);case CancelFailure():
return failure(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( CancelSuccess value)?  success,TResult? Function( CancelFailure value)?  failure,}){
final _that = this;
switch (_that) {
case CancelSuccess() when success != null:
return success(_that);case CancelFailure() when failure != null:
return failure(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  success,TResult Function( String error)?  failure,required TResult orElse(),}) {final _that = this;
switch (_that) {
case CancelSuccess() when success != null:
return success();case CancelFailure() when failure != null:
return failure(_that.error);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  success,required TResult Function( String error)  failure,}) {final _that = this;
switch (_that) {
case CancelSuccess():
return success();case CancelFailure():
return failure(_that.error);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  success,TResult? Function( String error)?  failure,}) {final _that = this;
switch (_that) {
case CancelSuccess() when success != null:
return success();case CancelFailure() when failure != null:
return failure(_that.error);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class CancelSuccess implements CancelResult {
  const CancelSuccess({final  String? $type}): $type = $type ?? 'success';
  factory CancelSuccess.fromJson(Map<String, dynamic> json) => _$CancelSuccessFromJson(json);



@JsonKey(name: 'runtimeType')
final String $type;



@override
Map<String, dynamic> toJson() {
  return _$CancelSuccessToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CancelSuccess);
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'CancelResult.success()';
}


}




/// @nodoc
@JsonSerializable()

class CancelFailure implements CancelResult {
  const CancelFailure(this.error, {final  String? $type}): $type = $type ?? 'failure';
  factory CancelFailure.fromJson(Map<String, dynamic> json) => _$CancelFailureFromJson(json);

 final  String error;

@JsonKey(name: 'runtimeType')
final String $type;


/// Create a copy of CancelResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CancelFailureCopyWith<CancelFailure> get copyWith => _$CancelFailureCopyWithImpl<CancelFailure>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$CancelFailureToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CancelFailure&&(identical(other.error, error) || other.error == error));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,error);

@override
String toString() {
  return 'CancelResult.failure(error: $error)';
}


}

/// @nodoc
abstract mixin class $CancelFailureCopyWith<$Res> implements $CancelResultCopyWith<$Res> {
  factory $CancelFailureCopyWith(CancelFailure value, $Res Function(CancelFailure) _then) = _$CancelFailureCopyWithImpl;
@useResult
$Res call({
 String error
});




}
/// @nodoc
class _$CancelFailureCopyWithImpl<$Res>
    implements $CancelFailureCopyWith<$Res> {
  _$CancelFailureCopyWithImpl(this._self, this._then);

  final CancelFailure _self;
  final $Res Function(CancelFailure) _then;

/// Create a copy of CancelResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(CancelFailure(
null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

CompletePurchaseResult _$CompletePurchaseResultFromJson(
  Map<String, dynamic> json
) {
        switch (json['runtimeType']) {
                  case 'success':
          return CompletePurchaseSuccess.fromJson(
            json
          );
                case 'failure':
          return CompletePurchaseFailure.fromJson(
            json
          );
        
          default:
            throw CheckedFromJsonException(
  json,
  'runtimeType',
  'CompletePurchaseResult',
  'Invalid union type "${json['runtimeType']}"!'
);
        }
      
}

/// @nodoc
mixin _$CompletePurchaseResult {



  /// Serializes this CompletePurchaseResult to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CompletePurchaseResult);
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'CompletePurchaseResult()';
}


}

/// @nodoc
class $CompletePurchaseResultCopyWith<$Res>  {
$CompletePurchaseResultCopyWith(CompletePurchaseResult _, $Res Function(CompletePurchaseResult) __);
}


/// Adds pattern-matching-related methods to [CompletePurchaseResult].
extension CompletePurchaseResultPatterns on CompletePurchaseResult {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( CompletePurchaseSuccess value)?  success,TResult Function( CompletePurchaseFailure value)?  failure,required TResult orElse(),}){
final _that = this;
switch (_that) {
case CompletePurchaseSuccess() when success != null:
return success(_that);case CompletePurchaseFailure() when failure != null:
return failure(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( CompletePurchaseSuccess value)  success,required TResult Function( CompletePurchaseFailure value)  failure,}){
final _that = this;
switch (_that) {
case CompletePurchaseSuccess():
return success(_that);case CompletePurchaseFailure():
return failure(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( CompletePurchaseSuccess value)?  success,TResult? Function( CompletePurchaseFailure value)?  failure,}){
final _that = this;
switch (_that) {
case CompletePurchaseSuccess() when success != null:
return success(_that);case CompletePurchaseFailure() when failure != null:
return failure(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  success,TResult Function( String error)?  failure,required TResult orElse(),}) {final _that = this;
switch (_that) {
case CompletePurchaseSuccess() when success != null:
return success();case CompletePurchaseFailure() when failure != null:
return failure(_that.error);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  success,required TResult Function( String error)  failure,}) {final _that = this;
switch (_that) {
case CompletePurchaseSuccess():
return success();case CompletePurchaseFailure():
return failure(_that.error);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  success,TResult? Function( String error)?  failure,}) {final _that = this;
switch (_that) {
case CompletePurchaseSuccess() when success != null:
return success();case CompletePurchaseFailure() when failure != null:
return failure(_that.error);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class CompletePurchaseSuccess implements CompletePurchaseResult {
  const CompletePurchaseSuccess({final  String? $type}): $type = $type ?? 'success';
  factory CompletePurchaseSuccess.fromJson(Map<String, dynamic> json) => _$CompletePurchaseSuccessFromJson(json);



@JsonKey(name: 'runtimeType')
final String $type;



@override
Map<String, dynamic> toJson() {
  return _$CompletePurchaseSuccessToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CompletePurchaseSuccess);
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'CompletePurchaseResult.success()';
}


}




/// @nodoc
@JsonSerializable()

class CompletePurchaseFailure implements CompletePurchaseResult {
  const CompletePurchaseFailure(this.error, {final  String? $type}): $type = $type ?? 'failure';
  factory CompletePurchaseFailure.fromJson(Map<String, dynamic> json) => _$CompletePurchaseFailureFromJson(json);

 final  String error;

@JsonKey(name: 'runtimeType')
final String $type;


/// Create a copy of CompletePurchaseResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CompletePurchaseFailureCopyWith<CompletePurchaseFailure> get copyWith => _$CompletePurchaseFailureCopyWithImpl<CompletePurchaseFailure>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$CompletePurchaseFailureToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CompletePurchaseFailure&&(identical(other.error, error) || other.error == error));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,error);

@override
String toString() {
  return 'CompletePurchaseResult.failure(error: $error)';
}


}

/// @nodoc
abstract mixin class $CompletePurchaseFailureCopyWith<$Res> implements $CompletePurchaseResultCopyWith<$Res> {
  factory $CompletePurchaseFailureCopyWith(CompletePurchaseFailure value, $Res Function(CompletePurchaseFailure) _then) = _$CompletePurchaseFailureCopyWithImpl;
@useResult
$Res call({
 String error
});




}
/// @nodoc
class _$CompletePurchaseFailureCopyWithImpl<$Res>
    implements $CompletePurchaseFailureCopyWith<$Res> {
  _$CompletePurchaseFailureCopyWithImpl(this._self, this._then);

  final CompletePurchaseFailure _self;
  final $Res Function(CompletePurchaseFailure) _then;

/// Create a copy of CompletePurchaseResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(CompletePurchaseFailure(
null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$PurchaseVerificationDto {

 PurchaseId get purchaseId; PurchaseProductId get productId; PurchaseStatus get status; PurchaseProductType get productType; DateTime? get transactionDate; String? get purchaseToken; String? get localVerificationData; String? get serverVerificationData; String? get source;
/// Create a copy of PurchaseVerificationDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PurchaseVerificationDtoCopyWith<PurchaseVerificationDto> get copyWith => _$PurchaseVerificationDtoCopyWithImpl<PurchaseVerificationDto>(this as PurchaseVerificationDto, _$identity);

  /// Serializes this PurchaseVerificationDto to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PurchaseVerificationDto&&(identical(other.purchaseId, purchaseId) || other.purchaseId == purchaseId)&&(identical(other.productId, productId) || other.productId == productId)&&(identical(other.status, status) || other.status == status)&&(identical(other.productType, productType) || other.productType == productType)&&(identical(other.transactionDate, transactionDate) || other.transactionDate == transactionDate)&&(identical(other.purchaseToken, purchaseToken) || other.purchaseToken == purchaseToken)&&(identical(other.localVerificationData, localVerificationData) || other.localVerificationData == localVerificationData)&&(identical(other.serverVerificationData, serverVerificationData) || other.serverVerificationData == serverVerificationData)&&(identical(other.source, source) || other.source == source));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,purchaseId,productId,status,productType,transactionDate,purchaseToken,localVerificationData,serverVerificationData,source);

@override
String toString() {
  return 'PurchaseVerificationDto(purchaseId: $purchaseId, productId: $productId, status: $status, productType: $productType, transactionDate: $transactionDate, purchaseToken: $purchaseToken, localVerificationData: $localVerificationData, serverVerificationData: $serverVerificationData, source: $source)';
}


}

/// @nodoc
abstract mixin class $PurchaseVerificationDtoCopyWith<$Res>  {
  factory $PurchaseVerificationDtoCopyWith(PurchaseVerificationDto value, $Res Function(PurchaseVerificationDto) _then) = _$PurchaseVerificationDtoCopyWithImpl;
@useResult
$Res call({
 PurchaseId purchaseId, PurchaseProductId productId, PurchaseStatus status, PurchaseProductType productType, DateTime? transactionDate, String? purchaseToken, String? localVerificationData, String? serverVerificationData, String? source
});




}
/// @nodoc
class _$PurchaseVerificationDtoCopyWithImpl<$Res>
    implements $PurchaseVerificationDtoCopyWith<$Res> {
  _$PurchaseVerificationDtoCopyWithImpl(this._self, this._then);

  final PurchaseVerificationDto _self;
  final $Res Function(PurchaseVerificationDto) _then;

/// Create a copy of PurchaseVerificationDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? purchaseId = null,Object? productId = null,Object? status = null,Object? productType = null,Object? transactionDate = freezed,Object? purchaseToken = freezed,Object? localVerificationData = freezed,Object? serverVerificationData = freezed,Object? source = freezed,}) {
  return _then(_self.copyWith(
purchaseId: null == purchaseId ? _self.purchaseId : purchaseId // ignore: cast_nullable_to_non_nullable
as PurchaseId,productId: null == productId ? _self.productId : productId // ignore: cast_nullable_to_non_nullable
as PurchaseProductId,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as PurchaseStatus,productType: null == productType ? _self.productType : productType // ignore: cast_nullable_to_non_nullable
as PurchaseProductType,transactionDate: freezed == transactionDate ? _self.transactionDate : transactionDate // ignore: cast_nullable_to_non_nullable
as DateTime?,purchaseToken: freezed == purchaseToken ? _self.purchaseToken : purchaseToken // ignore: cast_nullable_to_non_nullable
as String?,localVerificationData: freezed == localVerificationData ? _self.localVerificationData : localVerificationData // ignore: cast_nullable_to_non_nullable
as String?,serverVerificationData: freezed == serverVerificationData ? _self.serverVerificationData : serverVerificationData // ignore: cast_nullable_to_non_nullable
as String?,source: freezed == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [PurchaseVerificationDto].
extension PurchaseVerificationDtoPatterns on PurchaseVerificationDto {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PurchaseVerificationDto value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PurchaseVerificationDto() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PurchaseVerificationDto value)  $default,){
final _that = this;
switch (_that) {
case _PurchaseVerificationDto():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PurchaseVerificationDto value)?  $default,){
final _that = this;
switch (_that) {
case _PurchaseVerificationDto() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( PurchaseId purchaseId,  PurchaseProductId productId,  PurchaseStatus status,  PurchaseProductType productType,  DateTime? transactionDate,  String? purchaseToken,  String? localVerificationData,  String? serverVerificationData,  String? source)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PurchaseVerificationDto() when $default != null:
return $default(_that.purchaseId,_that.productId,_that.status,_that.productType,_that.transactionDate,_that.purchaseToken,_that.localVerificationData,_that.serverVerificationData,_that.source);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( PurchaseId purchaseId,  PurchaseProductId productId,  PurchaseStatus status,  PurchaseProductType productType,  DateTime? transactionDate,  String? purchaseToken,  String? localVerificationData,  String? serverVerificationData,  String? source)  $default,) {final _that = this;
switch (_that) {
case _PurchaseVerificationDto():
return $default(_that.purchaseId,_that.productId,_that.status,_that.productType,_that.transactionDate,_that.purchaseToken,_that.localVerificationData,_that.serverVerificationData,_that.source);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( PurchaseId purchaseId,  PurchaseProductId productId,  PurchaseStatus status,  PurchaseProductType productType,  DateTime? transactionDate,  String? purchaseToken,  String? localVerificationData,  String? serverVerificationData,  String? source)?  $default,) {final _that = this;
switch (_that) {
case _PurchaseVerificationDto() when $default != null:
return $default(_that.purchaseId,_that.productId,_that.status,_that.productType,_that.transactionDate,_that.purchaseToken,_that.localVerificationData,_that.serverVerificationData,_that.source);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PurchaseVerificationDto implements PurchaseVerificationDto {
  const _PurchaseVerificationDto({required this.purchaseId, required this.productId, required this.status, required this.productType, this.transactionDate, this.purchaseToken, this.localVerificationData, this.serverVerificationData, this.source});
  factory _PurchaseVerificationDto.fromJson(Map<String, dynamic> json) => _$PurchaseVerificationDtoFromJson(json);

@override final  PurchaseId purchaseId;
@override final  PurchaseProductId productId;
@override final  PurchaseStatus status;
@override final  PurchaseProductType productType;
@override final  DateTime? transactionDate;
@override final  String? purchaseToken;
@override final  String? localVerificationData;
@override final  String? serverVerificationData;
@override final  String? source;

/// Create a copy of PurchaseVerificationDto
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PurchaseVerificationDtoCopyWith<_PurchaseVerificationDto> get copyWith => __$PurchaseVerificationDtoCopyWithImpl<_PurchaseVerificationDto>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PurchaseVerificationDtoToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PurchaseVerificationDto&&(identical(other.purchaseId, purchaseId) || other.purchaseId == purchaseId)&&(identical(other.productId, productId) || other.productId == productId)&&(identical(other.status, status) || other.status == status)&&(identical(other.productType, productType) || other.productType == productType)&&(identical(other.transactionDate, transactionDate) || other.transactionDate == transactionDate)&&(identical(other.purchaseToken, purchaseToken) || other.purchaseToken == purchaseToken)&&(identical(other.localVerificationData, localVerificationData) || other.localVerificationData == localVerificationData)&&(identical(other.serverVerificationData, serverVerificationData) || other.serverVerificationData == serverVerificationData)&&(identical(other.source, source) || other.source == source));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,purchaseId,productId,status,productType,transactionDate,purchaseToken,localVerificationData,serverVerificationData,source);

@override
String toString() {
  return 'PurchaseVerificationDto(purchaseId: $purchaseId, productId: $productId, status: $status, productType: $productType, transactionDate: $transactionDate, purchaseToken: $purchaseToken, localVerificationData: $localVerificationData, serverVerificationData: $serverVerificationData, source: $source)';
}


}

/// @nodoc
abstract mixin class _$PurchaseVerificationDtoCopyWith<$Res> implements $PurchaseVerificationDtoCopyWith<$Res> {
  factory _$PurchaseVerificationDtoCopyWith(_PurchaseVerificationDto value, $Res Function(_PurchaseVerificationDto) _then) = __$PurchaseVerificationDtoCopyWithImpl;
@override @useResult
$Res call({
 PurchaseId purchaseId, PurchaseProductId productId, PurchaseStatus status, PurchaseProductType productType, DateTime? transactionDate, String? purchaseToken, String? localVerificationData, String? serverVerificationData, String? source
});




}
/// @nodoc
class __$PurchaseVerificationDtoCopyWithImpl<$Res>
    implements _$PurchaseVerificationDtoCopyWith<$Res> {
  __$PurchaseVerificationDtoCopyWithImpl(this._self, this._then);

  final _PurchaseVerificationDto _self;
  final $Res Function(_PurchaseVerificationDto) _then;

/// Create a copy of PurchaseVerificationDto
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? purchaseId = null,Object? productId = null,Object? status = null,Object? productType = null,Object? transactionDate = freezed,Object? purchaseToken = freezed,Object? localVerificationData = freezed,Object? serverVerificationData = freezed,Object? source = freezed,}) {
  return _then(_PurchaseVerificationDto(
purchaseId: null == purchaseId ? _self.purchaseId : purchaseId // ignore: cast_nullable_to_non_nullable
as PurchaseId,productId: null == productId ? _self.productId : productId // ignore: cast_nullable_to_non_nullable
as PurchaseProductId,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as PurchaseStatus,productType: null == productType ? _self.productType : productType // ignore: cast_nullable_to_non_nullable
as PurchaseProductType,transactionDate: freezed == transactionDate ? _self.transactionDate : transactionDate // ignore: cast_nullable_to_non_nullable
as DateTime?,purchaseToken: freezed == purchaseToken ? _self.purchaseToken : purchaseToken // ignore: cast_nullable_to_non_nullable
as String?,localVerificationData: freezed == localVerificationData ? _self.localVerificationData : localVerificationData // ignore: cast_nullable_to_non_nullable
as String?,serverVerificationData: freezed == serverVerificationData ? _self.serverVerificationData : serverVerificationData // ignore: cast_nullable_to_non_nullable
as String?,source: freezed == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
