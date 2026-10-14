import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('globalThis')
external JSObject get globalThis;

Future<T> promiseToFuture<T extends JSAny?>(JSPromise<T> promise) =>
    promise.toDart;

Object? dartify(Object? value) {
  if (value == null) {
    return null;
  }
  return (value as JSAny).dartify();
}

JSAny? jsifyAny(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is Map || value is List) {
    return value.jsify();
  }
  return value as JSAny;
}

JSAny? toJsArg(Object? value) {
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

List<JSAny?> jsInteropArgs(List<Object?> args) =>
    args.map(toJsArg).toList();

Map<String, Object?> asMap(Object? value) {
  final dart = dartify(value);
  if (dart is Map<Object?, Object?>) {
    return dart.map(
      (key, mapValue) => MapEntry(key?.toString() ?? '', mapValue),
    );
  }
  return <String, Object?>{};
}

List<Object?> asList(Object? value) {
  final dart = dartify(value);
  if (dart is List<Object?>) {
    return dart;
  }
  if (dart is List<dynamic>) {
    return dart.cast<Object?>();
  }
  return <Object?>[];
}

String asString(Object? value, {String fallback = ''}) {
  if (value is String) {
    return value;
  }
  return fallback;
}

int asInt(Object? value, {int fallback = 0}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return fallback;
}

double asDouble(Object? value, {double fallback = 0}) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  return fallback;
}

bool asBool(Object? value, {bool fallback = false}) {
  if (value is bool) {
    return value;
  }
  return fallback;
}

Object? prop(Object? target, String name) {
  if (target == null) {
    return null;
  }
  return (target as JSObject)[name];
}

bool hasGlobalProperty(String name) => globalThis.has(name);

Object? globalProperty(String name) => globalThis[name];

void setGlobalProperty(String name, Object? value) {
  globalThis[name] = toJsArg(value);
}

Object? jsCall(
  Object? target,
  String methodName,
  List<Object?> args,
) {
  if (target == null) {
    throw StateError('Cannot call `$methodName` on null JS target.');
  }
  final object = target as JSObject;
  return object.callMethodVarArgs<JSAny?>(methodName.toJS, jsInteropArgs(args));
}

Object? jsCallConstructor(Object constructor, List<Object?> args) =>
    (constructor as JSFunction).callAsConstructorVarArgs<JSObject>(
      jsInteropArgs(args),
    );

Future<Object?> jsCallPromise(
  Object? target,
  String methodName, [
  List<Object?> args = const <Object?>[],
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

JSAny? jsify(Object? value) => jsifyAny(value);

JSAny allowInterop(Function fn) => fn.toJS;

void jsCallListener(Object? listener, List<Object?> args) {
  jsCall(listener, 'call', args);
}

void runGuarded(void Function() callback) {
  try {
    callback();
  } catch (error, stackTrace) {
    Zone.current.handleUncaughtError(error, stackTrace);
  }
}
