import 'dart:async';
import 'dart:js_interop';
import 'dart:js_util' as js_util;

import '../raw/crazygames_raw_shared.dart';

Map<String, Object?> asMap(final Object? value) {
  final dart = dartify(value);
  if (dart is Map<Object?, Object?>) {
    return dart.map(
      (final key, final mapValue) => MapEntry(key?.toString() ?? '', mapValue),
    );
  }
  return <String, Object?>{};
}

List<Object?> asList(final Object? value) {
  final dart = dartify(value);
  if (dart is List<Object?>) {
    return dart;
  }
  if (dart is List<dynamic>) {
    return dart.cast<Object?>();
  }
  return <Object?>[];
}

String asString(final Object? value, {final String fallback = ''}) {
  if (value is String) {
    return value;
  }
  return fallback;
}

int asInt(final Object? value, {final int fallback = 0}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return fallback;
}

double asDouble(final Object? value, {final double fallback = 0}) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  return fallback;
}

bool asBool(final Object? value, {final bool fallback = false}) {
  if (value is bool) {
    return value;
  }
  return fallback;
}

Object? prop(final Object? target, final String name) {
  if (target == null) {
    return null;
  }
  return js_util.getProperty<Object?>(target, name);
}

Object? jsCall(
  final Object? target,
  final String methodName,
  final List<Object?> args,
) {
  if (target == null) {
    throw StateError('Cannot call `$methodName` on null JS target.');
  }
  return js_util.callMethod<Object?>(target, methodName, args);
}

Future<Object?> jsCallPromise(
  final Object? target,
  final String methodName, [
  final List<Object?> args = const <Object?>[],
]) async {
  final result = jsCall(target, methodName, args);
  if (result == null) {
    return null;
  }
  if (result is bool || result is num || result is String) {
    return result;
  }
  if (js_util.hasProperty(result, 'then')) {
    return js_util.promiseToFuture<Object?>(result);
  }
  return result;
}

JSAny? jsify(final Object? value) => jsifyAny(value);

Object allowInterop(final Function fn) => js_util.allowInterop(fn);

void runGuarded(final void Function() callback) {
  try {
    callback();
  } catch (error, stackTrace) {
    Zone.current.handleUncaughtError(error, stackTrace);
  }
}
