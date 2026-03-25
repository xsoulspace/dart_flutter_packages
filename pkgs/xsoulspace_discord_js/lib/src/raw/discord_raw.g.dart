// GENERATED CODE - DO NOT MODIFY BY HAND.
// Source: @discord/embedded-app-sdk@2.4.0
// ignore_for_file: avoid_types_as_parameter_names, camel_case_types, non_constant_identifier_names, unused_element

@JS()
library;

import 'dart:js_interop';

@JS('DiscordSDK')
external JSAny? get DiscordSDK;

extension type DiscordSdkRaw(JSObject _) implements JSObject {
  external JSPromise<JSAny?> ready();

  external JSAny? get commands;

  external JSPromise<JSAny?> subscribe(
    JSString event,
    JSFunction listener, [
    JSAny? subscribeArgs,
  ]);

  external JSPromise<JSAny?> unsubscribe(
    JSString event,
    JSFunction listener, [
    JSAny? unsubscribeArgs,
  ]);
}
