@TestOn('browser')
library;

import 'dart:async';
import 'dart:collection';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_web_speech_recognition/src/raw/web_speech_recognition_raw.g.dart'
    as raw;
import 'package:xsoulspace_inference_web_speech_recognition/src/web_speech_recognition_inference_client_web.dart';

void main() {
  late JSAny? originalSpeechRecognition;
  late JSAny? originalWebkitSpeechRecognition;

  setUp(() {
    originalSpeechRecognition = globalContext['SpeechRecognition'];
    originalWebkitSpeechRecognition = globalContext['webkitSpeechRecognition'];
  });

  tearDown(() {
    globalContext['SpeechRecognition'] = originalSpeechRecognition;
    globalContext['webkitSpeechRecognition'] = originalWebkitSpeechRecognition;
  });

  test('raw binding resolves SpeechRecognition constructor path', () {
    final stub = _SpeechRecognitionGlobalStub(
      transcripts: const <String>['hello'],
    )..install();

    expect(raw.speechRecognitionConstructor, isNotNull);
    expect(raw.webkitSpeechRecognitionConstructor, isNull);

    final instance = raw.speechRecognitionConstructor!
        .callAsConstructorVarArgs<JSObject>();
    final recognition = raw.SpeechRecognitionRaw(instance);
    recognition.maxAlternatives = 1.toJS;

    expect(stub.createdInstances, 1);
  });

  test('microphone recognition session returns transcript', () async {
    final stub = _SpeechRecognitionGlobalStub(
      transcripts: const <String>['mic transcript'],
    )..install();

    final client = WebSpeechRecognitionInferenceClient(
      adapter: BrowserWebSpeechRecognitionAdapter(
        userAgentProvider: () => 'Mozilla/5.0 Chrome/124.0.0.0 Safari/537.36',
      ),
    );

    final result = await client.infer(
      InferenceRequest.speechToText(
        audioInput: const InferenceAudioInput.microphone(
          mimeType: 'audio/webm',
        ),
      ),
    );

    expect(result.success, isTrue);
    expect(result.data?.transcript, 'mic transcript');
    expect(stub.startCallCount, 1);
    expect(stub.startWithTrackCount, 0);
  });

  test('file-url recognition session uses audioTrack start path', () async {
    final stub = _SpeechRecognitionGlobalStub(
      transcripts: const <String>['file transcript'],
    )..install();
    final trackProvider = _FakeTrackProvider();

    final client = WebSpeechRecognitionInferenceClient(
      adapter: BrowserWebSpeechRecognitionAdapter(
        userAgentProvider: () => 'Mozilla/5.0 Chrome/124.0.0.0 Safari/537.36',
        audioTrackProvider: trackProvider,
      ),
    );

    final result = await client.infer(
      InferenceRequest.speechToText(
        audioInput: const InferenceAudioInput.filePath(
          filePath: 'https://example.com/audio.wav',
          mimeType: 'audio/wav',
        ),
      ),
    );

    expect(result.success, isTrue);
    expect(result.data?.transcript, 'file transcript');
    expect(stub.startCallCount, 1);
    expect(stub.startWithTrackCount, 1);
    expect(trackProvider.fileCalls, 1);
    expect(trackProvider.disposeCalls, 1);
  });

  test('bytes recognition session uses audioTrack start path', () async {
    final stub = _SpeechRecognitionGlobalStub(
      transcripts: const <String>['bytes transcript'],
    )..install();
    final trackProvider = _FakeTrackProvider();

    final client = WebSpeechRecognitionInferenceClient(
      adapter: BrowserWebSpeechRecognitionAdapter(
        userAgentProvider: () => 'Mozilla/5.0 Chrome/124.0.0.0 Safari/537.36',
        audioTrackProvider: trackProvider,
      ),
    );

    final result = await client.infer(
      InferenceRequest.speechToText(
        audioInput: const InferenceAudioInput.bytes(
          bytes: <int>[1, 2, 3, 4],
          mimeType: 'audio/webm',
        ),
      ),
    );

    expect(result.success, isTrue);
    expect(result.data?.transcript, 'bytes transcript');
    expect(stub.startCallCount, 1);
    expect(stub.startWithTrackCount, 1);
    expect(trackProvider.bytesCalls, 1);
    expect(trackProvider.disposeCalls, 1);
  });
}

class _FakeTrackProvider implements WebSpeechRecognitionTrackProvider {
  int fileCalls = 0;
  int bytesCalls = 0;
  int disposeCalls = 0;

  final JSObject _track = JSObject();

  @override
  Future<WebSpeechRecognitionAudioTrackHandle> fromFileUrl({
    required final String fileUrl,
    required final String mimeType,
  }) async {
    fileCalls += 1;
    return _buildHandle();
  }

  @override
  Future<WebSpeechRecognitionAudioTrackHandle> fromBytes({
    required final List<int> bytes,
    required final String mimeType,
  }) async {
    bytesCalls += 1;
    return _buildHandle();
  }

  WebSpeechRecognitionAudioTrackHandle _buildHandle() {
    return WebSpeechRecognitionAudioTrackHandle(
      audioTrack: _track,
      dispose: () async {
        disposeCalls += 1;
      },
    );
  }
}

class _SpeechRecognitionGlobalStub {
  _SpeechRecognitionGlobalStub({required final List<String> transcripts})
    : _transcripts = Queue<String>.from(transcripts);

  final Queue<String> _transcripts;

  int createdInstances = 0;
  int startCallCount = 0;
  int startWithTrackCount = 0;

  void install() {
    globalContext['SpeechRecognition'] = _buildConstructor();
    globalContext['webkitSpeechRecognition'] = null;
  }

  JSFunction _buildConstructor() {
    return (() {
      createdInstances += 1;

      final recognition = JSObject();
      recognition['continuous'] = false.toJS;
      recognition['interimResults'] = false.toJS;
      recognition['maxAlternatives'] = 1.toJS;
      recognition['lang'] = ''.toJS;
      recognition['onresult'] = null;
      recognition['onerror'] = null;
      recognition['onend'] = null;

      recognition['start'] = (([final JSAny? track]) {
        startCallCount += 1;
        if (track != null) {
          startWithTrackCount += 1;
        }

        scheduleMicrotask(() {
          final transcript = _transcripts.isEmpty
              ? 'fallback transcript'
              : _transcripts.removeFirst();
          _emitResult(recognition, transcript);
          _emitEnd(recognition);
        });
      }).toJS;

      recognition['stop'] = (() {}).toJS;
      recognition['abort'] = (() {}).toJS;

      return recognition;
    }).toJS;
  }

  void _emitResult(final JSObject recognition, final String transcript) {
    final callback = recognition['onresult'];
    // ignore: invalid_runtime_check_with_js_interop_types
    if (callback is! JSObject) {
      return;
    }

    final alternative = JSObject();
    alternative['transcript'] = transcript.toJS;

    final result = JSObject();
    result['isFinal'] = true.toJS;
    result['length'] = 1.toJS;
    result['0'] = alternative;

    final results = JSObject();
    results['length'] = 1.toJS;
    results['0'] = result;

    final event = JSObject();
    event['resultIndex'] = 0.toJS;
    event['results'] = results;

    callback.callMethodVarArgs<JSAny?>('call'.toJS, <JSAny?>[null, event]);
  }

  void _emitEnd(final JSObject recognition) {
    final callback = recognition['onend'];
    // ignore: invalid_runtime_check_with_js_interop_types
    if (callback is! JSObject) {
      return;
    }

    final event = JSObject();
    callback.callMethodVarArgs<JSAny?>('call'.toJS, <JSAny?>[null, event]);
  }
}
