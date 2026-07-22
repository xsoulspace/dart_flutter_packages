@JS()
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe' as js_util_unsafe;

import 'package:meta/meta.dart';
import 'package:web/web.dart' as web;

@internal
Future<T> promiseToFuture<T extends JSAny?>(final JSPromise<T> promise) =>
    js_util.promiseToFuture<T>(promise as Object);

@internal
Object? dartify(final Object? value) {
  if (value == null) {
    return null;
  }
  return js_util.dartify(value);
}

@internal
JSAny? jsifyAny(final Object? value) {
  if (value == null) {
    return null;
  }
  if (value is Map || value is List) {
    return js_util.jsify(value) as JSAny;
  }
  return value as JSAny;
}
