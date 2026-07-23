import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('globalThis')
external JSObject get globalThis;

Future<T> promiseToFuture<T extends JSAny?>(final JSPromise<T> promise) =>
    promise.toDart;

Object? dartify(final Object? value) {
  if (value == null) {
    return null;
  }
  return (value as JSAny).dartify();
}

JSAny? jsifyAny(final Object? value) {
  if (value == null) {
    return null;
  }
  if (value is Map || value is List) {
    return value.jsify();
  }
  return value as JSAny;
}

JSAny? toJsArg(final Object? value) {
  if (value == null) {
    return null;
  }
  if (value is JSAny) {
    return value;
  }
  if (value is Map || value is List) {
    return value.jsify();
  }
  if (value is String) {
    return value.toJS;
  }
  if (value is int) {
    return value.toJS;
  }
  if (value is double) {
    return value.toJS;
  }
  if (value is bool) {
    return value.toJS;
  }
  if (value is Function) {
    return value.toJS;
  }
  throw ArgumentError.value(value, 'value', 'Cannot convert to JSAny');
}

List<JSAny?> jsInteropArgs(final List<Object?> args) =>
    args.map(toJsArg).toList();

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
  return (target as JSObject)[name];
}

bool hasGlobalProperty(final String name) => globalThis.has(name);

Object? globalProperty(final String name) => globalThis[name];

void setGlobalProperty(final String name, final Object? value) {
  globalThis[name] = toJsArg(value);
}

Object? jsCall(
  final Object? target,
  final String methodName,
  final List<Object?> args,
) {
  if (target == null) {
    throw StateError('Cannot call `$methodName` on null JS target.');
  }
  final object = target as JSObject;
  return object.callMethodVarArgs<JSAny?>(methodName.toJS, jsInteropArgs(args));
}

Object? jsCallConstructor(final Object constructor, final List<Object?> args) =>
    (constructor as JSFunction).callAsConstructorVarArgs<JSObject>(
      jsInteropArgs(args),
    );

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
  if (result is JSObject && result.has('then')) {
    return (result as JSPromise<JSAny?>).toDart;
  }
  return result;
}

JSAny? jsify(final Object? value) => jsifyAny(value);

JSAny allowInterop(final Function fn) => fn.toJS;

void jsCallListener(final Object? listener, final List<Object?> args) {
  jsCall(listener, 'call', args);
}

void runGuarded(final void Function() callback) {
  try {
    callback();
  } catch (error, stackTrace) {
    Zone.current.handleUncaughtError(error, stackTrace);
  }
}
