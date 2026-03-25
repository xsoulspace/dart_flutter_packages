// GENERATED CODE - DO NOT MODIFY BY HAND.
// Source: vkplay-iframe-api@0.1.0
// ignore_for_file: avoid_types_as_parameter_names, camel_case_types, non_constant_identifier_names, unused_element

@JS()
library;

import 'dart:js_interop';

@JS('iframeApi')
external VkPlayApiRaw? get iframeApi;

extension type VkPlayApiRaw(JSObject _) implements JSObject {
  external JSPromise<JSAny?> init([JSAny? options]);
  external JSPromise<JSAny?> getLoginStatus();
  external JSPromise<JSAny?> userInfo();
  external JSPromise<JSAny?> userProfile();
  external JSPromise<JSAny?> userFriends([JSAny? options]);
  external JSPromise<JSAny?> userSocialFriends([JSAny? options]);
  external JSPromise<JSAny?> showInviteBox(JSAny? payload);
  external JSPromise<JSAny?> postToFeed(JSAny? payload);
}
