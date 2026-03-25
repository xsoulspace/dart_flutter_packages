// GENERATED CODE - DO NOT MODIFY BY HAND.
// Source: Web Speech API declaration snapshot
// ignore_for_file: avoid_types_as_parameter_names, camel_case_types, non_constant_identifier_names, unused_element

@JS()
library;

import 'dart:js_interop';

@JS('SpeechRecognition')
external JSFunction? get speechRecognitionConstructor;

@JS('webkitSpeechRecognition')
external JSFunction? get webkitSpeechRecognitionConstructor;

extension type SpeechRecognitionAlternativeRaw(JSObject _) implements JSObject {
  external JSString get transcript;
  external JSNumber get confidence;
}

extension type SpeechRecognitionResultRaw(JSObject _) implements JSObject {
  external JSBoolean get isFinal;
  external JSNumber get length;
  external SpeechRecognitionAlternativeRaw item(JSNumber index);
}

extension type SpeechRecognitionResultListRaw(JSObject _) implements JSObject {
  external JSNumber get length;
  external SpeechRecognitionResultRaw item(JSNumber index);
}

extension type SpeechRecognitionEventRaw(JSObject _) implements JSObject {
  external JSNumber get resultIndex;
  external SpeechRecognitionResultListRaw get results;
}

extension type SpeechRecognitionErrorEventRaw(JSObject _) implements JSObject {
  external JSString get error;
  external JSString? get message;
}

extension type SpeechRecognitionRaw(JSObject _) implements JSObject {
  external JSBoolean get continuous;
  external set continuous(JSBoolean value);

  external JSBoolean get interimResults;
  external set interimResults(JSBoolean value);

  external JSString get lang;
  external set lang(JSString value);

  external JSNumber get maxAlternatives;
  external set maxAlternatives(JSNumber value);

  external JSFunction? get onresult;
  external set onresult(JSFunction? value);

  external JSFunction? get onerror;
  external set onerror(JSFunction? value);

  external JSFunction? get onend;
  external set onend(JSFunction? value);

  external void start([JSAny? audioTrack]);
  external void stop();
  external void abort();
}
