import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'raw/web_speech_recognition_raw.g.dart' as raw;
import 'web_speech_recognition_adapter.dart';

/// Live recognition session using microphone; continuous + interim results.
class BrowserWebSpeechLiveRecognitionSession
    implements WebSpeechLiveRecognitionSession {
  BrowserWebSpeechLiveRecognitionSession._({
    required raw.SpeechRecognitionRaw recognition,
    required StreamController<String> controller,
  })  : _recognition = recognition,
       _controller = controller;

  final raw.SpeechRecognitionRaw _recognition;
  final StreamController<String> _controller;
  bool _stopped = false;

  @override
  Stream<String> get transcriptStream => _controller.stream;

  @override
  void stop() {
    if (_stopped) return;
    _stopped = true;
    try {
      _recognition.stop();
    } catch (_) {}
    if (!_controller.isClosed) {
      _controller.close();
    }
  }

  void _onResult(final JSAny? event) {
    if (_controller.isClosed) return;
    final transcript = _extractTranscriptFromEvent(event);
    if (transcript != null && transcript.isNotEmpty) {
      _controller.add(transcript);
    }
  }

  void _onEnd(final JSAny? _) {
    if (!_controller.isClosed) {
      _controller.close();
    }
  }

  void _onError(final JSAny? _) {
    if (!_controller.isClosed) {
      _controller.close();
    }
  }

  static String? _extractTranscriptFromEvent(final JSAny? event) {
    final eventObject = _asJsObject(event);
    final resultsObject = _asJsObject(eventObject?['results']);
    final resultCount = _asInt(resultsObject?['length']) ?? 0;
    final buffer = StringBuffer();
    for (var index = 0; index < resultCount; index++) {
      final resultObject = _asJsObject(resultsObject?['$index']);
      if (resultObject == null) continue;
      final alternative = _asJsObject(resultObject['0']);
      final transcript = _asTrimmedString(alternative?['transcript']);
      if (transcript != null && transcript.isNotEmpty) {
        if (buffer.isNotEmpty) buffer.write(' ');
        buffer.write(transcript);
      }
    }
    final s = buffer.toString().trim();
    return s.isEmpty ? null : s;
  }

  static JSObject? _asJsObject(final JSAny? value) {
    // ignore: invalid_runtime_check_with_js_interop_types
    return value is JSObject ? value : null;
  }

  static int? _asInt(final JSAny? value) {
    final normalized = _dartify(value);
    if (normalized is int) return normalized;
    if (normalized is num) return (normalized).round();
    return null;
  }

  static String? _asTrimmedString(final JSAny? value) {
    final normalized = _dartify(value);
    if (normalized is! String) return null;
    final text = normalized.trim();
    return text.isEmpty ? null : text;
  }

  static Object? _dartify(final JSAny? value) {
    if (value == null) return null;
    try {
      return value.dartify();
    } catch (_) {
      return null;
    }
  }
}

abstract interface class WebSpeechRecognitionTrackProvider {
  Future<WebSpeechRecognitionAudioTrackHandle> fromFileUrl({
    required String fileUrl,
    required String mimeType,
  });

  Future<WebSpeechRecognitionAudioTrackHandle> fromBytes({
    required List<int> bytes,
    required String mimeType,
  });
}

final class WebSpeechRecognitionAudioTrackHandle {
  WebSpeechRecognitionAudioTrackHandle({
    required this.audioTrack,
    required Future<void> Function() dispose,
  }) : _dispose = dispose;

  final JSAny audioTrack;
  final Future<void> Function() _dispose;

  Future<void> dispose() => _dispose();
}

class BrowserWebSpeechRecognitionTrackProvider
    implements WebSpeechRecognitionTrackProvider {
  const BrowserWebSpeechRecognitionTrackProvider({
    this.loadTimeout = const Duration(seconds: 10),
  });

  final Duration loadTimeout;

  @override
  Future<WebSpeechRecognitionAudioTrackHandle> fromFileUrl({
    required final String fileUrl,
    required final String mimeType,
  }) {
    return _buildTrackHandle(fileUrl: fileUrl, objectUrlToRevoke: null);
  }

  @override
  Future<WebSpeechRecognitionAudioTrackHandle> fromBytes({
    required final List<int> bytes,
    required final String mimeType,
  }) async {
    final typedBytes = Uint8List.fromList(bytes);
    final blob = web.Blob(
      <web.BlobPart>[typedBytes.toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    );

    final objectUrl = web.URL.createObjectURL(blob);
    try {
      return await _buildTrackHandle(
        fileUrl: objectUrl,
        objectUrlToRevoke: objectUrl,
      );
    } catch (_) {
      web.URL.revokeObjectURL(objectUrl);
      rethrow;
    }
  }

  Future<WebSpeechRecognitionAudioTrackHandle> _buildTrackHandle({
    required final String fileUrl,
    required final String? objectUrlToRevoke,
  }) async {
    final audio = web.HTMLAudioElement()
      ..preload = 'auto'
      ..muted = true
      ..src = fileUrl;

    await _waitUntilPlayable(audio);

    try {
      await audio.play().toDart;
    } catch (error) {
      throw WebSpeechRecognitionAdapterException(
        kind: WebSpeechRecognitionFailureKind.invalidCaptureOrInput,
        reason: 'audio_play_failed',
        message: 'Failed to play the provided audio source in browser runtime',
        details: error.toString(),
      );
    }

    final stream = audio.captureStream();
    final tracks = stream.getAudioTracks().toDart;
    if (tracks.isEmpty) {
      throw const WebSpeechRecognitionAdapterException(
        kind: WebSpeechRecognitionFailureKind.invalidCaptureOrInput,
        reason: 'audio_track_missing',
        message: 'captureStream() produced no audio tracks',
      );
    }

    return WebSpeechRecognitionAudioTrackHandle(
      audioTrack: tracks.first,
      dispose: () async {
        try {
          for (final track in stream.getTracks().toDart) {
            track.stop();
          }
        } catch (_) {
          // best-effort cleanup
        }

        try {
          audio.pause();
          audio.src = '';
          audio.load();
        } catch (_) {
          // best-effort cleanup
        }

        if (objectUrlToRevoke != null) {
          web.URL.revokeObjectURL(objectUrlToRevoke);
        }
      },
    );
  }

  Future<void> _waitUntilPlayable(final web.HTMLAudioElement audio) async {
    final completer = Completer<void>();

    void completeReady() {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }

    void completeError(final Object error) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }

    audio.oncanplay = ((JSAny? _) => completeReady()).toJS;
    audio.onloadedmetadata = ((JSAny? _) => completeReady()).toJS;
    audio.onerror = ((JSAny? _) {
      completeError(
        const WebSpeechRecognitionAdapterException(
          kind: WebSpeechRecognitionFailureKind.invalidCaptureOrInput,
          reason: 'audio_load_failed',
          message: 'Failed to load browser audio source for captureStream()',
        ),
      );
    }).toJS;

    audio.load();

    try {
      await completer.future.timeout(
        loadTimeout,
        onTimeout: () {
          throw const WebSpeechRecognitionAdapterException(
            kind: WebSpeechRecognitionFailureKind.invalidCaptureOrInput,
            reason: 'audio_load_timeout',
            message: 'Timed out while loading browser audio source',
          );
        },
      );
    } finally {
      audio.oncanplay = null;
      audio.onloadedmetadata = null;
      audio.onerror = null;
    }
  }
}

class BrowserWebSpeechRecognitionAdapter
    implements WebSpeechRecognitionAdapter {
  BrowserWebSpeechRecognitionAdapter({
    final WebSpeechRecognitionTrackProvider? audioTrackProvider,
    final String Function()? userAgentProvider,
    this.sessionTimeout = const Duration(seconds: 30),
  }) : _audioTrackProvider =
           audioTrackProvider ??
           const BrowserWebSpeechRecognitionTrackProvider(),
       _userAgentProvider =
           userAgentProvider ?? (() => web.window.navigator.userAgent);

  final WebSpeechRecognitionTrackProvider _audioTrackProvider;
  final String Function() _userAgentProvider;
  final Duration sessionTimeout;

  @override
  bool get hasSpeechRecognitionApi => _resolveConstructor() != null;

  @override
  bool get isChromiumFamily => _isChromiumFamily(_userAgentProvider());

  @override
  Future<String> recognize({
    required final InferenceAudioInput audioInput,
    final String? language,
  }) async {
    final source = audioInput.resolvedSource;
    if (source == null) {
      throw const WebSpeechRecognitionAdapterException(
        kind: WebSpeechRecognitionFailureKind.invalidCaptureOrInput,
        reason: 'source_missing',
        message: 'Audio input source must be microphone, file_path, or bytes',
      );
    }

    final recognition = _createRecognition();
    recognition.continuous = false.toJS;
    recognition.interimResults = false.toJS;
    recognition.maxAlternatives = 1.toJS;
    if (language != null && language.trim().isNotEmpty) {
      recognition.lang = language.trim().toJS;
    }

    WebSpeechRecognitionAudioTrackHandle? trackHandle;

    try {
      switch (source) {
        case InferenceAudioSource.microphone:
          return _runRecognitionSession(
            recognition: recognition,
            withAudioTrack: false,
            startRecognition: () => recognition.start(),
          );
        case InferenceAudioSource.filePath:
          final fileUrl = (audioInput.filePath ?? '').trim();
          _validateBrowserLoadableUrl(fileUrl);
          trackHandle = await _audioTrackProvider.fromFileUrl(
            fileUrl: fileUrl,
            mimeType: audioInput.mimeType,
          );
          return _runRecognitionSession(
            recognition: recognition,
            withAudioTrack: true,
            startRecognition: () => recognition.start(trackHandle!.audioTrack),
          );
        case InferenceAudioSource.bytes:
          final bytes = audioInput.bytes ?? const <int>[];
          if (bytes.isEmpty) {
            throw const WebSpeechRecognitionAdapterException(
              kind: WebSpeechRecognitionFailureKind.invalidCaptureOrInput,
              reason: 'bytes_empty',
              message: 'Bytes audio input must not be empty',
            );
          }
          trackHandle = await _audioTrackProvider.fromBytes(
            bytes: bytes,
            mimeType: audioInput.mimeType,
          );
          return _runRecognitionSession(
            recognition: recognition,
            withAudioTrack: true,
            startRecognition: () => recognition.start(trackHandle!.audioTrack),
          );
      }
    } finally {
      if (trackHandle != null) {
        await trackHandle.dispose();
      }
    }
  }

  @override
  WebSpeechLiveRecognitionSession? startLiveRecognition({
    final String? language,
  }) {
    if (!hasSpeechRecognitionApi) return null;
    try {
      final recognition = _createRecognition();
      recognition.continuous = true.toJS;
      recognition.interimResults = true.toJS;
      recognition.maxAlternatives = 1.toJS;
      if (language != null && language.trim().isNotEmpty) {
        recognition.lang = language.trim().toJS;
      }
      final controller = StreamController<String>.broadcast();
      final session = BrowserWebSpeechLiveRecognitionSession._(
        recognition: recognition,
        controller: controller,
      );
      recognition.onresult = ((final JSAny? event) => session._onResult(event)).toJS;
      recognition.onend = ((final JSAny? e) => session._onEnd(e)).toJS;
      recognition.onerror = ((final JSAny? e) => session._onError(e)).toJS;
      try {
        recognition.start();
      } catch (_) {
        session.stop();
        return null;
      }
      return session;
    } catch (_) {
      return null;
    }
  }

  Future<String> _runRecognitionSession({
    required final raw.SpeechRecognitionRaw recognition,
    required final bool withAudioTrack,
    required final void Function() startRecognition,
  }) async {
    final transcriptCompleter = Completer<String>();
    var sawFinalResult = false;

    void completeError(final WebSpeechRecognitionAdapterException error) {
      if (!transcriptCompleter.isCompleted) {
        transcriptCompleter.completeError(error);
      }
    }

    recognition.onresult = ((final JSAny? event) {
      final transcript = _extractFinalTranscript(event);
      if (transcript == null || transcript.isEmpty) {
        return;
      }

      sawFinalResult = true;
      if (!transcriptCompleter.isCompleted) {
        transcriptCompleter.complete(transcript);
      }
    }).toJS;

    recognition.onerror = ((final JSAny? event) {
      completeError(_mapRecognitionErrorEvent(event));
    }).toJS;

    recognition.onend = ((final JSAny? _) {
      if (!transcriptCompleter.isCompleted && !sawFinalResult) {
        completeError(
          const WebSpeechRecognitionAdapterException(
            kind: WebSpeechRecognitionFailureKind
                .runtimeEngineOrNetworkOrLanguage,
            reason: 'session_ended_without_final_result',
            message:
                'SpeechRecognition session ended before a final transcript was produced',
          ),
        );
      }
    }).toJS;

    try {
      startRecognition();
    } catch (error) {
      completeError(_mapStartFailure(error, withAudioTrack: withAudioTrack));
    }

    final timeoutFuture = Future<String>.delayed(sessionTimeout, () {
      throw const WebSpeechRecognitionAdapterException(
        kind: WebSpeechRecognitionFailureKind.runtimeEngineOrNetworkOrLanguage,
        reason: 'session_timeout',
        message: 'SpeechRecognition session timed out',
      );
    });

    try {
      return await Future.any(<Future<String>>[
        transcriptCompleter.future,
        timeoutFuture,
      ]);
    } finally {
      recognition.onresult = null;
      recognition.onerror = null;
      recognition.onend = null;
      try {
        recognition.stop();
      } catch (_) {
        // best-effort cleanup
      }
    }
  }

  raw.SpeechRecognitionRaw _createRecognition() {
    final constructor = _resolveConstructor();
    if (constructor == null) {
      throw const WebSpeechRecognitionAdapterException(
        kind: WebSpeechRecognitionFailureKind.unsupported,
        reason: 'speech_recognition_constructor_missing',
        message:
            'SpeechRecognition constructor is not available in this browser runtime',
      );
    }

    final object = constructor.callAsConstructorVarArgs<JSObject>();
    return raw.SpeechRecognitionRaw(object);
  }

  JSFunction? _resolveConstructor() =>
      raw.speechRecognitionConstructor ??
      raw.webkitSpeechRecognitionConstructor;

  void _validateBrowserLoadableUrl(final String fileUrl) {
    if (fileUrl.isEmpty) {
      throw const WebSpeechRecognitionAdapterException(
        kind: WebSpeechRecognitionFailureKind.invalidCaptureOrInput,
        reason: 'file_url_empty',
        message: 'File-path audio input must provide a browser-loadable URL',
      );
    }

    final uri = Uri.tryParse(fileUrl);
    if (uri == null || !uri.hasScheme) {
      throw const WebSpeechRecognitionAdapterException(
        kind: WebSpeechRecognitionFailureKind.invalidCaptureOrInput,
        reason: 'file_url_invalid',
        message: 'File-path audio input must be an absolute browser URL',
      );
    }

    const allowedSchemes = <String>{'https', 'blob', 'data'};
    if (!allowedSchemes.contains(uri.scheme.toLowerCase())) {
      throw WebSpeechRecognitionAdapterException(
        kind: WebSpeechRecognitionFailureKind.invalidCaptureOrInput,
        reason: 'file_url_scheme_unsupported',
        message: 'Unsupported audio URL scheme for browser playback',
        details: <String, dynamic>{
          'url': fileUrl,
          'allowed_schemes': allowedSchemes.toList(growable: false),
        },
      );
    }
  }

  WebSpeechRecognitionAdapterException _mapStartFailure(
    final Object error, {
    required final bool withAudioTrack,
  }) {
    final rawError = error.toString();
    final lower = rawError.toLowerCase();

    if (withAudioTrack && _looksLikeAudioTrackUnsupported(lower)) {
      return WebSpeechRecognitionAdapterException(
        kind: WebSpeechRecognitionFailureKind.unsupported,
        reason: 'audio_track_start_unsupported',
        message:
            'SpeechRecognition.start(audioTrack) is unsupported at runtime',
        details: <String, dynamic>{'raw_error': rawError},
      );
    }

    if (_containsAny(lower, const <String>['not-allowed', 'permission'])) {
      return WebSpeechRecognitionAdapterException(
        kind: WebSpeechRecognitionFailureKind.permissionOrServiceBlocked,
        reason: 'permission_or_service_blocked',
        message: 'Speech recognition is blocked by browser permission/policy',
        details: <String, dynamic>{'raw_error': rawError},
      );
    }

    if (_containsAny(lower, const <String>[
      'audio-capture',
      'capture',
      'track',
      'invalid',
    ])) {
      return WebSpeechRecognitionAdapterException(
        kind: WebSpeechRecognitionFailureKind.invalidCaptureOrInput,
        reason: 'audio_input_or_capture_invalid',
        message:
            'Speech recognition could not start for the provided audio input',
        details: <String, dynamic>{'raw_error': rawError},
      );
    }

    return WebSpeechRecognitionAdapterException(
      kind: WebSpeechRecognitionFailureKind.runtimeEngineOrNetworkOrLanguage,
      reason: 'start_failed',
      message: 'Speech recognition failed to start in browser runtime',
      details: <String, dynamic>{'raw_error': rawError},
    );
  }

  WebSpeechRecognitionAdapterException _mapRecognitionErrorEvent(
    final JSAny? event,
  ) {
    final eventObject = _asJsObject(event);
    final errorCode = _asTrimmedString(eventObject?['error'])?.toLowerCase();
    final eventMessage = _asTrimmedString(eventObject?['message']);

    final details = <String, dynamic>{
      ...?errorCode == null ? null : <String, dynamic>{'error': errorCode},
      ...?eventMessage == null
          ? null
          : <String, dynamic>{'event_message': eventMessage},
    };

    switch (errorCode) {
      case 'not-allowed':
      case 'service-not-allowed':
        return WebSpeechRecognitionAdapterException(
          kind: WebSpeechRecognitionFailureKind.permissionOrServiceBlocked,
          reason: 'permission_or_service_blocked',
          message: 'Speech recognition is blocked by browser permission/policy',
          details: details,
        );
      case 'audio-capture':
      case 'aborted':
      case 'no-speech':
        return WebSpeechRecognitionAdapterException(
          kind: WebSpeechRecognitionFailureKind.invalidCaptureOrInput,
          reason: 'audio_input_or_capture_invalid',
          message: 'Speech recognition failed for the provided audio input',
          details: details,
        );
      case 'network':
      case 'language-not-supported':
      case 'bad-grammar':
      default:
        return WebSpeechRecognitionAdapterException(
          kind:
              WebSpeechRecognitionFailureKind.runtimeEngineOrNetworkOrLanguage,
          reason: 'runtime_engine_or_network_failure',
          message:
              'Speech recognition engine is unavailable in current runtime',
          details: details,
        );
    }
  }

  String? _extractFinalTranscript(final JSAny? event) {
    final eventObject = _asJsObject(event);
    final resultsObject = _asJsObject(eventObject?['results']);
    final resultCount = _asInt(resultsObject?['length']) ?? 0;

    for (var index = 0; index < resultCount; index++) {
      final resultObject = _asJsObject(resultsObject?['$index']);
      if (resultObject == null) {
        continue;
      }

      final isFinal = _asBool(resultObject['isFinal']) ?? false;
      if (!isFinal) {
        continue;
      }

      final alternative = _asJsObject(resultObject['0']);
      final transcript = _asTrimmedString(alternative?['transcript']);
      if (transcript != null && transcript.isNotEmpty) {
        return transcript;
      }
    }

    return null;
  }

  static bool _containsAny(final String value, final Iterable<String> needles) {
    for (final needle in needles) {
      if (value.contains(needle)) {
        return true;
      }
    }
    return false;
  }

  static bool _looksLikeAudioTrackUnsupported(final String lowerError) {
    return _containsAny(lowerError, const <String>[
      'too many arguments',
      'overload',
      'unsupported',
      'not implemented',
      'no matching signature',
    ]);
  }

  static bool _isChromiumFamily(final String userAgent) {
    final ua = userAgent.toLowerCase();
    return _containsAny(ua, const <String>[
      'chrome/',
      'chromium',
      'edg/',
      'opr/',
      'brave/',
    ]);
  }

  static JSObject? _asJsObject(final JSAny? value) {
    // ignore: invalid_runtime_check_with_js_interop_types
    return value is JSObject ? value : null;
  }

  static bool? _asBool(final JSAny? value) {
    final normalized = _dartify(value);
    if (normalized is bool) {
      return normalized;
    }
    return null;
  }

  static int? _asInt(final JSAny? value) {
    final normalized = _dartify(value);
    if (normalized is int) {
      return normalized;
    }
    if (normalized is num) {
      return normalized.round();
    }
    return null;
  }

  static String? _asTrimmedString(final JSAny? value) {
    final normalized = _dartify(value);
    if (normalized is! String) {
      return null;
    }

    final text = normalized.trim();
    return text.isEmpty ? null : text;
  }

  static Object? _dartify(final JSAny? value) {
    if (value == null) {
      return null;
    }

    try {
      return value.dartify();
    } catch (_) {
      return null;
    }
  }
}
