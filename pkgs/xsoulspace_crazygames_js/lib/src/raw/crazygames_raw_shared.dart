@JS()
library;

import 'dart:js_interop';

import 'package:meta/meta.dart';

@internal
Future<T> promiseToFuture<T extends JSAny?>(final JSPromise<T> promise) =>
    promise.toDart;

@internal
Object? dartify(final JSObject? value) {
  if (value == null) {
    return null;
  }
  return value.dartify();
}

@internal
JSAny? jsifyAny(final Object? value) {
  if (value == null) {
    return null;
  }
  if (value is Map || value is List) {
    return value.jsify();
  }
  return value as JSAny;
}
