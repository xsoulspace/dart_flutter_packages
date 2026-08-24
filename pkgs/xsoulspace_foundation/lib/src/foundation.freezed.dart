// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'foundation.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$LoadableContainer<T> {

 T get value; bool get isLoaded;
/// Create a copy of LoadableContainer
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LoadableContainerCopyWith<T, LoadableContainer<T>> get copyWith => _$LoadableContainerCopyWithImpl<T, LoadableContainer<T>>(this as LoadableContainer<T>, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LoadableContainer<T>&&const DeepCollectionEquality().equals(other.value, value)&&(identical(other.isLoaded, isLoaded) || other.isLoaded == isLoaded));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(value),isLoaded);

@override
String toString() {
  return 'LoadableContainer<$T>(value: $value, isLoaded: $isLoaded)';
}


}

/// @nodoc
abstract mixin class $LoadableContainerCopyWith<T,$Res>  {
  factory $LoadableContainerCopyWith(LoadableContainer<T> value, $Res Function(LoadableContainer<T>) _then) = _$LoadableContainerCopyWithImpl;
@useResult
$Res call({
 T value, bool isLoaded
});




}
/// @nodoc
class _$LoadableContainerCopyWithImpl<T,$Res>
    implements $LoadableContainerCopyWith<T, $Res> {
  _$LoadableContainerCopyWithImpl(this._self, this._then);

  final LoadableContainer<T> _self;
  final $Res Function(LoadableContainer<T>) _then;

/// Create a copy of LoadableContainer
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? value = freezed,Object? isLoaded = null,}) {
  return _then(LoadableContainer(
value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as T,isLoaded: null == isLoaded ? _self.isLoaded : isLoaded // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [LoadableContainer].
extension LoadableContainerPatterns<T> on LoadableContainer<T> {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LoadableContainer<T> value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LoadableContainer() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LoadableContainer<T> value)  $default,){
final _that = this;
switch (_that) {
case _LoadableContainer():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LoadableContainer<T> value)?  $default,){
final _that = this;
switch (_that) {
case _LoadableContainer() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( T value,  bool isLoaded)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LoadableContainer() when $default != null:
return $default(_that.value,_that.isLoaded);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( T value,  bool isLoaded)  $default,) {final _that = this;
switch (_that) {
case _LoadableContainer():
return $default(_that.value,_that.isLoaded);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( T value,  bool isLoaded)?  $default,) {final _that = this;
switch (_that) {
case _LoadableContainer() when $default != null:
return $default(_that.value,_that.isLoaded);case _:
  return null;

}
}

}

/// @nodoc


class _LoadableContainer<T> extends LoadableContainer<T> {
  const _LoadableContainer({required this.value, this.isLoaded = false}): super._();
  

@override final  T value;
@override@JsonKey() final  bool isLoaded;

/// Create a copy of LoadableContainer
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LoadableContainerCopyWith<T, _LoadableContainer<T>> get copyWith => __$LoadableContainerCopyWithImpl<T, _LoadableContainer<T>>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _LoadableContainer<T>&&const DeepCollectionEquality().equals(other.value, value)&&(identical(other.isLoaded, isLoaded) || other.isLoaded == isLoaded));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(value),isLoaded);

@override
String toString() {
  return 'LoadableContainer<$T>(value: $value, isLoaded: $isLoaded)';
}


}

/// @nodoc
abstract mixin class _$LoadableContainerCopyWith<T,$Res> implements $LoadableContainerCopyWith<T, $Res> {
  factory _$LoadableContainerCopyWith(_LoadableContainer<T> value, $Res Function(_LoadableContainer<T>) _then) = __$LoadableContainerCopyWithImpl;
@override @useResult
$Res call({
 T value, bool isLoaded
});




}
/// @nodoc
class __$LoadableContainerCopyWithImpl<T,$Res>
    implements _$LoadableContainerCopyWith<T, $Res> {
  __$LoadableContainerCopyWithImpl(this._self, this._then);

  final _LoadableContainer<T> _self;
  final $Res Function(_LoadableContainer<T>) _then;

/// Create a copy of LoadableContainer
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? value = freezed,Object? isLoaded = null,}) {
  return _then(_LoadableContainer<T>(
value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as T,isLoaded: null == isLoaded ? _self.isLoaded : isLoaded // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$FieldContainer<T> {

 T get value; String get errorText; bool get isLoading;
/// Create a copy of FieldContainer
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FieldContainerCopyWith<T, FieldContainer<T>> get copyWith => _$FieldContainerCopyWithImpl<T, FieldContainer<T>>(this as FieldContainer<T>, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FieldContainer<T>&&const DeepCollectionEquality().equals(other.value, value)&&(identical(other.errorText, errorText) || other.errorText == errorText)&&(identical(other.isLoading, isLoading) || other.isLoading == isLoading));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(value),errorText,isLoading);

@override
String toString() {
  return 'FieldContainer<$T>(value: $value, errorText: $errorText, isLoading: $isLoading)';
}


}

/// @nodoc
abstract mixin class $FieldContainerCopyWith<T,$Res>  {
  factory $FieldContainerCopyWith(FieldContainer<T> value, $Res Function(FieldContainer<T>) _then) = _$FieldContainerCopyWithImpl;
@useResult
$Res call({
 T value, String errorText, bool isLoading
});




}
/// @nodoc
class _$FieldContainerCopyWithImpl<T,$Res>
    implements $FieldContainerCopyWith<T, $Res> {
  _$FieldContainerCopyWithImpl(this._self, this._then);

  final FieldContainer<T> _self;
  final $Res Function(FieldContainer<T>) _then;

/// Create a copy of FieldContainer
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? value = freezed,Object? errorText = null,Object? isLoading = null,}) {
  return _then(FieldContainer(
value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as T,errorText: null == errorText ? _self.errorText : errorText // ignore: cast_nullable_to_non_nullable
as String,isLoading: null == isLoading ? _self.isLoading : isLoading // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [FieldContainer].
extension FieldContainerPatterns<T> on FieldContainer<T> {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FieldContainer<T> value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FieldContainer() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FieldContainer<T> value)  $default,){
final _that = this;
switch (_that) {
case _FieldContainer():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FieldContainer<T> value)?  $default,){
final _that = this;
switch (_that) {
case _FieldContainer() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( T value,  String errorText,  bool isLoading)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FieldContainer() when $default != null:
return $default(_that.value,_that.errorText,_that.isLoading);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( T value,  String errorText,  bool isLoading)  $default,) {final _that = this;
switch (_that) {
case _FieldContainer():
return $default(_that.value,_that.errorText,_that.isLoading);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( T value,  String errorText,  bool isLoading)?  $default,) {final _that = this;
switch (_that) {
case _FieldContainer() when $default != null:
return $default(_that.value,_that.errorText,_that.isLoading);case _:
  return null;

}
}

}

/// @nodoc


class _FieldContainer<T> implements FieldContainer<T> {
  const _FieldContainer({required this.value, this.errorText = '', this.isLoading = false});
  

@override final  T value;
@override@JsonKey() final  String errorText;
@override@JsonKey() final  bool isLoading;

/// Create a copy of FieldContainer
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FieldContainerCopyWith<T, _FieldContainer<T>> get copyWith => __$FieldContainerCopyWithImpl<T, _FieldContainer<T>>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FieldContainer<T>&&const DeepCollectionEquality().equals(other.value, value)&&(identical(other.errorText, errorText) || other.errorText == errorText)&&(identical(other.isLoading, isLoading) || other.isLoading == isLoading));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(value),errorText,isLoading);

@override
String toString() {
  return 'FieldContainer<$T>(value: $value, errorText: $errorText, isLoading: $isLoading)';
}


}

/// @nodoc
abstract mixin class _$FieldContainerCopyWith<T,$Res> implements $FieldContainerCopyWith<T, $Res> {
  factory _$FieldContainerCopyWith(_FieldContainer<T> value, $Res Function(_FieldContainer<T>) _then) = __$FieldContainerCopyWithImpl;
@override @useResult
$Res call({
 T value, String errorText, bool isLoading
});




}
/// @nodoc
class __$FieldContainerCopyWithImpl<T,$Res>
    implements _$FieldContainerCopyWith<T, $Res> {
  __$FieldContainerCopyWithImpl(this._self, this._then);

  final _FieldContainer<T> _self;
  final $Res Function(_FieldContainer<T>) _then;

/// Create a copy of FieldContainer
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? value = freezed,Object? errorText = null,Object? isLoading = null,}) {
  return _then(_FieldContainer<T>(
value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as T,errorText: null == errorText ? _self.errorText : errorText // ignore: cast_nullable_to_non_nullable
as String,isLoading: null == isLoading ? _self.isLoading : isLoading // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
