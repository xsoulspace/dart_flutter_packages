@JS()
library;

import 'dart:js_interop';

import 'package:meta/meta.dart';
import 'package:xsoulspace_js_interop_runtime/xsoulspace_js_interop_runtime.dart'
    as js_runtime;

@internal
Future<T> promiseToFuture<T extends JSAny?>(final JSPromise<T> promise) =>
    js_runtime.promiseToFuture<T>(promise);

@internal
Object? dartify(final Object? value) => js_runtime.dartify(value);

@internal
JSAny? jsifyAny(final Object? value) => js_runtime.jsifyAny(value);
